#ifndef LIBJAILBREAK_SETID_DONOR_H
#define LIBJAILBREAK_SETID_DONOR_H

#include <stdint.h>
#include <sys/types.h>

#define JB_SETID_DONOR_MAGIC 0x5345544944444F4EULL
#define JB_SETID_DONOR_ARGUMENT "__RELAXIN_SETID_DONOR_V2__"

enum {
    JB_SETID_DONOR_ARG_MARKER = 1,
    JB_SETID_DONOR_ARG_CONTROL_FD,
    JB_SETID_DONOR_ARG_RUID,
    JB_SETID_DONOR_ARG_EUID,
    JB_SETID_DONOR_ARG_SVUID,
    JB_SETID_DONOR_ARG_RGID,
    JB_SETID_DONOR_ARG_EGID,
    JB_SETID_DONOR_ARG_SVGID,
    JB_SETID_DONOR_ARG_NGROUPS,
    JB_SETID_DONOR_FIXED_ARGC,
};

struct jb_setid_donor_reply {
    uint64_t magic;
    int32_t status;
    pid_t donorPid;
};

struct jb_setid_donor_ack {
    uint64_t magic;
    int32_t status;
};

#endif
