#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "util.h"
#include "translation.h"
#include "trustcache.h"
#include "jbclient_xpc.h"

#include "roothider.h"

int jbclient_initialize_primitives_internal(bool physrwPTE);
int jbclient_initialize_primitives_pte_only(void);
int jbclient_initialize_jailbreakd_primitives(void);
int jbclient_initialize_primitives(void);
