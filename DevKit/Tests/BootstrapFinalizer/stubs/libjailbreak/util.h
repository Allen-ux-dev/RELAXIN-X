#ifndef RLX_TEST_UTIL_H
#define RLX_TEST_UTIL_H

#include "jbclient_xpc.h"

int cmd_wait_for_exit(pid_t pid);
int exec_cmd(const char *binary, ...);

#define exec_cmd_trusted(binary, args...) ({ \
    int trust_status = jbclient_trust_file_by_path(binary); \
    trust_status == 0 ? exec_cmd(binary, args) : trust_status; \
})

#endif
