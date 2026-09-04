#include "jbserver_global.h"
#include "jbsettings.h"
#include <errno.h>
#include <libjailbreak/info.h>
#include <sandbox.h>
#include <libproc.h>
#include <sys/proc_info.h>

#include <libjailbreak/signatures.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>
#include <libjailbreak/log.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/physrw_pte.h>
#include <libjailbreak/codesign.h>
#include <libjailbreak/roothider/signature_policy.h>

#include <bsm/audit.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <unistd.h>
#include <libjailbreak/roothider.h>

#include "../../../systemhook/src/relaxin_executable_path.h"

extern au_asid_t audit_token_to_asid(audit_token_t token);

extern bool string_has_prefix(const char *str, const char *prefix);
static int systemwide_get_jbroot(char **rootPathOut) {
    *rootPathOut = strdup(jbinfo(rootPath));
    return 0;
}

static int systemwide_get_boot_uuid(char **bootUUIDOut) {
    const char *launchdUUID = getenv("LAUNCHD_UUID");
    *bootUUIDOut = launchdUUID ? strdup(launchdUUID) : NULL;
    return 0;
}

CS_SuperBlob *siginfo_resolve_superblob(struct siginfo *siginfo, int pid, int fd) {
    if (!siginfo)
        return NULL;
    if (siginfo->source != SIGNATURE_SOURCE_FILE && siginfo->source != SIGNATURE_SOURCE_PROC) {
        return NULL;
    }
    if (siginfo->signature.fs_blob_size == 0 || siginfo->signature.fs_blob_size > ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE) {
        return NULL;
    }

    size_t superblobSize = siginfo->signature.fs_blob_size;
    CS_SuperBlob *superblob = malloc(superblobSize);
    if (!superblob)
        return NULL;

    bool success = false;

    switch (siginfo->source) {
        case SIGNATURE_SOURCE_FILE: {
            struct stat st = {};

            if (fstat(fd, &st) != 0 || st.st_size < 0)
                break;
            uint64_t fileSize = (uint64_t)st.st_size;
            uint64_t superblobStart = 0;
            if (!roothide_signature_resolve_file_range(siginfo->signature.fs_file_start,
                                                       (uintptr_t)siginfo->signature.fs_blob_start,
                                                       superblobSize,
                                                       fileSize,
                                                       &superblobStart))
                break;

            size_t totalRead = 0;
            while (totalRead < superblobSize) {
                ssize_t amount = pread(fd,
                                       (uint8_t *)superblob + totalRead,
                                       superblobSize - totalRead,
                                       (off_t)(superblobStart + totalRead));
                if (amount > 0) {
                    totalRead += (size_t)amount;
                    continue;
                }
                if (amount < 0 && errno == EINTR)
                    continue;
                break;
            }
            if (totalRead != superblobSize)
                break;

            success = true;
            break;
        }
        case SIGNATURE_SOURCE_PROC: {
            if (!siginfo->signature.fs_blob_start)
                break;
            uint64_t proc = proc_find(pid);

            if (!proc)
                break;
            int readStatus = proc_vreadbuf(proc, siginfo->signature.fs_blob_start, superblob, superblobSize);
            proc_rele(proc);
            if (readStatus != 0)
                break;

            success = true;
            break;
        }
    }
    if (success && !roothide_signature_superblob_is_valid(superblob, superblobSize)) {
        success = false;
    }

    if (!success) {
        free(superblob);
        superblob = NULL;
    }

    return superblob;
}

