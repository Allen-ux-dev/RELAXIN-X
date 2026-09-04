/*
 * rlx-dump-kernel-offsets — prints, as JSON, everything Relaxin reads out of a
 * kernelcache file.
 *
 * This is the generator half of the offset table. It compiles the engine's own
 * StaticProfile.c and Patterns.c, so what it prints is by construction what the
 * device would have computed from the same file; the table is a cache of this
 * program's output, not a second opinion about it.
 *
 *     rlx-dump-kernel-offsets <kernelcache>
 */

#include "../../../RelaxinEngine/KernelAccess/Exploit/Rocket/Profile/StaticProfile.h"

#include <xpf/xpf.h>
#include <xpc/xpc.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void rocket_static_profile_log(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
}

static void print_json_string(FILE *stream, const char *value) {
    fputc('"', stream);
    for (const unsigned char *cursor = (const unsigned char *)(value ?: ""); *cursor; cursor++) {
        switch (*cursor) {
            case '"':
                fputs("\\\"", stream);
                break;
            case '\\':
                fputs("\\\\", stream);
                break;
            case '\n':
                fputs("\\n", stream);
                break;
            case '\r':
                fputs("\\r", stream);
                break;
            case '\t':
                fputs("\\t", stream);
                break;
            default:
                if (*cursor < 0x20)
                    fprintf(stream, "\\u%04x", *cursor);
                else
                    fputc(*cursor, stream);
                break;
        }
    }
    fputc('"', stream);
}

/*
 * The dictionary carries uint64, bool, and string values. Everything is emitted
 * with its type named, so the table builder never has to guess how to hand a
 * value back to libjailbreak's deserializer.
 */
static void print_offset_dictionary(FILE *stream, xpc_object_t dictionary) {
    __block bool first = true;
    fputs("  \"offsetDictionary\": {\n", stream);
    xpc_dictionary_apply(dictionary, ^bool(const char *key, xpc_object_t value) {
        xpc_type_t type = xpc_get_type(value);
        const char *kind = NULL;
        char rendered[512] = {0};

        if (type == XPC_TYPE_UINT64) {
            kind = "uint64";
            snprintf(rendered, sizeof(rendered), "%llu", xpc_uint64_get_value(value));
        } else if (type == XPC_TYPE_BOOL) {
            kind = "bool";
            snprintf(rendered, sizeof(rendered), "%s", xpc_bool_get_value(value) ? "true" : "false");
        } else if (type == XPC_TYPE_DOUBLE) {
            kind = "double";
            snprintf(rendered, sizeof(rendered), "%.17g", xpc_double_get_value(value));
        } else if (type == XPC_TYPE_STRING) {
            kind = "string";
        } else {
            return true;
        }

        if (!first)
            fputs(",\n", stream);
        first = false;
        fputs("    ", stream);
        print_json_string(stream, key);
        fputs(": {\"type\": \"", stream);
        fputs(kind, stream);
        fputs("\", \"value\": ", stream);
        if (type == XPC_TYPE_STRING)
            print_json_string(stream, xpc_string_get_string_ptr(value));
        else
            fputs(rendered, stream);
        fputs("}", stream);
        return true;
    });
    fputs("\n  }\n", stream);
}

static void print_gfx_offsets(FILE *stream, const PhysrwGfxResolvedOffsets *offsets) {
    fprintf(
        stream,
        "  \"gfxOffsets\": {\n" "    \"userClientToOwnerOffset\": %u,\n" "    \"submitObjectAddressOffset\": %u,\n" "    \"ownerToStateOffset\": %u,\n" "    \"stateControlOffset\": %u,\n" "    \"ownerPatchedPointerOffset\": %u,\n" "    \"stateSubmitObjectOffset\": %u,\n" "    \"stateAddressBiasOffset\": %u,\n" "    \"stateLengthOffset\": %u,\n" "    \"ownerResourceTableOffset\": %u,\n" "    \"resourceTableEntriesOffset\": %u,\n" "    \"resourceObjectMemoryOffset\": %u,\n" "    \"resourceMemoryAddressOffset\": %u,\n" "    \"ioGpuUserClientTypeStaticAddress\": %llu,\n" "    \"mobileFramebufferUserClientTypeStaticAddress\": %llu,\n" "    \"agxSubmitHandlerVtableAddress\": %llu\n" "  },\n",
        offsets->userClientToOwnerOffset,
        offsets->submitObjectAddressOffset,
        offsets->ownerToStateOffset,
        offsets->stateControlOffset,
        offsets->ownerPatchedPointerOffset,
        offsets->stateSubmitObjectOffset,
        offsets->stateAddressBiasOffset,
        offsets->stateLengthOffset,
        offsets->ownerResourceTableOffset,
        offsets->resourceTableEntriesOffset,
        offsets->resourceObjectMemoryOffset,
        offsets->resourceMemoryAddressOffset,
        offsets->ioGpuUserClientTypeStaticAddress,
        offsets->mobileFramebufferUserClientTypeStaticAddress,
        offsets->agxSubmitHandlerVtableAddress);
}

