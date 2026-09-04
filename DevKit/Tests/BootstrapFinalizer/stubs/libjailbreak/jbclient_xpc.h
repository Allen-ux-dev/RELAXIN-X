#ifndef RLX_TEST_JBCLIENT_XPC_H
#define RLX_TEST_JBCLIENT_XPC_H

#include <stdbool.h>

int jbclient_trust_file_by_path(const char *path);
bool jbclient_palehide_present(void);

#endif