int systemwide_trust_file(audit_token_t *processToken, int rfd, struct siginfo *siginfo, size_t siginfoSize) {
    if (siginfo && siginfoSize != sizeof(struct siginfo)) {
        JBLogError("systemwide trust rejected phase=validate-siginfo size=%zu expected=%zu status=%d",
                   siginfoSize,
                   sizeof(struct siginfo),
                   EINVAL);
        return EINVAL;
    }

    pid_t pid = -1;
    int fd = -1;
    if (!processToken) {
        pid = 1;
        fd = dup(rfd);
    } else {
        pid = audit_token_to_pid(*processToken);
        struct vnode_fdinfowithpath vnodeInfo;
        int ok = proc_pidfdinfo(pid, rfd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, sizeof(vnodeInfo));
        if (ok > 0) {
            fd = open(vnodeInfo.pvip.vip_path, O_RDONLY);
        }
    }

    if (fd < 0) {
        int status = errno ? errno : EBADF;
        JBLogError("systemwide trust failed phase=acquire-fd pid=%d remote-fd=%d status=%d", pid, rfd, status);
        return status;
    }

    char trustPath[PATH_MAX] = {0};
    if (fcntl(fd, F_GETPATH, trustPath) != 0) {
        strlcpy(trustPath, "(fd)", sizeof(trustPath));
    }
    struct statfs fsb;
    int fsr = fstatfs(fd, &fsb);
    if (fsr == 0) {
        // Anything on the rootfs or fakelib mount point can be ignored as it's guaranteed to already be in trustcache
        if (!strcmp(fsb.f_mntonname, "/") /*|| !strcmp(fsb.f_mntonname, "/usr/lib")*/) {
            close(fd);
            return 0;
        }
    }

    cdhash_t *cdhashes = NULL;
    uint32_t cdhashesCount = 0;
    int preparationStatus = 0;
    bool signatureEligibleForTrust = true;

    if (siginfo) {
        // If we were passed a siginfo, get the cdhash of the superblob from the siginfo
        CS_SuperBlob *superblob = siginfo_resolve_superblob(siginfo, pid, fd);
        if (superblob) {
            cdhash_t cdhash;
            if (code_signature_calculate_adhoc_cdhash(superblob, siginfo->signature.fs_blob_size, cdhash)) {
                if (siginfo->source == SIGNATURE_SOURCE_FILE) {
                    char filepath[PATH_MAX] = {0};
                    if (fcntl(fd, F_GETPATH, filepath) != 0) {
                        preparationStatus = errno ? errno : EBADF;
                    } else if (string_has_prefix(filepath, "/private/preboot/Cryptexes/")) {
                        signatureEligibleForTrust = false;
                    } else if (isRemovableBundlePath(filepath) && !hasTrollstoreLiteMarker(filepath)) {
                        signatureEligibleForTrust = false;
                    } else if (ensure_randomized_cdhash_for_slice(filepath,
                                                                  (uint64_t)siginfo->signature.fs_file_start,
                                                                  cdhash)
                               != 0) {
                        preparationStatus = errno ? errno : ENOEXEC;
                        JBLogError("Failed to prepare RootHide signature for %s", filepath);
                    }
                } else if (system_info_uses_sptm()) {
                    // A process-memory blob has no safe on-disk object to normalize.
                    preparationStatus = ENOTSUP;
                }

                if (signatureEligibleForTrust && preparationStatus == 0 && !is_cdhash_trustcached(cdhash)) {
                    cdhashes = malloc(sizeof(cdhash_t));
                    if (cdhashes) {
                        cdhashesCount = 1;
                        memcpy(cdhashes[0], cdhash, sizeof(cdhash));
                    } else {
                        preparationStatus = ENOMEM;
                    }
                }
            }
            free(superblob);
        } else {
            preparationStatus = EINVAL;
        }
    } else {
        // If we weren't passed a siginfo, get cdhashes of all slices
        preparationStatus = file_collect_untrusted_cdhashes(fd, &cdhashes, &cdhashesCount);
    }

    int trustStatus = preparationStatus;
    if (trustStatus == 0 && cdhashes && cdhashesCount > 0) {
        trustStatus = jb_trustcache_add_cdhashes(cdhashes, cdhashesCount);
    }
    free(cdhashes);

    if (trustStatus != 0) {
        JBLogError("systemwide trust failed phase=publish pid=%d path=%s entries=%u status=%d",
                   pid,
                   trustPath,
                   cdhashesCount,
                   trustStatus);
    }
    close(fd);
    return trustStatus;
}

int systemwide_trust_file_by_path(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    int r = systemwide_trust_file(NULL, fd, NULL, 0);
    close(fd);
    return r;
}

static int systemwide_copy_audit_session_port(audit_token_t processToken, mach_port_t *portOut) {
    if (!portOut)
        return EINVAL;
    *portOut = MACH_PORT_NULL;

    if (__builtin_available(iOS 17.0, *)) {
        au_asid_t asid = audit_token_to_asid(processToken);
        if (asid == AU_DEFAUDITSID)
            return 0;
        if (audit_session_port(asid, portOut) != 0) {
            return errno ? errno : EIO;
        }
        return MACH_PORT_VALID(*portOut) ? 0 : EIO;
    }
    return 0;
}

static int systemwide_update_proc_saved_ids(uint64_t proc,
                                            pid_t pid,
                                            const char *procPath,
                                            const struct proc_ucred_identity *identity,
                                            bool updateUid,
                                            bool updateGid) {
    if (!proc || !procPath || !identity)
        return EINVAL;

    int status = 0;
    if (updateUid) {
        status = kwrite32(proc + koffsetof(proc, svuid), identity->svuid);
        uint32_t observedSvuid = 0;
        if (status == 0) {
            status = kreadbuf(proc + koffsetof(proc, svuid), &observedSvuid, sizeof(observedSvuid));
            if (status == 0 && observedSvuid != identity->svuid) {
                status = EIO;
            }
        }
        if (status != 0) {
            JBLogError("identity finalize failed phase=saved-id " "field=svuid " "pid=%d path=%s value=%u status=%d",
                       pid,
                       procPath,
                       identity->svuid,
                       status);
            return status;
        }
    }
    if (updateGid) {
        status = kwrite32(proc + koffsetof(proc, svgid), identity->svgid);
        uint32_t observedSvgid = 0;
        if (status == 0) {
            status = kreadbuf(proc + koffsetof(proc, svgid), &observedSvgid, sizeof(observedSvgid));
            if (status == 0 && observedSvgid != identity->svgid) {
                status = EIO;
            }
        }
        if (status != 0) {
            JBLogError("identity finalize failed phase=saved-id " "field=svgid " "pid=%d path=%s value=%u status=%d",
                       pid,
                       procPath,
                       identity->svgid,
                       status);
            return status;
        }
    }
    return 0;
}

static int systemwide_clear_proc_sugid(uint64_t proc, pid_t pid, const char *procPath) {
    if (!proc || !procPath)
        return EINVAL;

    uint32_t flag = 0;
    int status = kreadbuf(proc + koffsetof(proc, flag), &flag, sizeof(flag));
    if (status != 0) {
        JBLogError("identity finalize failed phase=p-sugid-read " "pid=%d path=%s status=%d", pid, procPath, status);
        return status;
    }

    if ((flag & P_SUGID) != 0) {
        status = kwrite32(proc + koffsetof(proc, flag), flag & ~P_SUGID);
        if (status != 0) {
            JBLogError("identity finalize failed phase=p-sugid-write " "pid=%d path=%s status=%d",
                       pid,
                       procPath,
                       status);
            return status;
        }
    }

    uint32_t observedFlag = 0;
    status = kreadbuf(proc + koffsetof(proc, flag), &observedFlag, sizeof(observedFlag));
    if (status == 0 && (observedFlag & P_SUGID) != 0)
        status = EIO;
    if (status != 0) {
        JBLogError("identity finalize failed phase=p-sugid-verify " "pid=%d path=%s flag=0x%x status=%d",
                   pid,
                   procPath,
                   observedFlag,
                   status);
        return status;
    }

    return 0;
}

