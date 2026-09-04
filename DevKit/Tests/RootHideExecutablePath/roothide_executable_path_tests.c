#include "relaxin_executable_path.h"

#include <stdio.h>

static int failures;

static void expect(bool condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "not ok %s\n", message);
    failures++;
}

int main(void) {
    expect(is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/Relaxin.app/Relaxin"),
           "matches Relaxin executable");
    expect(is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/App.app/Relaxin"),
           "matches SideStore-staged Relaxin executable");
    expect(is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/RelaxinLite.app/RelaxinLite"),
           "matches Relaxin Lite executable");
    expect(!is_relaxin_executable_path(NULL), "rejects a null path");
    expect(!is_relaxin_executable_path("/Relaxin"), "rejects a bare executable name");
    expect(!is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/Other.app/Relaxin"),
           "rejects a mismatched bundle name");
    expect(!is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/Relaxin.app/RelaxinHelper"),
           "rejects a helper executable");
    expect(!is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/RelaxinLite.app/Relaxin"),
           "rejects a mismatched Lite executable");
    expect(!is_relaxin_executable_path("/private/var/containers/Bundle/Application/UUID/Relaxin.app/Relaxin/child"),
           "rejects an additional path component");

    if (failures == 0)
        fprintf(stdout, "ok roothide-executable-path\n");
    return failures == 0 ? 0 : 1;
}
