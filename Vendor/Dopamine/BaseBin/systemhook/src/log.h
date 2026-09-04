#ifndef SYSTEMHOOK_LOG_H
#define SYSTEMHOOK_LOG_H

#ifndef DEBUG
#define DEBUG 0
#endif

void SystemHookLogDebugFunction(const char *format, ...) __attribute__((format(printf, 1, 2)));
void SystemHookLogErrorFunction(const char *format, ...) __attribute__((format(printf, 1, 2)));

#define SYSTEMHOOK_LOG_ERROR(...) SystemHookLogErrorFunction(__VA_ARGS__)
#if DEBUG
#define SYSTEMHOOK_LOG_DEBUG(...) SystemHookLogDebugFunction(__VA_ARGS__)
#else
#define SYSTEMHOOK_LOG_DEBUG(...) do { } while (0)
#endif

#endif