int systemwide_process_checkin(audit_token_t *processToken,
                               char **rootPathOut,
                               char **bootUUIDOut,
                               char **sandboxExtensionsOut,
                               bool *fullyDebuggedOut) {
    // Fetch process info
    pid_t pid = audit_token_to_pid(*processToken);
    char procPath[4 * MAXPATHLEN];
    if (proc_pidpath(pid, procPath, sizeof(procPath)) <= 0) {
        return -1;
    }

    // Find proc in kernelspace
    uint64_t proc = proc_find(pid);
    if (!proc) {
        return -1;
    }

    // Get jbroot and boot uuid
    systemwide_get_jbroot(rootPathOut);
    systemwide_get_boot_uuid(bootUUIDOut);

    /************************************ roothide specific ************************************************/
    uint32_t csflags = 0;
    csops(pid, CS_OPS_STATUS, &csflags, sizeof(csflags));
    bool isPlatformProcess = (csflags & CS_PLATFORM_BINARY) != 0;

    // Generate sandbox extensions for the requesting process
    *sandboxExtensionsOut = generate_sandbox_extensions(processToken, isPlatformProcess);
    if (!(*sandboxExtensionsOut)) {
        JBLogError("Failed to generate sandbox extensions for process %d", pid);
        proc_rele(proc);
        return EACCES;
    }

    bool isApplication = isRemovableBundlePath(procPath) || isSubPathOf(procPath, JBROOT_PATH("/Applications"));
    bool fullyDebugged = false;
    if (isApplication) {
        /*************************************** roothide specific *********************************/

        // This is an app, enable CS_DEBUGGED based on user preference
        if (jbsetting(markAppsAsDebugged)) {
            fullyDebugged = true;
        }
    }
    *fullyDebuggedOut = fullyDebugged;

    // Allow invalid pages
    int status = cs_allow_invalid(proc, fullyDebugged);
    if (status != 0) {
        JBLogError("process checkin failed phase=codesign pid=%d path=%s status=%d", pid, procPath, status);
        proc_rele(proc);
        return status;
    }

    // Fix setuid
    struct stat sb;
    int statStatus = stat(procPath, &sb);
    if (statStatus == 0) {
        if (S_ISREG(sb.st_mode) && (sb.st_mode & (S_ISUID | S_ISGID))) {
            struct proc_ucred_identity originalIdentity = {0};
            status = proc_read_ucred_identity(proc, &originalIdentity);
            if (status != 0) {
                JBLogError("process checkin failed phase=ucred-read pid=%d path=%s status=%d", pid, procPath, status);
                proc_rele(proc);
                return status;
            }
            struct proc_ucred_identity desiredIdentity = originalIdentity;
            if (sb.st_mode & S_ISUID) {
                desiredIdentity.euid = sb.st_uid;
                desiredIdentity.svuid = sb.st_uid;
            }
            if (sb.st_mode & S_ISGID) {
                desiredIdentity.egid = sb.st_gid;
                desiredIdentity.svgid = sb.st_gid;
                desiredIdentity.groups[0] = sb.st_gid;
            }
            bool identityChanged = originalIdentity.euid != desiredIdentity.euid
                || originalIdentity.svuid != desiredIdentity.svuid || originalIdentity.egid != desiredIdentity.egid
                || originalIdentity.svgid != desiredIdentity.svgid
                || originalIdentity.groups[0] != desiredIdentity.groups[0];
            if (identityChanged) {
                mach_port_t auditSessionPort = MACH_PORT_NULL;
                status = systemwide_copy_audit_session_port(*processToken, &auditSessionPort);
                if (status != 0) {
                    JBLogError("process checkin failed phase=audit-session " "pid=%d path=%s asid=%u status=%d",
                               pid,
                               procPath,
                               audit_token_to_asid(*processToken),
                               status);
                    proc_rele(proc);
                    return status;
                }
                status = proc_ucred_update_content(proc,
                                                   procPath,
                                                   &desiredIdentity,
                                                   auditSessionPort,
                                                   PROC_UCRED_AUDIT_PRESERVE);
                if (MACH_PORT_VALID(auditSessionPort)) {
                    mach_port_deallocate(mach_task_self(), auditSessionPort);
                }
                if (status != 0) {
                    JBLogError("process checkin failed phase=setid pid=%d path=%s status=%d", pid, procPath, status);
                    proc_rele(proc);
                    return status;
                }
            }

            status = systemwide_update_proc_saved_ids(proc,
                                                      pid,
                                                      procPath,
                                                      &desiredIdentity,
                                                      (sb.st_mode & S_ISUID) != 0,
                                                      (sb.st_mode & S_ISGID) != 0);
            if (status != 0) {
                proc_rele(proc);
                return status;
            }

            status = systemwide_clear_proc_sugid(proc, pid, procPath);
            if (status != 0) {
                proc_rele(proc);
                return status;
            }
        }
    } else {
        JBLogError("process checkin phase=stat pid=%d path=%s errno=%d", pid, procPath, errno);
    }

    if (__builtin_available(iOS 16.0, *)) {
        // In iOS 16+ there is a super annoying security feature called Protobox
        // Amongst other things, it allows for a process to have a syscall mask
        // If a process calls a syscall it's not allowed to call, it immediately crashes
        // Because for tweaks and hooking this is unacceptable, we update these masks to be 1 for all syscalls on all processes
        // That will at least get rid of the syscall mask part of Protobox
        status = proc_allow_all_syscalls(proc);
        if (status != 0) {
            JBLogError("process checkin failed phase=syscall-filter pid=%d path=%s status=%d", pid, procPath, status);
            proc_rele(proc);
            return status;
        }

        // Some processes also have a filter for mach messages, fortunately there is one allowed message id that can be used for the check-in
        // Then we remove the filter to make other message ids accessible afterwards aswell
        status = proc_remove_msg_filter(proc);
        if (status != 0) {
            JBLogError("process checkin failed phase=message-filter pid=%d path=%s status=%d", pid, procPath, status);
            proc_rele(proc);
            return status;
        }
    }

    // For whatever reason after SpringBoard has restarted, AutoFill and other stuff stops working
    // The fix is to always also restart the kbd daemon alongside SpringBoard
    // Seems to be something sandbox related where kbd doesn't have the right extensions until restarted
    if (strcmp(procPath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0) {
        static bool springboardStartedBefore = false;
        if (!springboardStartedBefore) {
            // Ignore the first SpringBoard launch after userspace reboot
            // This fix only matters when SpringBoard gets restarted during runtime
            springboardStartedBefore = true;
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                killall("/System/Library/TextInput/kbd", SIGKILL);
            });
        }
    }
    // For the Dopamine app itself we want to give it a saved uid/gid of 0, unsandbox it and give it CS_PLATFORM_BINARY
    // This is so that the buttons inside it can work when jailbroken, even if the app was not installed by TrollStore
    else if (isRemovableBundlePath(procPath) && is_relaxin_executable_path(procPath)) {
        // svuid = 0, svgid = 0
        if (__builtin_available(iOS 17.0, *)) {
        } else {
            uint64_t ucred = proc_ucred(proc);
            kwrite32(proc + koffsetof(proc, svuid), 0);
            kwrite32(ucred + koffsetof(ucred, svuid), 0);
            kwrite32(proc + koffsetof(proc, svgid), 0);
            kwrite32(ucred + koffsetof(ucred, svgid), 0);
        }

        // platformize
        status = proc_csflags_set(proc, CS_PLATFORM_BINARY);
        if (status != 0) {
            proc_rele(proc);
            return status;
        }

        /********************* roothide specific ********************/
        status = proc_csflags_set(proc, CS_INSTALLER);
        if (status != 0) {
            proc_rele(proc);
            return status;
        }
        /*************************************************************/
    }

