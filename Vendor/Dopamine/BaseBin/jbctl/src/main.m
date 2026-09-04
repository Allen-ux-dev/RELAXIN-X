#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/jbclient_xpc.h>
#import <libjailbreak/jbclient_mach.h>
#import <libjailbreak/stock_fixes.h>
#import "internal.h"

#import <Foundation/Foundation.h>

#include <errno.h>
#include <limits.h>

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)

static int jbctl_exit_status(int status) {
    return status > 0 && status <= UCHAR_MAX ? status : 1;
}

void print_usage(void) {
    printf("Usage: jbctl <command> <arguments>\n\
Available commands:\n\
	proc_set_debugged <pid>\t\tMarks the process with the given pid as being debugged, allowing invalid code pages inside of it\n\
	trustcache info\t\t\tPrint info about all jailbreak related trustcaches and the cdhashes contained in them\n\
	trustcache add /path/to/macho\t\tAdd the cdhash of a macho to the jailbreaks trustcache\n\
	reboot_userspace\t\tRestarts userspace\n");
}

int main(int argc, char *argv[]) {
    if (!strcmp(argv[argc - 1], "earlyboot")) {
        // If jbctl is spawned in "early boot" state, the jbserver port needs to be obtained from registeredPorts[0] instead
        mach_port_t *registeredPorts;
        mach_msg_type_number_t registeredPortsCount = 0;
        if (mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount) == KERN_SUCCESS) {
            jbclient_xpc_set_custom_port(registeredPorts[0]);

            for (mach_msg_type_number_t i = 1; i < registeredPortsCount; i++) {
                mach_port_deallocate(mach_task_self(), registeredPorts[i]);
            }
            vm_deallocate(mach_task_self(), (vm_address_t)registeredPorts, registeredPortsCount * sizeof(mach_port_t));
        }
    }

    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (getuid() != 0 && geteuid() == 0) {
        // When jailbroken the Dopamine app cannot have uid 0 because it can't drop it anymore without loosing it
        // So in some cases (e.g. for spawning dpkg) we need to use jbctl to get it
        setuid(0);
    }

    const char *rootPath = jbclient_get_jbroot();
    if (rootPath) {
        gSystemInfo.jailbreakInfo.rootPath = strdup(rootPath);
    }

    char *cmd = argv[1];
    if (!strcmp(cmd, "proc_set_debugged")) {
        if (argc != 3) {
            print_usage();
            return 1;
        }
        char *end = NULL;
        errno = 0;
        long parsedPid = strtol(argv[2], &end, 10);
        if (errno != 0 || !end || *end != '\0' || parsedPid <= 0 || parsedPid > INT_MAX) {
            fprintf(stderr, "ERROR: PID must be a positive decimal integer.\n");
            return 2;
        }
        int pid = (int)parsedPid;
        int64_t result = jbclient_platform_set_process_debugged(pid, true);
        if (result == 0) {
            printf("Successfully marked proc of pid %d as debugged\n", pid);
        } else {
            fprintf(stderr, "ERROR: Failed to mark proc of pid %d as debugged (status: %lld).\n", pid, result);
            return jbctl_exit_status((int)result);
        }
        return 0;
    } else if (!strcmp(cmd, "trustcache")) {
        if (argc < 3) {
            print_usage();
            return 2;
        }
        if (getuid() != 0) {
            printf("ERROR: trustcache subcommand requires root.\n");
            return 3;
        }
        const char *trustcacheCmd = argv[2];
        if (!strcmp(trustcacheCmd, "info")) {
            xpc_object_t tcArr = nil;
            int status = jbclient_root_trustcache_info(&tcArr);
            if (status != 0 || !tcArr) {
                fprintf(stderr, "ERROR: Unable to read jailbreak trustcache info (status: %d).\n", status);
                return jbctl_exit_status(status);
            }

            size_t tcCount = xpc_array_get_count(tcArr);
            for (size_t i = 0; i < tcCount; i++) {
                xpc_object_t tc = xpc_array_get_dictionary(tcArr, i);
                if (!tc)
                    continue;
                xpc_object_t cdhashesArr = xpc_dictionary_get_array(tc, "cdhashes");
                if (!cdhashesArr)
                    continue;
                size_t length = xpc_array_get_count(cdhashesArr);
                printf("Jailbreak Trustcache %zd <SPTM no-kcall owner> (length: %zd)\n", i, length);
                for (size_t j = 0; j < length; j++) {
                    size_t cdhashLength = 0;
                    const void *cdhashData = xpc_array_get_data(cdhashesArr, j, &cdhashLength);
                    if (!cdhashData)
                        continue;
                    char cdhashString[cdhashLength * 2 + 1];
                    convert_data_to_hex_string(cdhashData, cdhashLength, cdhashString);
                    printf("| %zd:\t%s\n", j + 1, cdhashString);
                }
            }
            return 0;
        } else if (!strcmp(trustcacheCmd, "add")) {
            if (argc < 4) {
                print_usage();
                return 2;
            }

            /************************ roothide specific ********************************/
            const char *requestedPath = argv[3];
            const char *filepath = requestedPath;
            char rootedPath[PATH_MAX] = {0};
            if (access(filepath, F_OK) != 0 && requestedPath[0] == '/' && rootPath) {
                int length = snprintf(rootedPath, sizeof(rootedPath), "%s%s", rootPath, requestedPath);
                if (length > 0 && (size_t)length < sizeof(rootedPath))
                    filepath = rootedPath;
            }
            if (access(filepath, F_OK) != 0) {
                printf("ERROR: passed macho path does not exist\n");
                printf("\n\n");
                print_usage();
                return 2;
            }
            int status = jbclient_dyld_patch_enabled() ? jbclient_trust_file_by_path(filepath)
                                                       : jbclient_trust_executable_recurse(filepath, NULL);
            if (status != 0) {
                fprintf(stderr, "ERROR: Failed to trust %s (status: %d).\n", requestedPath, status);
            }
            return status == 0 ? 0 : jbctl_exit_status(status);
            /************************ roothide specific ********************************/
        }
        print_usage();
        return 2;
    } else if (!strcmp(cmd, "reboot_userspace")) {
        return reboot3(RB2_USERREBOOT);
    } else if (!strcmp(cmd, "internal")) {
        if (getuid() != 0)
            return 41;
        if (argc < 3)
            return 42;

        const char *internalCmd = argv[2];
        return jbctl_handle_internal(internalCmd, argc - 2, &argv[2]);
    }

    print_usage();
    return 2;
}
