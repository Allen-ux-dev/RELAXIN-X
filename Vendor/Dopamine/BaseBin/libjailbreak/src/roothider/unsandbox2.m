#import <Foundation/Foundation.h>

#include <stdio.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/event.h>
#include <sys/syscall.h>
#include <libgen.h>

#include "../libjailbreak.h"
#include "../info.h"
#include "unsandbox.h"
#include "common.h"
#include "../log.h"

// ==================== iOS 16.4 xnu-8796 use smrq_link ====================

#define SMR_POINTER_DECL(name, type_t) \
	struct name { type_t volatile __smr_ptr; }

#define SMR_POINTER(type_t) \
	SMR_POINTER_DECL(, type_t)

typedef SMR_POINTER(struct smrq_link *) __smrq_link_t;

struct smrq_link {
    struct smrq_link *le_next;
    struct smrq_link **le_prev;
};

struct namecache_v2 {
    TAILQ_ENTRY(namecache_v2) nc_entry; /* chain of all entries */
    TAILQ_ENTRY(namecache_v2) nc_child; /* chain of ncp's that are children of a vp */
    union {
        LIST_ENTRY(namecache_v2) nc_link;      /* chain of ncp's that 'name' a vp */
        TAILQ_ENTRY(namecache_v2) nc_negentry; /* chain of ncp's that 'name' a vp */
    } nc_un;
    struct smrq_link nc_hash; /* hash chain */
    uint32_t nc_vid;          /* vid for nc_vp */
    uint32_t nc_counter;      /* flags */
    vnode_t nc_dvp;           /* vnode of parent of name */
    vnode_t nc_vp;            /* vnode the name refers to */
    unsigned int nc_hashval;  /* hashval of stringname */
    const char *nc_name;      /* pointer to segment name in string cache */
};

#define namecache namecache_v2
#define NC_VALID 0x01

static int make_tail_file() {
    char tail[PATH_MAX];
    snprintf(tail, sizeof(tail), "/tmp/%u", arc4random());
    int tailfd = open(tail, O_RDWR | O_CREAT, 0666);
    if (tailfd < 0)
        return -1;
    /* CREATE can return without publishing a positive namecache entry. The
	 * retained lookup guarantees that the source entry has a removable tail. */
    int tailLookupFd = open(tail, O_RDONLY);
    if (tailLookupFd < 0)
        return -1;
    uint64_t tailvp = proc_fd_vnode(proc_self(), tailfd);
    if (tailvp == 0)
        return -1;
    struct vnode tailvnode;
    if (kreadbuf(tailvp, &tailvnode, sizeof(tailvnode)) != 0)
        return -1;
    struct namecache tailnc = {0};
    uint64_t tailncp = (uint64_t)tailvnode.v_nclinks.lh_first;
    if (tailncp == 0 || kreadbuf(tailncp, &tailnc, sizeof(tailnc)) != 0)
        return -1;
    return 0;
}

