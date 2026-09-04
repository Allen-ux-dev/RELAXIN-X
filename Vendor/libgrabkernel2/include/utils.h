#ifndef utils_h
#define utils_h

#include <Foundation/Foundation.h>

#define LIBGRABKERNEL2_USE_LOG_PREFIX 1

#if LIBGRABKERNEL2_USE_LOG_PREFIX
#define LOG_PREFIX "libgrabkernel2: "
#else
#define LOG_PREFIX ""
#endif

void libgrabkernel2_log(const char *format, ...) __attribute__((format(printf, 1, 2)));
void libgrabkernel2_warning(const char *format, ...) __attribute__((format(printf, 1, 2)));
void libgrabkernel2_error(const char *format, ...) __attribute__((format(printf, 1, 2)));

#define LOG(fmt, ...) libgrabkernel2_log(LOG_PREFIX fmt, ##__VA_ARGS__)
#define WARNLOG(fmt, ...) libgrabkernel2_warning(LOG_PREFIX fmt, ##__VA_ARGS__)
#define ERRLOG(fmt, ...) libgrabkernel2_error(LOG_PREFIX fmt, ##__VA_ARGS__)

#ifdef DEBUG
#define DBGLOG(fmt, ...) LOG("DEBUG: " fmt, ##__VA_ARGS__)
#else
#define DBGLOG(fmt, ...)
#endif

NSString *getOsStr(void);
NSString *getBuild(void);
NSString *getModelIdentifier(void);
NSString *getBoardconfig(void);

#endif /* utils_h */