#ifdef __arm64e__
    // On arm64e every image has a trust level associated with it
    // "In trust cache" trust levels have higher runtime enforcements, this can be a problem for some tools as Dopamine trustcaches everything that's adhoc signed
    // So we add the ability for a binary to get a different trust level using the "jb.pmap_cs.custom_trust" entitlement
    // This is for binaries that rely on weaker PMAP_CS checks (e.g. Lua trampolines need it)
    xpc_object_t customTrustObj = xpc_copy_entitlement_for_token("jb.pmap_cs.custom_trust", processToken);
    if (customTrustObj) {
        if (xpc_get_type(customTrustObj) == XPC_TYPE_STRING) {
            const char *customTrustStr = xpc_string_get_string_ptr(customTrustObj);
            uint32_t customTrust = pmap_cs_trust_string_to_int(customTrustStr);
            if (customTrust >= 2) {
                if (koffsetof(pmap_cs_code_directory, signing_identifier)
                    && koffsetof(pmap_cs_code_directory, team_identifier)
                    && koffsetof(pmap_cs_region, pmap_cs_region_right)) {
                    proc_set_pmap_cs_custom_trust(proc, customTrust);
                } else {
                    uint64_t mainCodeDir = proc_find_main_binary_code_dir(proc);
                    if (mainCodeDir) {
                        kwrite32(mainCodeDir + koffsetof(pmap_cs_code_directory, trust), customTrust);
                    }
                }
            }

            if (customTrust <= pmap_cs_trust_string_to_int("PMAP_CS_APP_STORE")) {
                if (kconstant(TFRO_PLATFORM) && koffsetof(proc_ro, t_flags_ro)) {
                    proc_csflags_clear(proc, CS_PLATFORM_BINARY);

                    uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
                    uint32_t t_flags = kread32(proc_ro + koffsetof(proc_ro, t_flags_ro));
                    t_flags &= ~kconstant(TFRO_PLATFORM);
                    kwrite32(proc_ro + koffsetof(proc_ro, t_flags_ro), t_flags);
                }
            }
        }
    }
#endif

    proc_rele(proc);
    return 0;
}

static int systemwide_read_pointer(uint64_t address, uint64_t *value) {
    uint64_t rawValue = 0;
    int status = kreadbuf(address, &rawValue, sizeof(rawValue));
    if (status != 0)
        return status;
    *value = UNSIGN_PTR(rawValue);
    return 0;
}