static void print_profile(FILE *stream,
                          const RocketStaticKernelProfile *profile,
                          const char *const *sets,
                          size_t setCount,
                          xpc_object_t dictionary) {
    fputs("{\n", stream);
    fprintf(stream, "  \"profileVersion\": %u,\n", profile->version);

    fputs("  \"xnuBuild\": ", stream);
    print_json_string(stream, profile->xnuBuild);
    fputs(",\n  \"osVersion\": ", stream);
    print_json_string(stream, profile->osVersion);
    fputs(",\n", stream);

    fprintf(
        stream,
        "  \"staticKernelBase\": %llu,\n" "  \"sptmArgs\": %llu,\n" "  \"xnuVersionPacked\": %llu,\n" "  \"isArm64e\": %s,\n" "  \"isSPTMDevice\": %s,\n" "  \"isFileset\": %s,\n" "  \"hasPPLTextSection\": %s,\n" "  \"hasGFXOffsets\": %s,\n",
        profile->staticKernelBase,
        profile->sptmArgs,
        profile->xnuVersionPacked,
        profile->isArm64e ? "true" : "false",
        profile->isSPTMDevice ? "true" : "false",
        profile->isFileset ? "true" : "false",
        profile->hasPPLTextSection ? "true" : "false",
        profile->hasGFXOffsets ? "true" : "false");

    fprintf(
        stream,
        "  \"symbols\": {\n" "    \"cpu_ttep\": %llu,\n" "    \"gVirtBase\": %llu,\n" "    \"gPhysBase\": %llu,\n" "    \"gPhysSize\": %llu,\n" "    \"ptov_table\": %llu,\n" "    \"allproc\": %llu,\n" "    \"vm_map_pmap\": %llu,\n" "    \"arm_tt_l1_index_mask\": %llu,\n" "    \"t1sz_boot\": %llu,\n" "    \"kernel_el\": %llu\n" "  },\n",
        profile->symbols.cpu_ttep,
        profile->symbols.gVirtBase,
        profile->symbols.gPhysBase,
        profile->symbols.gPhysSize,
        profile->symbols.ptov_table,
        profile->symbols.allproc,
        profile->symbols.vm_map_pmap,
        profile->symbols.arm_tt_l1_index_mask,
        profile->symbols.t1sz_boot,
        profile->symbols.kernel_el);

    print_gfx_offsets(stream, &profile->gfxOffsets);

    fputs("  \"offsetSets\": [", stream);
    for (size_t index = 0; index < setCount; index++) {
        if (index)
            fputs(", ", stream);
        print_json_string(stream, sets[index]);
    }
    fputs("],\n", stream);

    print_offset_dictionary(stream, dictionary);
    fputs("}\n", stream);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <kernelcache>\n", argv[0]);
        return 2;
    }

    if (xpf_start_with_kernel_path(argv[1]) != 0) {
        fprintf(stderr, "[-] xpf_start %s: %s\n", argv[1], xpf_get_error() ?: "unknown");
        return 1;
    }

    RocketStaticKernelProfile profile = {0};
    if (!rocket_static_profile_collect(&profile)) {
        fprintf(stderr, "[-] profile %s: incomplete\n", argv[1]);
        xpf_stop();
        return 1;
    }

    const char *sets[ROCKET_STATIC_PROFILE_OFFSET_SET_MAX] = {0};
    size_t setCount = rocket_static_profile_offset_sets(sets, ROCKET_STATIC_PROFILE_OFFSET_SET_MAX);
    xpc_object_t dictionary = xpf_construct_offset_dictionary(sets);
    if (!dictionary) {
        fprintf(stderr, "[-] offset dictionary %s: %s\n", argv[1], xpf_get_error() ?: "unknown");
        xpf_stop();
        return 1;
    }

    /*
     * The engine sets this on the dictionary it hands libjailbreak, so the
     * table has to carry it too — it is the base every slide is measured from.
     */
    xpc_dictionary_set_uint64(dictionary, "kernelConstant.staticBase", profile.staticKernelBase);

    print_profile(stdout, &profile, sets, setCount, dictionary);

    xpc_release(dictionary);
    xpf_stop();
    return 0;
}
