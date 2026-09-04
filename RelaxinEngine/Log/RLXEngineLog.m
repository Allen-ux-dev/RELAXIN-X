//
//  RLXEngineLog.m
//  RelaxinEngine
//

#import "RLXEngineLog.h"

#import <os/lock.h>

static os_unfair_lock logHandlerLock = OS_UNFAIR_LOCK_INIT;
static rlx_engine_log_handler logHandler;

void rlx_engine_set_log_handler(rlx_engine_log_handler handler) {
    os_unfair_lock_lock(&logHandlerLock);
    logHandler = handler;
    os_unfair_lock_unlock(&logHandlerLock);
}
void rlx_engine_log(int32_t level, const char *category, const char *message) {
    os_unfair_lock_lock(&logHandlerLock);
    rlx_engine_log_handler handler = logHandler;
    os_unfair_lock_unlock(&logHandlerLock);

    if (handler) {
        handler(level, category ?: "C", message ?: "");
    }
}