static void fork_fix_log_failure(const char *stage, pid_t parentPid, pid_t childPid, uint64_t address, int status) {
    physrw_pte_diagnostics diagnostics = {0};
    int diagnosticsStatus = physrw_pte_copy_diagnostics(&diagnostics);
    JBLogError(
        "forkfix failure stage=%s parent=%d child=%d " "address=0x%llx status=%d diagnostics_status=%d " "pte_hits=%llu pte_fresh=%llu pte_reclaimed=%llu " "reclaim_attempts=%llu reclaim_successes=%llu " "reclaim_failures=%llu acquire_failures=%llu " "generation_builds=%llu generation_build_failures=%llu " "generation_rotations=%llu generation_retire_failures=%llu " "generation_slots=%llu/%llu standby=%llu " "last_pa=0x%llx last_group=%d last_status=%d " "last_mach=%d last_stage=%u",
        stage ?: "unknown",
        parentPid,
        childPid,
        address,
        status,
        diagnosticsStatus,
        diagnostics.cacheHits,
        diagnostics.freshSlotAssignments,
        diagnostics.reclaimedSlotAssignments,
        diagnostics.reclaimAttempts,
        diagnostics.reclaimSuccesses,
        diagnostics.reclaimFailures,
        diagnostics.acquireFailures,
        diagnostics.generationBuildAttempts,
        diagnostics.generationBuildFailures,
        diagnostics.generationRotations,
        diagnostics.generationRetirementFailures,
        diagnostics.activeGenerationSlotsUsed,
        diagnostics.activeGenerationCapacity,
        diagnostics.standbyGenerationReady,
        diagnostics.lastFailedPhysicalAddress,
        diagnostics.lastReclaimGroup,
        diagnostics.lastReclaimStatus,
        diagnostics.lastReclaimMachStatus,
        diagnostics.lastReclaimStage);
}

struct fork_fix_attempt {
    pid_t parentPid;
    pid_t childPid;
    bool loggedFailure;
};

static void fork_fix_note_failure(struct fork_fix_attempt *attempt, const char *stage, uint64_t address, int status) {
    if (attempt->loggedFailure)
        return;
    attempt->loggedFailure = true;
    fork_fix_log_failure(stage, attempt->parentPid, attempt->childPid, address, status);
}

static uint64_t fork_fix_diagnostic_read64(struct fork_fix_attempt *attempt, const char *stage, uint64_t address) {
    uint64_t value = 0;
    int status = kreadbuf(address, &value, sizeof(value));
    if (status != 0) {
        fork_fix_note_failure(attempt, stage, address, status);
    }
    return value;
}

static uint64_t fork_fix_diagnostic_read_pointer(struct fork_fix_attempt *attempt,
                                                 const char *stage,
                                                 uint64_t address) {
    return UNSIGN_PTR(fork_fix_diagnostic_read64(attempt, stage, address));
}

static uint32_t fork_fix_diagnostic_read32(struct fork_fix_attempt *attempt, const char *stage, uint64_t address) {
    uint32_t value = 0;
    int status = kreadbuf(address, &value, sizeof(value));
    if (status != 0) {
        fork_fix_note_failure(attempt, stage, address, status);
    }
    return value;
}

static void fork_fix_diagnostic_write64(struct fork_fix_attempt *attempt,
                                        const char *stage,
                                        uint64_t address,
                                        uint64_t value) {
    int status = kwrite64(address, value);
    if (status != 0) {
        fork_fix_note_failure(attempt, stage, address, status);
    }
}

struct fork_trust_lease {
    struct fork_trust_lease *next;
    struct cs_fork_trust_state state;
    size_t holderCount;
};

struct fork_trust_transaction {
    struct fork_trust_transaction *next;
    pid_t pid;
    uint32_t pidVersion;
    struct fork_trust_lease *lease;
};

static pthread_mutex_t forkTrustLock = PTHREAD_MUTEX_INITIALIZER;
static struct fork_trust_transaction *forkTrustTransactions;
static struct fork_trust_lease *forkTrustLeases;

static struct fork_trust_transaction **fork_trust_transaction_slot(pid_t pid, uint32_t pidVersion) {
    struct fork_trust_transaction **slot = &forkTrustTransactions;
    while (*slot && ((*slot)->pid != pid || (*slot)->pidVersion != pidVersion)) {
        slot = &(*slot)->next;
    }
    return slot;
}

static struct fork_trust_lease **fork_trust_lease_slot(uint64_t trustPairAddress) {
    struct fork_trust_lease **slot = &forkTrustLeases;
    while (*slot && (*slot)->state.trust_pair_address != trustPairAddress) {
        slot = &(*slot)->next;
    }
    return slot;
}

int systemwide_fork_fix_prepare(audit_token_t *parentToken) {
    if (!parentToken)
        return EINVAL;
    if (!system_info_uses_sptm())
        return 0;

    pid_t parentPid = audit_token_to_pid(*parentToken);
    if (parentPid <= 0)
        return ESRCH;
    uint32_t parentPidVersion = parentToken->val[7];

    uint64_t parentProc = proc_find(parentPid);
    if (!parentProc)
        return ESRCH;

    struct fork_trust_transaction *transaction = calloc(1, sizeof(*transaction));
    struct fork_trust_lease *newLease = calloc(1, sizeof(*newLease));
    if (!transaction || !newLease) {
        free(transaction);
        free(newLease);
        proc_rele(parentProc);
        return ENOMEM;
    }
    transaction->pid = parentPid;
    transaction->pidVersion = parentPidVersion;

    pthread_mutex_lock(&forkTrustLock);
    struct fork_trust_transaction **existing = fork_trust_transaction_slot(parentPid, parentPidVersion);
    struct cs_fork_trust_state state = {0};
    int status = *existing ? EALREADY : cs_fork_trust_prepare(parentProc, &state);
    if (status == 0) {
        struct fork_trust_lease **leaseSlot = fork_trust_lease_slot(state.trust_pair_address);
        struct fork_trust_lease *lease = *leaseSlot;
        if (!lease) {
            newLease->state = state;
            newLease->holderCount = 1;
            newLease->next = forkTrustLeases;
            forkTrustLeases = newLease;
            lease = newLease;
            newLease = NULL;
        } else {
            lease->holderCount++;
        }
        transaction->lease = lease;
    }
    if (status == 0) {
        transaction->next = forkTrustTransactions;
        forkTrustTransactions = transaction;
        transaction = NULL;
    }
    pthread_mutex_unlock(&forkTrustLock);

    free(transaction);
    free(newLease);
    proc_rele(parentProc);
    if (status != 0) {
        fork_fix_log_failure("prepare", parentPid, 0, 0, status);
    }
    return status;
}

