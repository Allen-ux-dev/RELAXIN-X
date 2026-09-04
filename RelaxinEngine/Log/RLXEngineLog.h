//
//  RLXEngineLog.h
//  RelaxinEngine
//
//  C logging surface for engine and exploit sources. The host injects the
//  storage backend once; calls made before injection are safely dropped.
//

#ifndef RLX_ENGINE_LOG_H
#define RLX_ENGINE_LOG_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    RLX_ENGINE_LOG_VERBOSE = 0,
    RLX_ENGINE_LOG_INFO = 1,
    RLX_ENGINE_LOG_WARNING = 2,
    RLX_ENGINE_LOG_ERROR = 3,
    RLX_ENGINE_LOG_CRITICAL = 4,
};

typedef void (*rlx_engine_log_handler)(int32_t level, const char *_Nullable category, const char *_Nullable message);

/// Installs the process-wide engine log sink. Passing NULL disables logging.
///
/// The handler may be called concurrently and must remain valid until it is
/// replaced or cleared.
void rlx_engine_set_log_handler(rlx_engine_log_handler _Nullable handler);

/// Emits one UTF-8 log message through the injected sink.
///
/// A NULL category falls back to "C"; a NULL message becomes an empty string.
void rlx_engine_log(int32_t level, const char *_Nullable category, const char *_Nullable message);

#ifdef __cplusplus
}
#endif

#endif /* RLX_ENGINE_LOG_H */
