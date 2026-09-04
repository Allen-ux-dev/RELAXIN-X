#ifndef JB_LOG_H
#define JB_LOG_H

#ifndef DEBUG
#define DEBUG 0
#endif

void JBLogDebugFunction(const char *format, ...) __attribute__((format(printf, 1, 2)));
void JBLogErrorFunction(const char *format, ...) __attribute__((format(printf, 1, 2)));

#if DEBUG
#define JBLogDebug(...) do { \
    JBLogDebugFunction(__VA_ARGS__); \
} while (0)
#else
#define JBLogDebug(...) do { } while (0)
#endif

#define JBLogError(...) do { \
    JBLogErrorFunction(__VA_ARGS__); \
} while (0)

#endif