int systemwide_fork_fix_restore(audit_token_t *parentToken) {
    if (!parentToken)
        return EINVAL;
    if (!system_info_uses_sptm())
        return 0;

    pid_t parentPid = audit_token_to_pid(*parentToken);
    if (parentPid <= 0)
        return ESRCH;
    uint32_t parentPidVersion = parentToken->val[7];

    pthread_mutex_lock(&forkTrustLock);
    struct fork_trust_transaction **slot = fork_trust_transaction_slot(parentPid, parentPidVersion);
    struct fork_trust_transaction *transaction = *slot;
    struct fork_trust_lease *releasedLease = NULL;
    int status = transaction ? 0 : ENOENT;
    if (status == 0 && transaction->lease->holderCount == 1) {
        struct fork_trust_lease **leaseSlot = fork_trust_lease_slot(transaction->lease->state.trust_pair_address);
        if (*leaseSlot != transaction->lease) {
            status = EFAULT;
        } else {
            status = cs_fork_trust_restore(&transaction->lease->state);
        }
        if (status == 0) {
            releasedLease = transaction->lease;
            *leaseSlot = releasedLease->next;
        }
    } else if (status == 0) {
        transaction->lease->holderCount--;
    }
    if (status == 0) {
        *slot = transaction->next;
    }
    pthread_mutex_unlock(&forkTrustLock);

    if (status == 0) {
        free(releasedLease);
        free(transaction);
    } else {
        fork_fix_log_failure("restore", parentPid, 0, 0, status);
    }
    return status;
}

static int fork_fix_original(pid_t parentPid, pid_t childPid, uint64_t parentProc, uint64_t childProc) {
    struct fork_fix_attempt attempt = {
        .parentPid = parentPid,
        .childPid = childPid,
    };
    int allowInvalidStatus = cs_allow_invalid(childProc, false);
    if (allowInvalidStatus != 0) {
        fork_fix_note_failure(&attempt, "allow-invalid", childProc, allowInvalidStatus);
    }

    uint64_t childTask = proc_task(childProc);
    if (!childTask) {
        fork_fix_note_failure(&attempt, "child-task", childProc + koffsetof(proc, task), EFAULT);
    }
    uint64_t childVmMap = fork_fix_diagnostic_read_pointer(&attempt, "child-map", childTask + koffsetof(task, map));
    uint64_t childHeader = childVmMap + koffsetof(vm_map, hdr);
    uint32_t childNentries = fork_fix_diagnostic_read32(&attempt,
                                                        "child-entry-count",
                                                        childHeader + koffsetof(vm_map_header, nentries));
    uint64_t childEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                           "child-first-entry",
                                                           childHeader + koffsetof(vm_map_header, links)
                                                               + koffsetof(vm_map_links, next));

    uint64_t parentTask = proc_task(parentProc);
    if (!parentTask) {
        fork_fix_note_failure(&attempt, "parent-task", parentProc + koffsetof(proc, task), EFAULT);
    }
    uint64_t parentVmMap = fork_fix_diagnostic_read_pointer(&attempt, "parent-map", parentTask + koffsetof(task, map));
    uint64_t parentHeader = parentVmMap + koffsetof(vm_map, hdr);
    uint32_t parentNentries = fork_fix_diagnostic_read32(&attempt,
                                                         "parent-entry-count",
                                                         parentHeader + koffsetof(vm_map_header, nentries));
    uint64_t parentEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                            "parent-first-entry",
                                                            parentHeader + koffsetof(vm_map_header, links)
                                                                + koffsetof(vm_map_links, next));

    uint64_t childFirstEntry = childEntry;
    uint64_t parentFirstEntry = parentEntry;
    uint32_t childIdx = 0;
    uint32_t parentIdx = 0;
    do {
        uint64_t childStart = fork_fix_diagnostic_read_pointer(&attempt,
                                                               "child-entry-start",
                                                               childEntry + koffsetof(vm_map_entry, links)
                                                                   + koffsetof(vm_map_links, min));
        uint64_t parentStart = fork_fix_diagnostic_read_pointer(&attempt,
                                                                "parent-entry-start",
                                                                parentEntry + koffsetof(vm_map_entry, links)
                                                                    + koffsetof(vm_map_links, min));

        if (parentStart < childStart) {
            parentEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                           "parent-next-entry",
                                                           parentEntry + koffsetof(vm_map_entry, links)
                                                               + koffsetof(vm_map_links, next));
            parentIdx++;
        } else if (parentStart > childStart) {
            childEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                          "child-next-entry",
                                                          childEntry + koffsetof(vm_map_entry, links)
                                                              + koffsetof(vm_map_links, next));
            childIdx++;
        } else {
            uint64_t parentFlags = fork_fix_diagnostic_read64(&attempt,
                                                              "parent-entry-flags",
                                                              parentEntry + koffsetof(vm_map_entry, flags));
            uint64_t childFlags = fork_fix_diagnostic_read64(&attempt,
                                                             "child-entry-flags",
                                                             childEntry + koffsetof(vm_map_entry, flags));
            uint8_t parentProt = VM_FLAGS_GET_PROT(parentFlags);
            uint8_t parentMaxProt = VM_FLAGS_GET_MAXPROT(parentFlags);
            uint8_t childProt = VM_FLAGS_GET_PROT(childFlags);
            uint8_t childMaxProt = VM_FLAGS_GET_MAXPROT(childFlags);

            bool updateChildFlags = parentProt != childProt || parentMaxProt != childMaxProt;
            if (updateChildFlags) {
                VM_FLAGS_SET_PROT(childFlags, parentProt);
                VM_FLAGS_SET_MAXPROT(childFlags, parentMaxProt);
            }

            if (__builtin_available(iOS 16.0, *)) {
                bool parentUserDebug = VM_FLAGS_GET_XNU_USER_DEBUG(parentFlags);
                bool childUserDebug = VM_FLAGS_GET_XNU_USER_DEBUG(childFlags);
                if (parentUserDebug != childUserDebug) {
                    VM_FLAGS_SET_XNU_USER_DEBUG(childFlags, parentUserDebug);
                    updateChildFlags = true;
                }
            }

            if (updateChildFlags) {
                fork_fix_diagnostic_write64(&attempt,
                                            "child-entry-flags-write",
                                            childEntry + koffsetof(vm_map_entry, flags),
                                            childFlags);
            }

            parentEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                           "parent-next-entry",
                                                           parentEntry + koffsetof(vm_map_entry, links)
                                                               + koffsetof(vm_map_links, next));
            parentIdx++;
            childEntry = fork_fix_diagnostic_read_pointer(&attempt,
                                                          "child-next-entry",
                                                          childEntry + koffsetof(vm_map_entry, links)
                                                              + koffsetof(vm_map_links, next));
            childIdx++;
        }
    } while (parentEntry != 0 && childEntry != 0 && parentEntry != parentFirstEntry && childEntry != childFirstEntry
             && parentIdx < parentNentries && childIdx < childNentries);

    return 0;
}

