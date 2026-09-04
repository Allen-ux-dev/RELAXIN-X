
#include <stdbool.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/roothider.h>
#include <libjailbreak/codesign.h>

#ifndef DEBUG
#define DEBUG 0
#endif

#if DEBUG
#define RHLogDebug(...) NSLog(__VA_ARGS__)
#else
#define RHLogDebug(...) do { } while (0)
#endif

#define RHLogError(...) NSLog(__VA_ARGS__)

bool isJailbreakBundlePath(const char *path);