int unsandbox2(const char *dir, const char *file) {
    int ret = 0;
    int filefd = -1, dirfd = -1, newfilefd = -1;

    dirfd = open(dir, O_RDONLY);
    if (dirfd < 0) {
        JBLogError("open dir failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    filefd = open(file, O_RDONLY);
    if (filefd < 0) {
        JBLogError("open file failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    char fname[PATH_MAX];
    char newfile[PATH_MAX];
    snprintf(newfile, sizeof(newfile), "%s/%s", dir, basename_r(file, fname));

    /* A userspace reboot preserves the kernel namecache. Reuse an alias only
	 * when it still resolves to the exact source vnode, and never overwrite a
	 * conflicting entry with another round of kernel list manipulation. */
    newfilefd = open(newfile, O_RDONLY);
    if (newfilefd >= 0) {
        struct stat sourceStat;
        struct stat publishedStat;
        if (fstat(filefd, &sourceStat) != 0 || fstat(newfilefd, &publishedStat) != 0) {
            JBLogError("stat published file failed %d,%s", errno, strerror(errno));
            goto failed;
        }
        if (sourceStat.st_dev != publishedStat.st_dev || sourceStat.st_ino != publishedStat.st_ino) {
            errno = EEXIST;
            JBLogError("published file conflicts with source %s %s", file, newfile);
            goto failed;
        }
        goto final;
    }
    if (errno != ENOENT) {
        JBLogError("open published file failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    /*
     * Add a new namecache to the tail of nchead after the kernel caches
     * "file", avoiding filenc.nc_entry.tqe_next == 0.
     */
    if (make_tail_file() != 0) {
        JBLogError("make_tail_file failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    uint64_t dirvp = proc_fd_vnode(proc_self(), dirfd);
    if (!dirvp) {
        JBLogError("get dirvp failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    struct vnode dirvnode;
    kreadbuf(dirvp, &dirvnode, sizeof(dirvnode));
    kwrite32(dirvp + offsetof(struct vnode, v_usecount), dirvnode.v_usecount + 1);

    uint64_t filevp = proc_fd_vnode(proc_self(), filefd);
    if (!filevp) {
        JBLogError("get filevp failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    struct vnode filevnode;
    kreadbuf(filevp, &filevnode, sizeof(filevnode));

    kwrite32(filevp + offsetof(struct vnode, v_usecount), filevnode.v_usecount + 1);

    struct vnode parentvnode;
    uint64_t parentvp = UNSIGN_PTR((uint64_t)filevnode.v_parent);
    kreadbuf(parentvp, &parentvnode, sizeof(parentvnode));
    kwrite32(parentvp + offsetof(struct vnode, v_usecount), parentvnode.v_usecount + 1);

    struct namecache filenc = {0};
    uint64_t filencp = (uint64_t)filevnode.v_nclinks.lh_first;
    if (filencp == 0 || kreadbuf(filencp, &filenc, sizeof(filenc)) != 0) {
        errno = EIO;
        goto failed;
    }
    /* XNU lockless namecache readers require a complete valid entry. Check
	 * every removal prerequisite before publishing any changed field. */
    if (filenc.nc_vp != (vnode_t)filevp || !(filenc.nc_counter & NC_VALID) || !filenc.nc_entry.tqe_next
        || !filenc.nc_entry.tqe_prev || !filenc.nc_child.tqe_prev || !filenc.nc_un.nc_link.le_prev
        || !filenc.nc_hash.le_prev) {
        errno = EAGAIN;
        goto failed;
    }
    init_crc32();
    uint32_t hash_val = hash_string(basename_r(file, fname), 0);

    uint64_t nchashtbl = kread64(ksymbol(nchashtbl));
    uint64_t nchashmask = kread64(ksymbol(nchashmask));

    uint32_t index = (dirvnode.v_id ^ (hash_val)) & nchashmask; //*********dirv2?
    uint64_t ncpp = nchashtbl + index * 8;

    kwrite64(filencp + offsetof(struct namecache, nc_dvp), dirvp);
    kwrite64(filevp + offsetof(struct vnode, v_parent), 0);

    //TAILQ_REMOVE(&nchead, ncp, nc_entry);
    //TAILQ_REMOVE(&(ncp->nc_dvp->v_ncchildren), ncp, nc_child);
    {
        uint64_t ncp = filencp;
        if (filenc.nc_entry.tqe_next) { //always true for filenc next time
            //TAILQ_NEXT((elm), field)->field.tqe_prev = (elm)->field.tqe_prev;
            kwrite64((uint64_t)filenc.nc_entry.tqe_next + offsetof(struct namecache, nc_entry.tqe_prev),
                     (uint64_t)filenc.nc_entry.tqe_prev);
        }
        //*(elm)->field.tqe_prev = TAILQ_NEXT((elm), field);
        kwrite64((uint64_t)filenc.nc_entry.tqe_prev, (uint64_t)filenc.nc_entry.tqe_next);

        kwrite64(filencp + offsetof(struct namecache, nc_entry.tqe_next), filencp); //TAILQ_CHECK_NEXT
        kwrite64(filencp + offsetof(struct namecache, nc_entry.tqe_prev),
                 filencp + offsetof(struct namecache, nc_entry.tqe_next)); //TAILQ_CHECK_PREV
    }

    //smrq_serialized_remove(/*__smrq_link_t*/ncp, nc_hash):
    {
        uint64_t ncp = filencp;

        if (filenc.nc_hash.le_next) {
            //next->prev = prev; in __smrq_serialized_remove_one(__smrq_link_t*
            kwrite64((uint64_t)filenc.nc_hash.le_next + offsetof(struct smrq_link, le_prev),
                     (uint64_t)filenc.nc_hash.le_prev); //next->prev = prev
        }

        //smr_serialized_store_relaxed(prev, next);
        kwrite64((uint64_t)filenc.nc_hash.le_prev, (uint64_t)filenc.nc_hash.le_next);
    }
    //smrq_serialized_insert_head(ncpp, /*__smrq_link_t*/ncp->nc_hash):
    {
        uint64_t ncp = filencp;

        uint64_t first = kread64(ncpp);
        kwrite64(ncp + offsetof(struct namecache, nc_hash.le_next),
                 first); //smr_serialized_store_relaxed(&elem->next, next);
        if (first) {     //if (next != NULL)
            //next->prev = &elem->next;
            kwrite64(first + offsetof(struct smrq_link, le_prev), ncp + offsetof(struct namecache, nc_hash.le_next));
        }
        kwrite64(ncpp, ncp + offsetof(struct namecache, nc_hash));         //smr_serialized_store(prev, elem);
        kwrite64(ncp + offsetof(struct namecache, nc_hash.le_prev), ncpp); //elem->prev = prev;
    }

    //TAILQ_REMOVE(&(ncp->nc_dvp->v_ncchildren), ncp, nc_child);
    {
        uint64_t ncp = filencp;
        if (filenc.nc_child.tqe_next) { //always true for filenc next time
            //TAILQ_NEXT((elm), field)->field.tqe_prev = (elm)->field.tqe_prev;
            kwrite64((uint64_t)filenc.nc_child.tqe_next + offsetof(struct namecache, nc_child.tqe_prev),
                     (uint64_t)filenc.nc_child.tqe_prev);
        } else {
            //(head)->tqh_last = (elm)->field.tqe_prev;
            kwrite64(parentvp + offsetof(struct vnode, v_ncchildren.tqh_last), (uint64_t)filenc.nc_child.tqe_prev);
        }
        //*(elm)->field.tqe_prev = TAILQ_NEXT((elm), field);
        kwrite64((uint64_t)filenc.nc_child.tqe_prev, (uint64_t)filenc.nc_child.tqe_next);

        kwrite64(filencp + offsetof(struct namecache, nc_child.tqe_next), filencp); //TAILQ_CHECK_NEXT
        kwrite64(filencp + offsetof(struct namecache, nc_child.tqe_prev),
                 filencp + offsetof(struct namecache, nc_child.tqe_next)); //TAILQ_CHECK_PREV
    }

    //LIST_REMOVE(ncp, nc_un.nc_link);
    {
        uint64_t ncp = filencp;

        if (filenc.nc_un.nc_link.le_next) {
            //LIST_NEXT((elm), field)->field.le_prev =(elm)->field.le_prev;
            kwrite64((uint64_t)filenc.nc_un.nc_link.le_next + offsetof(struct namecache, nc_un.nc_link.le_prev),
                     (uint64_t)filenc.nc_un.nc_link.le_prev); //next->prev = prev
        }

        //*(elm)->field.le_prev = LIST_NEXT((elm), field);
        kwrite64((uint64_t)filenc.nc_un.nc_link.le_prev, (uint64_t)filenc.nc_un.nc_link.le_next);
    }

    //update v_parent
    newfilefd = open(newfile, O_RDONLY);
    if (newfilefd < 0) {
        JBLogError("open newfile failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    char pathbuf[PATH_MAX] = {0};
    int ret1 = fcntl(newfilefd, F_GETPATH, pathbuf);
    if (ret1 != 0) {
        JBLogError("get realpath failed %d,%s", errno, strerror(errno));
        goto failed;
    }

    goto final;

failed:
    ret = -1;

final:
    if (dirfd >= 0)
        close(dirfd);
    if (filefd >= 0)
        close(filefd);
    if (newfilefd >= 0)
        close(newfilefd);

    return ret;
}
