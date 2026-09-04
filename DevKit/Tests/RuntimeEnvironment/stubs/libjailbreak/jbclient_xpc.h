#ifndef RLX_TEST_JBCLIENT_XPC_H
#define RLX_TEST_JBCLIENT_XPC_H

#include <stdbool.h>

int jbclient_process_checkin(char **rootPath, char **bootUUID, char **sandboxExtensions, bool *fullyDebugged);
bool jbclient_roothide_jailbroken(void);

#endif
