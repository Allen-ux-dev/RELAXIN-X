#include <Foundation/Foundation.h>
#include <errno.h>
#include <kern_memorystatus.h>
#include <libproc.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/log.h>
#include <libjailbreak/roothider.h>

void jailbreakd_received_message(mach_port_t port);

void setJetsamLimit(uint32_t sizeInMB, bool is_fatal_limit) {
    uint32_t cmd = is_fatal_limit ? MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT
                                  : MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK;
    int rc = memorystatus_control(cmd, getpid(), sizeInMB, NULL, 0);
    if (rc < 0) {
        JBLogError("jailbreakd: memorystatus_control failed status=%d errno=%d", rc, errno);
        exit(rc);
    }
}

int main(int argc, char *argv[]) {
    crashreporter_start();

    setJetsamLimit(50, false);

    JBLogDebug("jailbreakd startup status=begin pid=%d", getpid());

    @autoreleasepool {

        mach_port_t *registeredPorts = NULL;
        mach_msg_type_number_t registeredPortsCount = 0;
        kern_return_t kr = mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount);
        if (kr != KERN_SUCCESS || registeredPortsCount < 3) {
            JBLogError("mach_ports_lookup error: %d, %x, %s", registeredPortsCount, kr, mach_error_string(kr));
            return 1;
        }
        mach_port_t bootstraport = registeredPorts[2];
        if (!MACH_PORT_VALID(bootstraport)) {
            JBLogError("invalid bootstraport");
            return 2;
        }
        registeredPorts[2] = MACH_PORT_NULL;
        mach_ports_register(mach_task_self(), registeredPorts, registeredPortsCount);

        jbclient_xpc_set_custom_port(bootstraport);
        int ret = jbclient_initialize_jailbreakd_primitives();
        if (ret != 0) {
            JBLogError("Failed to initialize jailbreak primitives: %d", ret);
            return 3;
        }
        JBLogDebug("jailbreakd primitives status=ready");

        if (getenv("RESPAWN_REQUIRED")) {
            unsetenv("RESPAWN_REQUIRED");
            JBLogDebug(
                "RESPAWN_REQUIRED consumed: continuing current jailbreakd pid=%d policy=stock-dyld patched respawn=disabled",
                getpid());
        }

        mach_port_t serverPort = jbclient_jailbreakd_checkin();
        if (!MACH_PORT_VALID(serverPort)) {
            JBLogError("Failed to check in server port");
            return 6;
        }

        JBLogDebug("jailbreakd server status=ready");

        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV,
                                                          (uintptr_t)serverPort,
                                                          0,
                                                          dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
            jailbreakd_received_message(serverPort);
        });
        dispatch_resume(source);

        dispatch_main();
    }

    return 0;
}