int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid) {
    int retval = 3;
    pid_t parentPid = audit_token_to_pid(*parentToken);
    uint64_t parentProc = proc_find(parentPid);
    uint64_t childProc = proc_find(childPid);

    if (!childProc || !parentProc) {
        fork_fix_log_failure("proc-find", parentPid, (pid_t)childPid, 0, ESRCH);
        goto out;
    }

    retval = 2;
    uint64_t observedParentProc = 0;
    int status = systemwide_read_pointer(childProc + koffsetof(proc, pptr), &observedParentProc);
    if (status != 0) {
        fork_fix_log_failure("child-parent", parentPid, (pid_t)childPid, childProc + koffsetof(proc, pptr), status);
        retval = status;
        goto out;
    }
    // Safety check to ensure we are actually coming from fork.
    if (observedParentProc != parentProc) {
        retval = EACCES;
        goto out;
    }

    retval = fork_fix_original(parentPid, (pid_t)childPid, parentProc, childProc);

out:
    if (childProc)
        proc_rele(childProc);
    if (parentProc)
        proc_rele(parentProc);

    return retval;
}
static int systemwide_cs_revalidate(audit_token_t *callerToken) {
    uint64_t callerPid = audit_token_to_pid(*callerToken);
    if (callerPid > 0) {
        uint64_t callerProc = proc_find(callerPid);
        if (callerProc) {
            int status = proc_csflags_set(callerProc, CS_VALID);
            proc_rele(callerProc);
            return status;
        }
    }
    return ESRCH;
}

static int systemwide_validate_direct_child(pid_t callerPid, uint64_t callerProc, pid_t childPid, uint64_t childProc) {
    uint64_t liveCallerProc = proc_find(callerPid);
    uint64_t liveChildProc = proc_find(childPid);
    int status = 0;

    if (!liveCallerProc || !liveChildProc || liveCallerProc != callerProc || liveChildProc != childProc) {
        status = ESRCH;
        goto out;
    }

    uint64_t observedParentProc = 0;
    status = systemwide_read_pointer(childProc + koffsetof(proc, pptr), &observedParentProc);
    if (status == 0 && observedParentProc != callerProc) {
        status = EACCES;
    }

out:
    if (liveChildProc)
        proc_rele(liveChildProc);
    if (liveCallerProc)
        proc_rele(liveCallerProc);
    return status;
}

