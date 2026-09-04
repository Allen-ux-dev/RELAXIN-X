#ifndef RLX_POST_JAILBREAK_LOG_H
#define RLX_POST_JAILBREAK_LOG_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    RLX_POST_JAILBREAK_LOG_VERBOSE = 0,
    RLX_POST_JAILBREAK_LOG_INFO = 1,
    RLX_POST_JAILBREAK_LOG_WARNING = 2,
    RLX_POST_JAILBREAK_LOG_ERROR = 3,
    RLX_POST_JAILBREAK_LOG_CRITICAL = 4,
};

typedef void (*rlx_post_jailbreak_log_handler)(int32_t level,
                                               const char *_Nullable category,
                                               const char *_Nullable message);

void rlx_post_jailbreak_set_log_handler(rlx_post_jailbreak_log_handler _Nullable handler);
void rlx_post_jailbreak_log(int32_t level, const char *_Nullable category, const char *_Nullable message);

#ifdef __cplusplus
}
#endif

#endif /* RLX_POST_JAILBREAK_LOG_H */
