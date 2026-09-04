#ifndef RELAXIN_EXECUTABLE_PATH_H
#define RELAXIN_EXECUTABLE_PATH_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

static inline bool is_relaxin_executable_path(const char *path) {
    static const char *const executableSuffixes[] = {
        "/Relaxin.app/Relaxin",
        "/RelaxinLite.app/RelaxinLite",
        "/App.app/Relaxin", // SideStore
    };
    if (!path)
        return false;

    size_t pathLength = strlen(path);
    for (size_t i = 0; i < sizeof(executableSuffixes) / sizeof(executableSuffixes[0]); i++) {
        const char *suffix = executableSuffixes[i];
        size_t suffixLength = strlen(suffix);
        if (pathLength >= suffixLength && strcmp(path + pathLength - suffixLength, suffix) == 0) {
            return true;
        }
    }
    return false;
}

#endif
