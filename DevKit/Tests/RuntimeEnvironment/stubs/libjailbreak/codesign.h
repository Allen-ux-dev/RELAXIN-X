#ifndef RLX_TEST_CODESIGN_H
#define RLX_TEST_CODESIGN_H

#include <stddef.h>
#include <sys/types.h>

#define CS_OPS_STATUS 0
#define CS_PLATFORM_BINARY 0x04000000

int csops(pid_t pid, unsigned int operation, void *address, size_t size);

#endif
