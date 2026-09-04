// Derived from Dopamine-lbr77 tooling; see LICENSE.md.

#include <errno.h>
#include <fcntl.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    kEmbeddedSignatureMagic = 0xfade0cc0,
    kCodeDirectoryMagic = 0xfade0c02,
    kBlobWrapperMagic = 0xfade0b01,
    kCodeDirectorySlot = 0,
    kAlternateCodeDirectoryFirst = 0x1000,
    kAlternateCodeDirectoryLimit = 0x1005,
    kSignatureSlot = 0x10000,
    kAdHocFlag = 0x2,
};

static uint32_t read_le32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static uint32_t read_be32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
}

static uint64_t read_be64(const uint8_t *bytes) {
    return ((uint64_t)read_be32(bytes) << 32) | read_be32(bytes + 4);
}

static bool range_is_within(uint64_t offset, uint64_t size, uint64_t limit) {
    return offset <= limit && size <= limit - offset;
}

static int verify_superblob(const uint8_t *bytes, size_t size, const char *path, uint32_t slice_index) {
    if (size < 12 || read_be32(bytes) != kEmbeddedSignatureMagic) {
        fprintf(stderr, "%s: slice %u has an invalid embedded signature\n", path, slice_index);
        return EBADEXEC;
    }

    uint32_t declared_size = read_be32(bytes + 4);
    uint32_t count = read_be32(bytes + 8);
    if (declared_size < 12 || declared_size > size || count > (declared_size - 12) / 8) {
        fprintf(stderr, "%s: slice %u has invalid SuperBlob bounds\n", path, slice_index);
        return EBADEXEC;
    }

    uint32_t data_start = 12 + count * 8;
    uint32_t code_directory_count = 0;
    uint32_t signature_slot_count = 0;
    for (uint32_t index = 0; index < count; index++) {
        uint32_t type = read_be32(bytes + 12 + index * 8);
        uint32_t offset = read_be32(bytes + 16 + index * 8);
        if (offset < data_start || !range_is_within(offset, 8, declared_size)) {
            fprintf(stderr, "%s: slice %u has invalid slot 0x%x bounds\n", path, slice_index, type);
            return EBADEXEC;
        }

        uint32_t magic = read_be32(bytes + offset);
        uint32_t blob_size = read_be32(bytes + offset + 4);
        if (blob_size < 8 || !range_is_within(offset, blob_size, declared_size)) {
            fprintf(stderr, "%s: slice %u has invalid slot 0x%x size\n", path, slice_index, type);
            return EBADEXEC;
        }

        bool code_directory = type == kCodeDirectorySlot
            || (type >= kAlternateCodeDirectoryFirst && type < kAlternateCodeDirectoryLimit);
        if (code_directory) {
            if (magic != kCodeDirectoryMagic || blob_size < 16 || !(read_be32(bytes + offset + 12) & kAdHocFlag)) {
                fprintf(stderr, "%s: slice %u CodeDirectory 0x%x lacks CS_ADHOC\n", path, slice_index, type);
                return EBADEXEC;
            }
            code_directory_count++;
        } else if (type == kSignatureSlot) {
            if (magic != kBlobWrapperMagic || blob_size != 8) {
                fprintf(stderr, "%s: slice %u contains a non-empty CMS signature\n", path, slice_index);
                return EBADEXEC;
            }
            signature_slot_count++;
        }
    }

    if (!code_directory_count || signature_slot_count > 1) {
        fprintf(stderr, "%s: slice %u is not unambiguously ad-hoc signed\n", path, slice_index);
        return EBADEXEC;
    }
    return 0;
}

