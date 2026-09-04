#include "signature_policy.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(bool condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

static void write_big_endian_u32(uint8_t *bytes, uint32_t value) {
    bytes[0] = (uint8_t)(value >> 24);
    bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8);
    bytes[3] = (uint8_t)value;
}

static void test_macho_magic_filter(void) {
    const uint8_t macho32[] = {0xce, 0xfa, 0xed, 0xfe};
    const uint8_t macho64[] = {0xcf, 0xfa, 0xed, 0xfe};
    const uint8_t swappedMacho32[] = {0xfe, 0xed, 0xfa, 0xce};
    const uint8_t swappedMacho64[] = {0xfe, 0xed, 0xfa, 0xcf};
    const uint8_t fat32[] = {0xca, 0xfe, 0xba, 0xbe};
    const uint8_t fat64[] = {0xca, 0xfe, 0xba, 0xbf};
    const uint8_t swappedFat32[] = {0xbe, 0xba, 0xfe, 0xca};
    const uint8_t swappedFat64[] = {0xbf, 0xba, 0xfe, 0xca};
    const uint8_t propertyList[] = {'<', '?', 'x', 'm'};
    const uint8_t shortFile[] = {0xcf, 0xfa, 0xed};

    require(roothide_signature_has_macho_magic(macho32, sizeof(macho32)), "32-bit Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(macho64, sizeof(macho64)), "64-bit Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(swappedMacho32, sizeof(swappedMacho32)),
            "byte-swapped 32-bit Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(swappedMacho64, sizeof(swappedMacho64)),
            "byte-swapped 64-bit Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(fat32, sizeof(fat32)), "32-bit FAT Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(fat64, sizeof(fat64)), "64-bit FAT Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(swappedFat32, sizeof(swappedFat32)),
            "byte-swapped 32-bit FAT Mach-O magic should be accepted");
    require(roothide_signature_has_macho_magic(swappedFat64, sizeof(swappedFat64)),
            "byte-swapped 64-bit FAT Mach-O magic should be accepted");
    require(!roothide_signature_has_macho_magic(propertyList, sizeof(propertyList)),
            "a property list prefix must not be treated as Mach-O");
    require(!roothide_signature_has_macho_magic(shortFile, sizeof(shortFile)),
            "a truncated magic must not be treated as Mach-O");
    require(!roothide_signature_has_macho_magic(NULL, sizeof(macho64)), "a null prefix must not be treated as Mach-O");
}

static void test_runtime_policy(void) {
    const uint32_t otherFlag = UINT32_C(0x00000100);
    const uint32_t adhocFlag = ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC;
    const struct {
        bool usesSPTM;
        bool hasTeamID;
        bool startsAdhoc;
        bool endsAdhoc;
        const char *message;
    } cases[] = {
        {false, false, false, true, "PPL must add CS_ADHOC without TeamID"},
        {false, false, true, true, "PPL must retain CS_ADHOC without TeamID"},
        {false, true, false, true, "PPL must add CS_ADHOC with TeamID"},
        {false, true, true, true, "PPL must retain CS_ADHOC with TeamID"},
        {true, false, false, true, "SPTM must add CS_ADHOC without TeamID"},
        {true, false, true, true, "SPTM must retain CS_ADHOC without TeamID"},
        {true, true, false, false, "SPTM must retain non-adhoc flags with TeamID"},
        {true, true, true, false, "SPTM must remove CS_ADHOC with TeamID"},
    };

    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        uint32_t initialFlags = otherFlag | (cases[index].startsAdhoc ? adhocFlag : 0);
        uint32_t expectedFlags = otherFlag | (cases[index].endsAdhoc ? adhocFlag : 0);
        uint32_t actualFlags = roothide_signature_normalize_code_directory_flags(initialFlags,
                                                                                 cases[index].usesSPTM,
                                                                                 cases[index].hasTeamID);
        require(actualFlags == expectedFlags, cases[index].message);
    }
}

static void test_partial_preparation_is_retried(void) {
    uint32_t flags = ROOTHIDE_CODE_DIRECTORY_FLAG_ADHOC;
    require(roothide_signature_is_prepared(flags, true, false, true, true),
            "all preparation invariants should be accepted");
    require(!roothide_signature_is_prepared(flags, true, false, false, true),
            "missing jbrand must require preparation");
    require(!roothide_signature_is_prepared(flags, true, false, true, false),
            "a stale page-zero hash must require preparation even after jbrand was written");
    require(!roothide_signature_is_prepared(flags, true, true, true, true),
            "a stale SPTM CS_ADHOC flag must require preparation");
}

static void test_code_directory_layout(void) {
    require(roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020200), 128, 64, 32, 2, 2, 12),
            "a bounded SHA-256 CodeDirectory layout should be accepted");
    require(roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020600), 144, 112, 32, 3, 1, 14),
            "the known 0x20600 header and 16K pages should be accepted");
    require(!roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020600), 96, 64, 32, 2, 1, 12),
            "a CodeDirectory shorter than its versioned header must be rejected");
    require(!roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020200), 128, 48, 32, 1, 1, 12),
            "the code-slot table must not overlap the CodeDirectory header");
    require(!roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020200), 128, 64, 32, 3, 2, 12),
            "special slots before hashOffset must fit in the buffer");
    require(!roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020200), 128, 64, 32, 2, 3, 12),
            "all declared code slots must fit in the CodeDirectory");
    require(!roothide_signature_code_directory_layout_is_valid(UINT32_C(0x00020200), 128, 64, 32, 2, 2, 13),
            "unsupported code-signing page shifts must be rejected");
}