static int systemwide_persona_fix(audit_token_t *callerToken,
                                  int childPid,
                                  uid_t overwriteUid,
                                  gid_t overwriteGid,
                                  bool resumeChild) {
    bool hasPersonaMgmtEntitlement = false;
    xpc_object_t personaMgmtVal = xpc_copy_entitlement_for_token("com.apple.private.persona-mgmt", callerToken);
    if (personaMgmtVal) {
        if (xpc_get_type(personaMgmtVal) == XPC_TYPE_INT64) {
            hasPersonaMgmtEntitlement = xpc_int64_get_value(personaMgmtVal) == 1;
        } else if (xpc_get_type(personaMgmtVal) == XPC_TYPE_UINT64) {
            hasPersonaMgmtEntitlement = xpc_uint64_get_value(personaMgmtVal) == 1;
        } else if (xpc_get_type(personaMgmtVal) == XPC_TYPE_BOOL) {
            hasPersonaMgmtEntitlement = xpc_bool_get_value(personaMgmtVal);
        }
        xpc_release(personaMgmtVal);
    }

    if (!hasPersonaMgmtEntitlement)
        return EACCES;
    if (childPid <= 0)
        return EINVAL;

    pid_t callerPid = audit_token_to_pid(*callerToken);
    if (callerPid <= 0)
        return EINVAL;
    uint64_t callerProc = proc_find(callerPid);
    uint64_t childProc = proc_find(childPid);
    if (!callerProc || !childProc) {
        if (childProc)
            proc_rele(childProc);
        if (callerProc)
            proc_rele(callerProc);
        return ESRCH;
    }

    int status = systemwide_validate_direct_child(callerPid, callerProc, childPid, childProc);
    if (status != 0) {
        JBLogError("persona fix failed phase=plan caller=%d child=%d " "status=%d", callerPid, childPid, status);
        proc_rele(childProc);
        proc_rele(callerProc);
        return status;
    }

    char childProcPath[4 * MAXPATHLEN] = "<unknown>";
    struct proc_ucred_identity originalIdentity = {0};
    struct proc_ucred_identity desiredIdentity = {0};
    bool identityChanged = false;
    if (proc_pidpath(childPid, childProcPath, sizeof(childProcPath)) <= 0) {
        status = ESRCH;
        goto out;
    }

    status = proc_read_ucred_identity(childProc, &originalIdentity);
    if (status != 0)
        goto out;
    desiredIdentity = originalIdentity;
    if (overwriteUid != (uid_t)-1) {
        desiredIdentity.euid = overwriteUid;
        desiredIdentity.ruid = overwriteUid;
        desiredIdentity.svuid = overwriteUid;
    }
    if (overwriteGid != (gid_t)-1) {
        desiredIdentity.egid = overwriteGid;
        desiredIdentity.rgid = overwriteGid;
        desiredIdentity.svgid = overwriteGid;
        desiredIdentity.groups[0] = overwriteGid;
    }
    identityChanged = originalIdentity.euid != desiredIdentity.euid || originalIdentity.ruid != desiredIdentity.ruid
        || originalIdentity.svuid != desiredIdentity.svuid || originalIdentity.egid != desiredIdentity.egid
        || originalIdentity.rgid != desiredIdentity.rgid || originalIdentity.svgid != desiredIdentity.svgid
        || originalIdentity.groups[0] != desiredIdentity.groups[0];
    if (identityChanged) {
        mach_port_t auditSessionPort = MACH_PORT_NULL;
        status = systemwide_copy_audit_session_port(*callerToken, &auditSessionPort);
        if (status != 0) {
            JBLogError("persona fix failed phase=audit-session caller=%d " "child=%d path=%s asid=%u status=%d",
                       callerPid,
                       childPid,
                       childProcPath,
                       audit_token_to_asid(*callerToken),
                       status);
            goto out;
        }
        status = proc_ucred_update_content(childProc,
                                           childProcPath,
                                           &desiredIdentity,
                                           auditSessionPort,
                                           PROC_UCRED_AUDIT_SYNCHRONIZE);
        if (MACH_PORT_VALID(auditSessionPort)) {
            mach_port_deallocate(mach_task_self(), auditSessionPort);
        }
        if (status != 0)
            goto out;
    }

    status = systemwide_update_proc_saved_ids(childProc,
                                              childPid,
                                              childProcPath,
                                              &desiredIdentity,
                                              overwriteUid != (uid_t)-1,
                                              overwriteGid != (gid_t)-1);
    if (status == 0 && identityChanged) {
        status = systemwide_clear_proc_sugid(childProc, childPid, childProcPath);
    }
    if (status == 0 && resumeChild) {
        status = systemwide_validate_direct_child(callerPid, callerProc, childPid, childProc);
        if (status != 0) {
            JBLogError("persona fix failed phase=resume-validate caller=%d " "child=%d path=%s status=%d",
                       callerPid,
                       childPid,
                       childProcPath,
                       status);
        } else if (kill(childPid, SIGCONT) != 0) {
            status = errno != 0 ? errno : EIO;
            JBLogError("persona fix failed phase=resume caller=%d child=%d " "path=%s status=%d",
                       callerPid,
                       childPid,
                       childProcPath,
                       status);
        }
    }

out:
    if (status != 0) {
        int cleanupStatus = 0;
        int validationStatus = systemwide_validate_direct_child(callerPid, callerProc, childPid, childProc);
        if (validationStatus != 0) {
            cleanupStatus = validationStatus;
        } else if (kill(childPid, SIGKILL) != 0 && errno != ESRCH) {
            cleanupStatus = errno != 0 ? errno : EIO;
        }
        JBLogError(
            "persona fix phase=cleanup caller=%d child=%d path=%s " "validation-status=%d status=%d original-status=%d",
            callerPid,
            childPid,
            childProcPath,
            validationStatus,
            cleanupStatus,
            status);
    }
    proc_rele(childProc);
    proc_rele(callerProc);
    return status;
}

struct jbserver_domain gSystemwideDomain = {
	.permissionHandler = roothide_domain_allowed,
	.actions = {
		// JBS_SYSTEMWIDE_GET_JBROOT
		{
			.handler = systemwide_get_jbroot,
			.args = (jbserver_arg[]){
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_GET_BOOT_UUID
		{
			.handler = systemwide_get_boot_uuid,
			.args = (jbserver_arg[]){
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_TRUST_FILE
		{
			.handler = systemwide_trust_file,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "fd", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "siginfo", .type = JBS_TYPE_DATA, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_PROCESS_CHECKIN
		{
			.handler = systemwide_process_checkin,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "sandbox-extensions", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "fully-debugged", .type = JBS_TYPE_BOOL, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_FORK_FIX
		{
			.handler = systemwide_fork_fix,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_CS_REVALIDATE
		{
			.handler = systemwide_cs_revalidate,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_JBSETTINGS_GET
		{
			.handler = jbsettings_get,
			.args = (jbserver_arg[]){
				{ .name = "key", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "value", .type = JBS_TYPE_XPC_GENERIC, .out = true },
			},
		},
		// JBS_SYSTEMWIDE_PERSONA_FIX
		{
			.handler = systemwide_persona_fix,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "overwrite-uid", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "overwrite-gid", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "resume-child", .type = JBS_TYPE_BOOL, .out = false },
			},
		},
		{ 0 },
	},
};
