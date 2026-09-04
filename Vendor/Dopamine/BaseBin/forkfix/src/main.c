#include <assert.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <sys/wait.h>
#include <unistd.h>
#include "litehook.h"
#include "syscall.h"
#include <libjailbreak/jbclient_mach.h>

extern void __fork(void);
extern pid_t forkfix___fork(void);

static int childToParentPipe[2];
static int parentToChildPipe[2];

static int forkfix_errno_for_status(int status) {
    return status > 0 && status <= ELAST ? status : EIO;
}

static void terminate_child(pid_t pid) {
    if (pid <= 0)
        return;
    kill(pid, SIGKILL);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
    }
}

static int open_pipes(void) {
    parentToChildPipe[0] = -1;
    parentToChildPipe[1] = -1;
    childToParentPipe[0] = -1;
    childToParentPipe[1] = -1;
    if (pipe(parentToChildPipe) != 0)
        return -1;
    if (pipe(childToParentPipe) != 0) {
        int savedError = errno;
        close(parentToChildPipe[0]);
        close(parentToChildPipe[1]);
        errno = savedError;
        return -1;
    }
    return 0;
}

static void close_pipes(void) {
    for (size_t i = 0; i < 2; i++) {
        if (parentToChildPipe[i] >= 0) {
            ffsys_close(parentToChildPipe[i]);
        }
        if (childToParentPipe[i] >= 0) {
            ffsys_close(childToParentPipe[i]);
        }
    }
}

static int child_fixup(void) {
    char message = ' ';
    if (ffsys_write(childToParentPipe[1], &message, sizeof(message)) != sizeof(message)) {
        return EIO;
    }
    if (ffsys_read(parentToChildPipe[0], &message, sizeof(message)) != sizeof(message)) {
        return EIO;
    }
    return 0;
}

static int parent_fixup(pid_t childPid) {
    char message = ' ';
    ssize_t readResult;
    do {
        readResult = read(childToParentPipe[0], &message, sizeof(message));
    } while (readResult < 0 && errno == EINTR);
    if (readResult != sizeof(message))
        return EIO;

    int status = jbclient_mach_fork_fix(childPid);
    if (status != 0)
        return status;

    ssize_t writeResult;
    do {
        writeResult = write(parentToChildPipe[1], &message, sizeof(message));
    } while (writeResult < 0 && errno == EINTR);
    return writeResult == sizeof(message) ? 0 : EIO;
}

pid_t forkfix_pipe_fork(void) {
    if (open_pipes() != 0)
        return -1;

    int status = jbclient_mach_fork_fix_prepare();
    if (status != 0) {
        close_pipes();
        errno = forkfix_errno_for_status(status);
        return -1;
    }

    pid_t pid = ffsys_fork();
    int forkError = pid < 0 ? errno : 0;
    if (pid != 0) {
        status = jbclient_mach_fork_fix_restore();
        if (status != 0) {
            terminate_child(pid);
            close_pipes();
            errno = forkfix_errno_for_status(status);
            return -1;
        }
    }
    if (pid < 0) {
        close_pipes();
        errno = forkError;
        return -1;
    }

    status = pid == 0 ? child_fixup() : parent_fixup(pid);
    if (status != 0) {
        if (pid > 0)
            terminate_child(pid);
        close_pipes();
        errno = forkfix_errno_for_status(status);
        return -1;
    }

    close_pipes();
    return pid;
}

void apply_fork_hook(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *systemhookHandle = dlopen("systemhook.dylib", RTLD_NOLOAD);
        assert(systemhookHandle != NULL);

        kern_return_t (*hookFunction)(void *, void *) = dlsym(systemhookHandle, "litehook_hook_function");
        assert(hookFunction != NULL);
        hookFunction((void *)__fork, (void *)forkfix___fork);
    });
}

__attribute__((constructor)) static void initializer(void) {
    apply_fork_hook();
}