static void require_team_id_state(uint32_t version,
                                  uint32_t offset,
                                  const uint8_t *bytes,
                                  size_t size,
                                  roothide_team_id_state_t expected,
                                  const char *message) {
    require(roothide_signature_team_id_state(version, offset, bytes, size) == expected, message);
}

static void test_team_id_parser(void) {
    uint8_t codeDirectory[80] = {0};
    memcpy(codeDirectory + 64, "TEAMID", sizeof("TEAMID"));

    require_team_id_state(UINT32_C(0x00020100),
                          64,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_ABSENT,
                          "old CodeDirectory versions do not carry TeamID");
    require_team_id_state(UINT32_C(0x00020200),
                          0,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_ABSENT,
                          "zero TeamID offset means absent");
    require_team_id_state(UINT32_C(0x00020200),
                          64,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_PRESENT,
                          "bounded non-empty TeamID should be accepted");
    require_team_id_state(UINT32_C(0x00020600),
                          64,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_INVALID,
                          "TeamID must not point into the versioned CodeDirectory header");
    require_team_id_state(UINT32_C(0x00020200),
                          80,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_INVALID,
                          "out-of-range TeamID must be rejected");

    memset(codeDirectory + 64, 'A', sizeof(codeDirectory) - 64);
    require_team_id_state(UINT32_C(0x00020200),
                          64,
                          codeDirectory,
                          sizeof(codeDirectory),
                          ROOTHIDE_TEAM_ID_INVALID,
                          "unterminated TeamID must be rejected");
}

static void make_valid_superblob(uint8_t bytes[28]) {
    memset(bytes, 0, 28);
    write_big_endian_u32(bytes, UINT32_C(0xfade0cc0));
    write_big_endian_u32(bytes + 4, 28);
    write_big_endian_u32(bytes + 8, 1);
    write_big_endian_u32(bytes + 12, 0);
    write_big_endian_u32(bytes + 16, 20);
    write_big_endian_u32(bytes + 20, UINT32_C(0xfade0c02));
    write_big_endian_u32(bytes + 24, 8);
}

static void test_superblob_bounds(void) {
    uint8_t bytes[28];
    make_valid_superblob(bytes);
    require(!roothide_signature_superblob_is_valid(NULL, sizeof(bytes)), "a null superblob must be rejected");
    require(roothide_signature_superblob_is_valid(bytes, sizeof(bytes)), "bounded superblob should be accepted");
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes) - 1),
            "declared length beyond the owned buffer must be rejected");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes + 8, 3);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "index table beyond the superblob must be rejected");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes, 0);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "an unknown superblob magic must be rejected");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes + 16, 12);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "a blob must not overlap the superblob index table");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes + 16, 27);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "blob header beyond the superblob must be rejected");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes + 24, 7);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "a blob shorter than its generic header must be rejected");

    make_valid_superblob(bytes);
    write_big_endian_u32(bytes + 24, 9);
    require(!roothide_signature_superblob_is_valid(bytes, sizeof(bytes)),
            "blob length beyond the superblob must be rejected");
    require(!roothide_signature_superblob_is_valid(bytes, ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE + 1U),
            "signature buffers above the kernel limit must be rejected before parsing");
}

static void test_file_range_resolution(void) {
    uint64_t resolvedStart = 0;
    require(roothide_signature_resolve_file_range(16, 32, 64, 128, &resolvedStart) && resolvedStart == 48,
            "bounded file signature range should resolve");
    require(roothide_signature_resolve_file_range(16, 32, 64, 112, &resolvedStart) && resolvedStart + 64 == 112,
            "a signature range ending exactly at EOF should resolve");
    require(!roothide_signature_resolve_file_range(-1, 0, 64, 112, &resolvedStart),
            "negative slice offsets must be rejected");
    require(!roothide_signature_resolve_file_range(16, UINT64_MAX, 64, 112, &resolvedStart),
            "slice and blob offset overflow must be rejected");
    require(!roothide_signature_resolve_file_range(16, 32, 65, 112, &resolvedStart),
            "signature ranges beyond EOF must be rejected");
    require(!roothide_signature_resolve_file_range(16, 32, 0, 112, &resolvedStart),
            "empty signature ranges must be rejected");
    require(!roothide_signature_resolve_file_range(16,
                                                   32,
                                                   ROOTHIDE_SIGNATURE_MAX_BLOB_SIZE + 1U,
                                                   UINT64_MAX,
                                                   &resolvedStart),
            "oversized signature ranges must be rejected");
    require(!roothide_signature_resolve_file_range(16, 32, 64, 112, NULL), "a missing range output must be rejected");
}

int main(void) {
    test_macho_magic_filter();
    test_runtime_policy();
    test_partial_preparation_is_retried();
    test_code_directory_layout();
    test_team_id_parser();
    test_superblob_bounds();
    test_file_range_resolution();
    puts("RootHide signature policy tests passed");
    return 0;
}
