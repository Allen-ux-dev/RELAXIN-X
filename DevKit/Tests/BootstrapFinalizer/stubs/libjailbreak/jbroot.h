#ifndef RLX_TEST_JBROOT_H
#define RLX_TEST_JBROOT_H

#include <limits.h>
#include <string.h>

extern char *_Nullable get_jbroot(void);

static inline const char *_Nullable rlx_test_jbroot_path(const char *_Nullable path, char *_Nonnull buffer) {
    if (!buffer || !path || !get_jbroot()) {
        return NULL;
    }
    strlcpy(buffer, get_jbroot(), PATH_MAX);
    strlcat(buffer, path, PATH_MAX);
    return buffer;
}

#define JBROOT_PATH(path) rlx_test_jbroot_path((path), alloca(PATH_MAX))

#endif