static int verify_slice(const uint8_t *bytes, size_t size, const char *path, uint32_t slice_index) {
    if (size < sizeof(struct mach_header_64) || read_le32(bytes) != MH_MAGIC_64) {
        fprintf(stderr, "%s: slice %u is not a 64-bit Mach-O\n", path, slice_index);
        return EBADEXEC;
    }

    uint32_t command_count = read_le32(bytes + 16);
    uint32_t command_bytes = read_le32(bytes + 20);
    uint64_t command_offset = sizeof(struct mach_header_64);
    if (!range_is_within(command_offset, command_bytes, size)) {
        fprintf(stderr, "%s: slice %u has invalid load-command bounds\n", path, slice_index);
        return EBADEXEC;
    }

    uint32_t signature_count = 0;
    for (uint32_t index = 0; index < command_count; index++) {
        if (!range_is_within(command_offset, sizeof(struct load_command), size)) {
            return EBADEXEC;
        }

        const uint8_t *command = bytes + command_offset;
        uint32_t type = read_le32(command);
        uint32_t command_size = read_le32(command + 4);
        if (command_size < sizeof(struct load_command) || !range_is_within(command_offset, command_size, size)) {
            fprintf(stderr, "%s: slice %u has an invalid load command\n", path, slice_index);
            return EBADEXEC;
        }

        if (type == LC_CODE_SIGNATURE) {
            if (command_size < sizeof(struct linkedit_data_command)) {
                return EBADEXEC;
            }

            uint32_t offset = read_le32(command + 8);
            uint32_t signature_size = read_le32(command + 12);
            if (!range_is_within(offset, signature_size, size)) {
                fprintf(stderr, "%s: slice %u has invalid LC_CODE_SIGNATURE bounds\n", path, slice_index);
                return EBADEXEC;
            }

            int result = verify_superblob(bytes + offset, signature_size, path, slice_index);
            if (result != 0) {
                return result;
            }
            signature_count++;
        }

        command_offset += command_size;
    }

    if (signature_count != 1) {
        fprintf(stderr, "%s: slice %u requires one LC_CODE_SIGNATURE\n", path, slice_index);
        return EBADEXEC;
    }
    return 0;
}

static int verify_file(const char *path) {
    int descriptor = open(path, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
        return errno;
    }

    struct stat info = {0};
    if (fstat(descriptor, &info) != 0 || info.st_size < 4) {
        int result = errno ? errno : EBADEXEC;
        close(descriptor);
        return result;
    }

    size_t size = (size_t)info.st_size;
    const uint8_t *bytes = mmap(NULL, size, PROT_READ, MAP_PRIVATE, descriptor, 0);
    close(descriptor);
    if (bytes == MAP_FAILED) {
        return errno;
    }

    int result = 0;
    uint32_t fat_magic = read_be32(bytes);
    if (fat_magic == FAT_MAGIC || fat_magic == FAT_MAGIC_64) {
        bool fat64 = fat_magic == FAT_MAGIC_64;
        uint32_t count = size >= 8 ? read_be32(bytes + 4) : 0;
        uint32_t architecture_size = fat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
        if (!count || !range_is_within(8, (uint64_t)count * architecture_size, size)) {
            result = EBADEXEC;
        }

        for (uint32_t index = 0; result == 0 && index < count; index++) {
            const uint8_t *architecture = bytes + 8 + index * architecture_size;
            uint64_t offset = fat64 ? read_be64(architecture + 8) : read_be32(architecture + 8);
            uint64_t slice_size = fat64 ? read_be64(architecture + 16) : read_be32(architecture + 12);
            if (!range_is_within(offset, slice_size, size)) {
                result = EBADEXEC;
            } else {
                result = verify_slice(bytes + offset, (size_t)slice_size, path, index);
            }
        }
    } else {
        result = verify_slice(bytes, size, path, 0);
    }

    munmap((void *)bytes, size);
    return result;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <Mach-O> [...]\n", argv[0]);
        return 64;
    }

    for (int index = 1; index < argc; index++) {
        int result = verify_file(argv[index]);
        if (result != 0) {
            fprintf(stderr, "%s: ad-hoc signature verification failed: %s\n", argv[index], strerror(result));
            return result;
        }
    }
    return 0;
}
