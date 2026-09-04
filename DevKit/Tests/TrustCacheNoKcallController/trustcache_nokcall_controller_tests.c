#include "trustcache_nokcall_controller.h"

#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FK_BASE UINT64_C(0xfffffff000000000)
#define FK_SIZE (16U * 1024U * 1024U)
#define FK_LIST_SLOT (FK_BASE + UINT64_C(0x100))
#define FK_NODE_START (FK_BASE + UINT64_C(0x1000))
#define FK_MODULE_START (FK_BASE + UINT64_C(0x10000))
#define FK_NODE_STEP UINT64_C(0x40)
#define FK_MODULE_STEP UINT64_C(0x1000)
#define FK_CAPACITY 8U
#define FK_STRIDE ((size_t)sizeof(tcnm_entry))
#define FK_MODULE_SIZE (TCNM_FILE_HEADER_SIZE + FK_CAPACITY * FK_STRIDE)
#define FK_MAX_NODES 2048U

typedef struct {
    uint64_t next;
    uint64_t previous;
    uint8_t type;
    uint8_t reserved[7];
    uint64_t moduleSize;
    uint64_t module;
} fake_node;

typedef struct {
    uint32_t version;
    uint8_t marker[TCNM_MARKER_SIZE];
    uint32_t capacity;
    uint8_t payload[FK_CAPACITY * sizeof(tcnm_entry)];
} __attribute__((packed)) fake_module;

_Static_assert(sizeof(fake_node) == 40U, "fake node layout");
_Static_assert(sizeof(fake_module) == FK_MODULE_SIZE, "fake module layout");

typedef struct {
    uint8_t *memory;
    uint32_t nodeCount;
    uint8_t moduleSkew;
    uint32_t nonceSerial;
    uint64_t protectedCalls;
    uint64_t subwriteEvents;
    uint64_t failProtectedCall;
    uint64_t crashSubwrite;
    uint64_t failReadCall;
    uint64_t readCalls;
    uint64_t failReadAddress;
    uint32_t failReadAddressVisit;
    uint32_t readAddressVisits;
    uint32_t reloadCalls;
    int forcedReloadStatus;
    bool sessionCrashed;
    bool failReloadBeforeLink;
    bool failReloadAfterLink;
    bool reloadAddsUnexpectedNode;
    bool invalidLiveTableObserved;
    bool missingRequiredHashObserved;
    uint32_t requiredHashCount;
    uint8_t requiredHashes[FK_CAPACITY][TCNM_HASH_SIZE];
    uint8_t appSource[FK_MODULE_SIZE];
    uint8_t osSource[FK_MODULE_SIZE];
} fake_kernel;

typedef struct {
    unsigned int failures;
} test_state;

static test_state gTest;

static bool fk_all_live_tables_valid(fake_kernel *kernel);
static bool fk_required_hashes_are_live(fake_kernel *kernel);

#define EXPECT_TRUE(expression) \
	do { \
		if (!(expression)) { \
			fprintf(stderr, "%s:%d: expected true: %s\n", \
			        __FILE__, __LINE__, #expression); \
			gTest.failures++; \
		} \
	} while (0)

#define EXPECT_EQ(expected, observed) \
	do { \
		long long expectedValue = (long long)(expected); \
		long long observedValue = (long long)(observed); \
		if (expectedValue != observedValue) { \
			fprintf(stderr, \
			        "%s:%d: expected %lld, observed %lld: %s\n", \
			        __FILE__, __LINE__, expectedValue, observedValue, \
			        #observed); \
			gTest.failures++; \
		} \
	} while (0)

static void *fk_pointer(fake_kernel *kernel, uint64_t address, size_t size) {
    if (!kernel || address < FK_BASE)
        return NULL;
    uint64_t offset = address - FK_BASE;
    if (offset > FK_SIZE || size > FK_SIZE - (size_t)offset)
        return NULL;
    return kernel->memory + (size_t)offset;
}

static const void *fk_const_pointer(const fake_kernel *kernel, uint64_t address, size_t size) {
    return fk_pointer((fake_kernel *)kernel, address, size);
}

static tcnm_entry fk_entry(uint8_t first, uint8_t tail) {
    tcnm_entry entry = {0};
    entry.hash[0] = first;
    entry.hash[TCNM_HASH_SIZE - 1] = tail;
    entry.hashType = 2;
    return entry;
}

static void fk_build_source(uint8_t kind, uint8_t bytes[FK_MODULE_SIZE]) {
    fake_module module = {
        .version = 1,
        .capacity = FK_CAPACITY,
    };
    for (size_t index = 0; index < sizeof(module.marker); index++) {
        module.marker[index] = (uint8_t)(kind + index);
    }
    tcnm_entry signedEntry = fk_entry(kind, 1);
    memcpy(module.payload + (FK_CAPACITY - 1) * FK_STRIDE, &signedEntry, sizeof(signedEntry));
    memcpy(bytes, &module, sizeof(module));
}

static fake_node *fk_node(fake_kernel *kernel, uint32_t index) {
    return fk_pointer(kernel, FK_NODE_START + (uint64_t)index * FK_NODE_STEP, sizeof(fake_node));
}

static uint32_t fk_type_count(fake_kernel *kernel, uint8_t type) {
    uint32_t count = 0;
    for (uint32_t index = 0; index < kernel->nodeCount; index++) {
        fake_node *node = fk_node(kernel, index);
        if (node && node->type == type)
            count++;
    }
    return count;
}

static bool fk_linked_nodes_are_terminal(fake_kernel *kernel) {
    for (uint32_t index = 0; index < kernel->nodeCount; index++) {
        fake_node *node = fk_node(kernel, index);
        if (!node)
            return false;
        fake_module *module = fk_pointer(kernel, node->module, FK_MODULE_SIZE);
        if (!module)
            return false;

        bool markerKnown = module->marker[TCNM_MARKER_VERSION_OFFSET] == TCNM_MARKER_VERSION;
        if (node->type == 2) {
            if (!markerKnown || module->marker[TCNM_MARKER_PHASE_OFFSET] != TCNM_MARKER_PHASE_READY) {
                return false;
            }
        } else if (markerKnown) {
            return false;
        }
    }
    return true;
}

static uint64_t fk_module_address(const fake_kernel *kernel, uint32_t index) {
    return FK_MODULE_START + (uint64_t)index * FK_MODULE_STEP + kernel->moduleSkew;
}

static int fk_link_source(fake_kernel *kernel, uint8_t kind) {
    if (kernel->nodeCount >= FK_MAX_NODES)
        return ENOSPC;
    uint32_t index = kernel->nodeCount++;
    fake_node *node = fk_node(kernel, index);
    uint64_t moduleAddress = fk_module_address(kernel, index);
    uint8_t *module = fk_pointer(kernel, moduleAddress, FK_MODULE_SIZE);
    if (!node || !module)
        return EFAULT;
    memset(node, 0, sizeof(*node));
    node->previous = index ? FK_NODE_START + (uint64_t)(index - 1) * FK_NODE_STEP : 0;
    node->type = kind;
    node->moduleSize = FK_MODULE_SIZE;
    node->module = moduleAddress;
    memcpy(module, kind == TCNM_SOURCE_APP ? kernel->appSource : kernel->osSource, FK_MODULE_SIZE);
    if (index) {
        fake_node *previous = fk_node(kernel, index - 1);
        previous->next = FK_NODE_START + (uint64_t)index * FK_NODE_STEP;
    } else {
        uint64_t *slot = fk_pointer(kernel, FK_LIST_SLOT, sizeof(*slot));
        *slot = FK_NODE_START;
    }
    return 0;
}

static int fk_insert_unmanaged_shared_after(fake_kernel *kernel,
                                            uint32_t predecessorIndex,
                                            uint32_t capacity,
                                            uint32_t *indexOut) {
    if (!kernel || !capacity || capacity > FK_CAPACITY || predecessorIndex >= kernel->nodeCount
        || kernel->nodeCount >= FK_MAX_NODES) {
        return EINVAL;
    }
    uint32_t index = kernel->nodeCount++;
    fake_node *predecessor = fk_node(kernel, predecessorIndex);
    fake_node *node = fk_node(kernel, index);
    uint64_t nodeAddress = FK_NODE_START + (uint64_t)index * FK_NODE_STEP;
    uint64_t moduleAddress = fk_module_address(kernel, index);
    fake_module *module = fk_pointer(kernel, moduleAddress, FK_MODULE_SIZE);
    if (!predecessor || !node || !module)
        return EFAULT;

    memset(node, 0, sizeof(*node));
    memset(module, 0, sizeof(*module));
    node->next = predecessor->next;
    node->type = 2;
    node->moduleSize = FK_MODULE_SIZE;
    node->module = moduleAddress;
    module->version = 1;
    module->capacity = capacity;
    tcnm_entry entry = fk_entry((uint8_t)(0x70 + index), 1);
    memcpy(module->payload + (size_t)(capacity - 1) * FK_STRIDE, &entry, sizeof(entry));
    predecessor->next = nodeAddress;
    if (indexOut)
        *indexOut = index;
    return 0;
}

static int fk_insert_oversized_foreign_source_after_head(fake_kernel *kernel, uint32_t *indexOut) {
    if (!kernel || kernel->nodeCount >= FK_MAX_NODES)
        return EINVAL;
    uint32_t index = kernel->nodeCount++;
    fake_node *head = fk_node(kernel, 0);
    fake_node *node = fk_node(kernel, index);
    uint64_t nodeAddress = FK_NODE_START + (uint64_t)index * FK_NODE_STEP;
    uint64_t moduleAddress = fk_module_address(kernel, index);
    size_t moduleSize = FK_MODULE_SIZE + sizeof(uint64_t);
    uint8_t *module = fk_pointer(kernel, moduleAddress, moduleSize);
    if (!head || !node || !module)
        return EFAULT;

    memset(node, 0, sizeof(*node));
    node->next = head->next;
    node->type = TCNM_SOURCE_APP;
    node->moduleSize = moduleSize;
    node->module = moduleAddress;
    memcpy(module, kernel->appSource, FK_MODULE_SIZE);
    memset(module + FK_MODULE_SIZE, 0xa5, sizeof(uint64_t));
    head->next = nodeAddress;
    if (indexOut)
        *indexOut = index;
    return 0;
}

static bool fk_previous_links_match_forward_chain(fake_kernel *kernel) {
    uint64_t *listSlot = fk_pointer(kernel, FK_LIST_SLOT, sizeof(*listSlot));
    if (!listSlot)
        return false;
    uint64_t address = *listSlot;
    uint64_t expectedPrevious = 0;
    uint32_t observedCount = 0;
    while (address) {
        if (observedCount++ >= kernel->nodeCount)
            return false;
        fake_node *node = fk_pointer(kernel, address, sizeof(*node));
        if (!node || node->previous != expectedPrevious)
            return false;
        expectedPrevious = address;
        address = node->next;
    }
    return observedCount == kernel->nodeCount;
}

static int fk_initialize_with_module_skew(fake_kernel *kernel, uint8_t moduleSkew) {
    if (moduleSkew >= sizeof(uint32_t))
        return EINVAL;
    memset(kernel, 0, sizeof(*kernel));
    kernel->moduleSkew = moduleSkew;
    kernel->memory = calloc(1, FK_SIZE);
    if (!kernel->memory)
        return ENOMEM;
    fk_build_source(TCNM_SOURCE_APP, kernel->appSource);
    fk_build_source(TCNM_SOURCE_OS, kernel->osSource);
    int status = fk_link_source(kernel, TCNM_SOURCE_APP);
    if (status == 0)
        status = fk_link_source(kernel, TCNM_SOURCE_OS);
    return status;
}

static int fk_initialize(fake_kernel *kernel) {
    return fk_initialize_with_module_skew(kernel, 0);
}

static void fk_destroy(fake_kernel *kernel) {
    free(kernel->memory);
    memset(kernel, 0, sizeof(*kernel));
}

static int fk_clone(const fake_kernel *source, fake_kernel *target) {
    if (!source || !source->memory || !target)
        return EINVAL;
    *target = *source;
    target->memory = malloc(FK_SIZE);
    if (!target->memory) {
        memset(target, 0, sizeof(*target));
        return ENOMEM;
    }
    memcpy(target->memory, source->memory, FK_SIZE);
    return 0;
}

static void fk_new_session(fake_kernel *kernel) {
    kernel->sessionCrashed = false;
    kernel->readCalls = 0;
    kernel->protectedCalls = 0;
    kernel->subwriteEvents = 0;
    kernel->reloadCalls = 0;
    kernel->forcedReloadStatus = 0;
    kernel->failReadCall = 0;
    kernel->failReadAddress = 0;
    kernel->failReadAddressVisit = 0;
    kernel->readAddressVisits = 0;
    kernel->failProtectedCall = 0;
    kernel->crashSubwrite = 0;
    kernel->failReloadBeforeLink = false;
    kernel->failReloadAfterLink = false;
    kernel->reloadAddsUnexpectedNode = false;
    kernel->invalidLiveTableObserved = false;
}

static int fk_read(void *context, uint64_t address, void *output, size_t size) {
    fake_kernel *kernel = context;
    if (kernel->sessionCrashed)
        return ECANCELED;
    kernel->readCalls++;
    if (kernel->failReadAddress && address == kernel->failReadAddress) {
        kernel->readAddressVisits++;
        if (kernel->failReadAddressVisit && kernel->readAddressVisits == kernel->failReadAddressVisit) {
            return EIO;
        }
    }
    if (kernel->failReadCall && kernel->readCalls == kernel->failReadCall) {
        return EIO;
    }
    const void *source = fk_const_pointer(kernel, address, size);
    if (!source)
        return EFAULT;
    memcpy(output, source, size);
    return 0;
}

static int fk_protected_replace(void *context,
                                uint64_t address,
                                const void *expected,
                                const void *desired,
                                size_t size) {
    fake_kernel *kernel = context;
    if (kernel->sessionCrashed)
        return ECANCELED;
    if (size != sizeof(uint32_t) || (address & (sizeof(uint32_t) - 1)) != 0) {
        return EINVAL;
    }
    uint8_t *target = fk_pointer(kernel, address, size);
    if (!target)
        return EFAULT;
    if (memcmp(target, expected, size) != 0)
        return EAGAIN;
    kernel->protectedCalls++;
    if (kernel->failProtectedCall && kernel->protectedCalls == kernel->failProtectedCall) {
        return EIO;
    }
    for (size_t offset = 0; offset < size; offset += sizeof(uint32_t)) {
        size_t chunk = size - offset;
        if (chunk > sizeof(uint32_t))
            chunk = sizeof(uint32_t);
        memcpy(target + offset, (const uint8_t *)desired + offset, chunk);
        kernel->subwriteEvents++;
        if (!fk_all_live_tables_valid(kernel)) {
            kernel->invalidLiveTableObserved = true;
        }
        if (!fk_required_hashes_are_live(kernel)) {
            kernel->missingRequiredHashObserved = true;
        }
        if (kernel->crashSubwrite && kernel->subwriteEvents == kernel->crashSubwrite) {
            kernel->sessionCrashed = true;
            return EINPROGRESS;
        }
    }
    return 0;
}

static int fk_reload(void *context, uint8_t sourceKind) {
    fake_kernel *kernel = context;
    if (kernel->sessionCrashed)
        return ECANCELED;
    kernel->reloadCalls++;
    if (kernel->forcedReloadStatus != 0) {
        return kernel->forcedReloadStatus;
    }
    if (kernel->failReloadBeforeLink)
        return EIO;
    int status = fk_link_source(kernel, sourceKind);
    if (status != 0)
        return status;
    if (kernel->reloadAddsUnexpectedNode) {
        status = fk_link_source(kernel, 3);
        if (status != 0)
            return status;
    }
    return kernel->failReloadAfterLink ? EINPROGRESS : 0;
}

static int fk_nonce(void *context, uint8_t nonce[4]) {
    fake_kernel *kernel = context;
    static const uint8_t fixedNonce[4] = {0x44, 0x55, 0x66, 0x77};
    kernel->nonceSerial++;
    memcpy(nonce, fixedNonce, sizeof(fixedNonce));
    return 0;
}

static int fk_controller_create(fake_kernel *kernel, bool loader, tcnc_controller **controllerOut) {
    static tcnc_signed_source sources[2];
    sources[0] = (tcnc_signed_source){
        .sourceKind = TCNM_SOURCE_APP,
        .bytes = kernel->appSource,
        .size = sizeof(kernel->appSource),
    };
    sources[1] = (tcnc_signed_source){
        .sourceKind = TCNM_SOURCE_OS,
        .bytes = kernel->osSource,
        .size = sizeof(kernel->osSource),
    };
    tcnc_config config = {
        .listSlot = FK_LIST_SLOT,
        .pointerMask = UINT64_C(0xffff000000000000),
        .pointerMinimum = UINT64_C(0xffff000000000000),
        .pageSize = 0x4000,
        .maxNodes = FK_MAX_NODES,
        .sharedType = 2,
        .signedSources = sources,
        .signedSourceCount = 2,
        .nonce = fk_nonce,
        .nonceContext = kernel,
    };
    tcnc_backend backend = {
        .read = fk_read,
        .protected_replace = fk_protected_replace,
        .reload_signed_source = loader ? fk_reload : NULL,
        .context = kernel,
    };
    return tcnc_controller_create(&config, &backend, controllerOut);
}

static int fk_recover_rebuilding_owner(fake_kernel *kernel) {
    for (uint32_t attempt = 0; attempt < 128; attempt++) {
        fk_new_session(kernel);
        tcnc_controller *controller = NULL;
        int status = fk_controller_create(kernel, true, &controller);
        if (status == 0) {
            status = tcnc_recover_to_fixed_point(controller);
        }
        tcnc_controller_destroy(controller);
        if (status == 0)
            return 0;
        if (status != EAGAIN && status != EINPROGRESS && status != EIO && status != ECANCELED) {
            return status;
        }
    }
    return ELOOP;
}

static bool fk_all_live_tables_valid(fake_kernel *kernel) {
    for (uint32_t index = 0; index < kernel->nodeCount; index++) {
        fake_node *node = fk_node(kernel, index);
        fake_module *module = fk_pointer(kernel, node->module, FK_MODULE_SIZE);
        if (!node || !module || tcnm_entries_validate(module->payload, module->capacity, FK_STRIDE) != 0) {
            return false;
        }
    }
    return true;
}

static bool fk_required_hashes_are_live(fake_kernel *kernel) {
    for (uint32_t required = 0; required < kernel->requiredHashCount; required++) {
        bool globallyFound = false;
        for (uint32_t index = 0; index < kernel->nodeCount; index++) {
            fake_node *node = fk_node(kernel, index);
            if (!node)
                return false;
            fake_module *module = fk_pointer(kernel, node->module, FK_MODULE_SIZE);
            if (!module || module->capacity != FK_CAPACITY)
                continue;
            bool found = false;
            if (tcnm_entries_query(module->payload,
                                   module->capacity,
                                   FK_STRIDE,
                                   kernel->requiredHashes[required],
                                   &found)
                    == 0
                && found) {
                globallyFound = true;
                break;
            }
        }
        if (!globallyFound)
            return false;
    }
    return true;
}

static int fk_capture_required_carrier_hashes(fake_kernel *kernel) {
    kernel->requiredHashCount = 0;
    kernel->missingRequiredHashObserved = false;
    memset(kernel->requiredHashes, 0, sizeof(kernel->requiredHashes));
    for (uint32_t index = 0; index < kernel->nodeCount; index++) {
        fake_node *node = fk_node(kernel, index);
        if (!node || node->type != 2)
            continue;
        fake_module *module = fk_pointer(kernel, node->module, FK_MODULE_SIZE);
        if (!module || module->capacity != FK_CAPACITY
            || tcnm_entries_validate(module->payload, module->capacity, FK_STRIDE) != 0) {
            return EPROTO;
        }
        for (uint32_t entry = 0; entry < module->capacity; entry++) {
            const uint8_t *hash = module->payload + (size_t)entry * FK_STRIDE;
            if (tcnm_hash_is_zero(hash))
                continue;
            bool duplicate = false;
            for (uint32_t required = 0; required < kernel->requiredHashCount; required++) {
                if (memcmp(kernel->requiredHashes[required], hash, TCNM_HASH_SIZE) == 0) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate)
                continue;
            if (kernel->requiredHashCount >= FK_CAPACITY) {
                return ENOSPC;
            }
            memcpy(kernel->requiredHashes[kernel->requiredHashCount++], hash, TCNM_HASH_SIZE);
        }
    }
    return kernel->requiredHashCount ? 0 : ENOENT;
}

static bool fk_full_snapshot_equal(const fake_kernel *left, const fake_kernel *right) {
    return left && right && left->nodeCount == right->nodeCount && memcmp(left->memory, right->memory, FK_SIZE) == 0;
}

static bool fk_matches_either_snapshot(const fake_kernel *observed,
                                       const fake_kernel *exactOriginal,
                                       const fake_kernel *exactReady) {
    return fk_full_snapshot_equal(observed, exactOriginal) || fk_full_snapshot_equal(observed, exactReady);
}

static int fk_prepare_unpaired_with_module_skew(fake_kernel *kernel, uint8_t moduleSkew) {
    int status = fk_initialize_with_module_skew(kernel, moduleSkew);
    if (status != 0)
        return status;
    tcnc_controller *bootstrap = NULL;
    status = fk_controller_create(kernel, false, &bootstrap);
    tcnm_entry initial = fk_entry(0xf0, 1);
    if (status == 0) {
        status = tcnc_bootstrap_append(bootstrap, &initial, 1);
    }
    tcnc_controller_destroy(bootstrap);
    return status;
}

static int fk_prepare_unpaired(fake_kernel *kernel) {
    return fk_prepare_unpaired_with_module_skew(kernel, 0);
}

static int fk_prepare_pair(fake_kernel *kernel) {
    int status = fk_prepare_unpaired(kernel);
    tcnc_controller *owner = NULL;
    if (status == 0)
        status = fk_controller_create(kernel, true, &owner);
    if (status == 0) {
        status = tcnc_prepare_runtime_pair(owner);
    }
    if (status == 0) {
        tcnm_entry addition = fk_entry(0xf1, 1);
        status = tcnc_append(owner, &addition, 1);
    }
    tcnc_controller_destroy(owner);
    return status;
}

static bool fk_recover_and_is_terminal(fake_kernel *kernel) {
    int recoveryStatus = fk_recover_rebuilding_owner(kernel);
    if (recoveryStatus != 0) {
        fprintf(stderr, "terminal recovery status=%d\n", recoveryStatus);
        return false;
    }
    return fk_linked_nodes_are_terminal(kernel) && fk_all_live_tables_valid(kernel);
}

static void test_bootstrap_reboot_adopts_then_prepares_pair(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry initial = fk_entry(0xf0, 2);

    tcnc_controller *bootstrap = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &bootstrap));
    EXPECT_EQ(0, tcnc_bootstrap_append(bootstrap, &initial, 1));
    EXPECT_EQ(1, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));
    EXPECT_TRUE(fk_all_live_tables_valid(&kernel));
    tcnc_controller_destroy(bootstrap);

    /* Kernel memory persists while the PID1 owner/controller is rebuilt. */
    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(0, kernel.reloadCalls);
    EXPECT_EQ(1, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));

    tcnm_entry runtime = fk_entry(0xf1, 3);
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(owner, &runtime, 1));
    EXPECT_EQ(2, kernel.reloadCalls);
    EXPECT_EQ(2, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));

    /* Replaying the request is idempotent once promotion has completed. */
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(owner, &runtime, 1));
    EXPECT_EQ(0, kernel.reloadCalls);
    EXPECT_EQ(2, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));
    bool found = false;
    EXPECT_EQ(0, tcnc_query(owner, initial.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(0, tcnc_query(owner, runtime.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_TRUE(fk_all_live_tables_valid(&kernel));

    uint8_t zero[TCNM_HASH_SIZE] = {0};
    uint64_t reads = kernel.readCalls;
    EXPECT_EQ(EINVAL, tcnc_query(owner, zero, &found));
    EXPECT_EQ(reads, kernel.readCalls);
    tcnc_controller_destroy(owner);
    fk_destroy(&kernel);
}

static void test_bootstrap_singleton_is_ready_without_loader(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry initial = fk_entry(0xe8, 1);
    tcnm_entry runtime = fk_entry(0xe9, 1);

    tcnc_controller *bootstrap = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &bootstrap));
    EXPECT_EQ(0, tcnc_bootstrap_append(bootstrap, &initial, 1));
    tcnc_controller_destroy(bootstrap);

    fake_kernel exactSingleton = {0};
    EXPECT_EQ(0, fk_clone(&kernel, &exactSingleton));
    fk_new_session(&kernel);
    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &owner));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(0, kernel.reloadCalls);

    EXPECT_EQ(1, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));
    bool found = false;
    EXPECT_EQ(0, tcnc_query(owner, initial.hash, &found));
    EXPECT_TRUE(found);

    uint64_t protectedCalls = kernel.protectedCalls;
    EXPECT_EQ(ENOTSUP, tcnc_append(owner, &runtime, 1));
    tcnc_controller_destroy(owner);
    EXPECT_EQ(protectedCalls, kernel.protectedCalls);
    EXPECT_TRUE(fk_full_snapshot_equal(&kernel, &exactSingleton));
    EXPECT_TRUE(fk_all_live_tables_valid(&kernel));

    /* Rebuilding the owner over persistent kernel memory remains idempotent. */
    fk_new_session(&kernel);
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &owner));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(1, fk_type_count(&kernel, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&kernel));
    EXPECT_EQ(0, tcnc_query(owner, initial.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(0, tcnc_query(owner, runtime.hash, &found));
    EXPECT_TRUE(!found);
    tcnc_controller_destroy(owner);

    fk_destroy(&exactSingleton);
    fk_destroy(&kernel);
}

static void test_bootstrap_recovery_does_not_call_unavailable_loader(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry initial = fk_entry(0xea, 1);
    tcnm_entry runtime = fk_entry(0xeb, 1);

    tcnc_controller *bootstrap = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &bootstrap));
    EXPECT_EQ(0, tcnc_bootstrap_append(bootstrap, &initial, 1));
    tcnc_controller_destroy(bootstrap);
    fake_kernel exactSingleton = {0};
    EXPECT_EQ(0, fk_clone(&kernel, &exactSingleton));

    fk_new_session(&kernel);
    kernel.forcedReloadStatus = EAGAIN;
    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(0, kernel.reloadCalls);

    bool found = false;
    EXPECT_EQ(0, tcnc_query(owner, initial.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(EAGAIN, tcnc_append(owner, &runtime, 1));
    EXPECT_EQ(1, kernel.reloadCalls);
    EXPECT_EQ(0, kernel.protectedCalls);
    EXPECT_TRUE(fk_full_snapshot_equal(&kernel, &exactSingleton));
    EXPECT_EQ(EAGAIN, tcnc_prepare_runtime_pair(owner));
    EXPECT_EQ(2, kernel.reloadCalls);
    EXPECT_EQ(0, tcnc_query(owner, runtime.hash, &found));
    EXPECT_TRUE(!found);
    tcnc_controller_destroy(owner);

    fk_destroy(&exactSingleton);
    fk_destroy(&kernel);
}

static void test_ready_clone_without_source_uses_loader_policy(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    fake_node *app = fk_node(&kernel, 0);
    fake_module *module = fk_pointer(&kernel, app->module, FK_MODULE_SIZE);
    EXPECT_TRUE(app != NULL);
    EXPECT_TRUE(module != NULL);

    tcnm_marker_fields fields = {
        .nonce = {0x41, 0x42, 0x43, 0x44},
        .peerModuleLow32 = 0,
        .phase = TCNM_MARKER_PHASE_READY,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = true,
    };
    tcnm_marker_binding binding = {
        .selfModuleLow32 = (uint32_t)app->module,
        .peerModuleLow32 = 0,
        .selfModuleSize = app->moduleSize,
        .peerModuleSize = app->moduleSize,
        .selfVersion = module->version,
        .peerVersion = module->version,
        .selfCapacity = module->capacity,
        .peerCapacity = module->capacity,
        .payload = module->payload,
        .payloadSize = sizeof(module->payload),
    };
    EXPECT_EQ(0, tcnm_marker_encode(&fields, &binding, module->marker));
    app->type = 2;

    fk_new_session(&kernel);
    kernel.forcedReloadStatus = EAGAIN;
    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
    EXPECT_EQ(EAGAIN, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(1, kernel.reloadCalls);
    EXPECT_EQ(0, kernel.protectedCalls);
    tcnc_controller_destroy(owner);
    fk_destroy(&kernel);
}

static void test_bootstrap_uses_empty_carrier_capacity(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    fake_module *canonical = (fake_module *)kernel.appSource;
    fake_node *appNode = fk_node(&kernel, 0);
    fake_module *live = fk_pointer(&kernel, appNode->module, FK_MODULE_SIZE);
    memset(canonical->payload, 0, sizeof(canonical->payload));
    for (uint32_t index = 0; index < FK_CAPACITY; index++) {
        tcnm_entry signedEntry = fk_entry((uint8_t)(0x20 + index), 1);
        memcpy(canonical->payload + (size_t)index * FK_STRIDE, &signedEntry, sizeof(signedEntry));
    }
    memcpy(live, canonical, sizeof(*live));

    tcnm_entry additions[2] = {
        fk_entry(0xe0, 1),
        fk_entry(0xe1, 1),
    };
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, additions, 2));
    tcnm_entry decoded[FK_CAPACITY] = {0};
    uint32_t used = 0;
    EXPECT_EQ(0, tcnm_entries_decode(live->payload, FK_CAPACITY, FK_STRIDE, decoded, FK_CAPACITY, &used));
    EXPECT_EQ(2, used);
    EXPECT_TRUE(memcmp(decoded[0].hash, additions[0].hash, TCNM_HASH_SIZE) == 0);
    EXPECT_TRUE(memcmp(decoded[1].hash, additions[1].hash, TCNM_HASH_SIZE) == 0);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_scans_follow_forward_links_only(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    fake_node *head = fk_node(&kernel, 0);
    fake_node *tail = fk_node(&kernel, 1);
    head->previous = UINT64_C(0x1111222233334444);
    tail->previous = UINT64_C(0x5555666677778888);

    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry source = fk_entry(TCNM_SOURCE_APP, 1);
    bool found = false;
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_query(controller, source.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(0, kernel.protectedCalls);
    EXPECT_EQ(UINT64_C(0x1111222233334444), head->previous);
    EXPECT_EQ(UINT64_C(0x5555666677778888), tail->previous);

    tail->next = FK_NODE_START;
    EXPECT_EQ(ELOOP, tcnc_query(controller, source.hash, &found));
    tail->next = FK_BASE + 3;
    EXPECT_EQ(EFAULT, tcnc_query(controller, source.hash, &found));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_bootstrap_quarantines_unmanaged_nodes_and_repairs_chain(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    uint32_t firstForeignIndex = 0;
    uint32_t secondForeignIndex = 0;
    EXPECT_EQ(0, fk_insert_unmanaged_shared_after(&kernel, 0, 3, &firstForeignIndex));
    EXPECT_EQ(0, fk_insert_unmanaged_shared_after(&kernel, firstForeignIndex, 1, &secondForeignIndex));

    fake_node *head = fk_node(&kernel, 0);
    fake_node *firstForeign = fk_node(&kernel, firstForeignIndex);
    fake_node *secondForeign = fk_node(&kernel, secondForeignIndex);
    fake_node *tail = fk_node(&kernel, 1);
    head->previous = UINT64_C(0x1111222233334444);
    firstForeign->previous = UINT64_C(0x5555666677778888);
    secondForeign->previous = 0;
    EXPECT_TRUE(!fk_previous_links_match_forward_chain(&kernel));

    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xe2, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_EQ(3, firstForeign->type);
    EXPECT_EQ(3, secondForeign->type);
    EXPECT_EQ(0, head->previous);
    EXPECT_EQ(FK_NODE_START, firstForeign->previous);
    EXPECT_EQ(FK_NODE_START + (uint64_t)firstForeignIndex * FK_NODE_STEP, secondForeign->previous);
    EXPECT_EQ(FK_NODE_START + (uint64_t)secondForeignIndex * FK_NODE_STEP, tail->previous);
    EXPECT_TRUE(fk_previous_links_match_forward_chain(&kernel));
    bool found = false;
    EXPECT_EQ(0, tcnc_query(controller, entry.hash, &found));
    EXPECT_TRUE(found);
    tcnc_controller_destroy(controller);

    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(controller));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_bootstrap_preserves_managed_intermediate_carrier(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry initial = fk_entry(0xe3, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &initial, 1));
    tcnc_controller_destroy(controller);

    fake_node *carrier = fk_node(&kernel, 0);
    fake_module *module = fk_pointer(&kernel, carrier->module, FK_MODULE_SIZE);
    module->marker[TCNM_MARKER_PHASE_OFFSET] = TCNM_MARKER_PHASE_PREPARED_FILL;
    EXPECT_EQ(2, carrier->type);

    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry addition = fk_entry(0xe4, 1);
    EXPECT_EQ(EALREADY, tcnc_bootstrap_append(controller, &addition, 1));
    EXPECT_EQ(2, carrier->type);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_unmanaged_quarantine_failure_is_retryable(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    uint32_t foreignIndex = 0;
    EXPECT_EQ(0, fk_insert_unmanaged_shared_after(&kernel, 0, 2, &foreignIndex));
    fake_node *foreign = fk_node(&kernel, foreignIndex);

    fk_new_session(&kernel);
    kernel.failProtectedCall = 1;
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xe5, 1);
    EXPECT_EQ(EIO, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_EQ(2, foreign->type);
    tcnc_controller_destroy(controller);

    fk_new_session(&kernel);
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_EQ(3, foreign->type);
    EXPECT_TRUE(fk_previous_links_match_forward_chain(&kernel));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_previous_link_repair_failures_are_best_effort(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    fake_node *head = fk_node(&kernel, 0);
    fake_node *tail = fk_node(&kernel, 1);
    head->previous = UINT64_C(0x1111222233334444);
    tail->previous = 0;

    fk_new_session(&kernel);
    kernel.failProtectedCall = 1;
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xe6, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_TRUE(!fk_previous_links_match_forward_chain(&kernel));
    EXPECT_EQ(FK_NODE_START, tail->previous);
    tcnc_controller_destroy(controller);

    fk_new_session(&kernel);
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_EQ(EALREADY, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_TRUE(fk_previous_links_match_forward_chain(&kernel));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_previous_link_readback_failure_is_best_effort(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    fake_node *head = fk_node(&kernel, 0);
    head->previous = UINT64_C(0x1111222233334444);

    fk_new_session(&kernel);
    kernel.failReadAddress = FK_NODE_START + 8;
    kernel.failReadAddressVisit = 2;
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xe7, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_TRUE(kernel.readAddressVisits >= 2);
    EXPECT_TRUE(fk_previous_links_match_forward_chain(&kernel));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_bootstrap_ignores_oversized_foreign_source(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    uint32_t foreignIndex = 0;
    EXPECT_EQ(0, fk_insert_oversized_foreign_source_after_head(&kernel, &foreignIndex));
    fake_node foreignBefore = *fk_node(&kernel, foreignIndex);

    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xe8, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    fake_node *foreign = fk_node(&kernel, foreignIndex);
    EXPECT_EQ(TCNM_SOURCE_APP, foreign->type);
    EXPECT_EQ(foreignBefore.moduleSize, foreign->moduleSize);
    EXPECT_EQ(foreignBefore.module, foreign->module);
    bool found = false;
    EXPECT_EQ(0, tcnc_query(controller, entry.hash, &found));
    EXPECT_TRUE(found);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_query_read_error_is_terminal(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_prepare_pair(&kernel));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    tcnm_entry query = fk_entry(0xf0, 1);
    bool found = false;
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_query(controller, query.hash, &found));
    EXPECT_TRUE(found);
    uint64_t completeReadCount = kernel.readCalls;
    EXPECT_TRUE(completeReadCount > 2);
    fk_new_session(&kernel);
    kernel.failReadCall = completeReadCount;
    EXPECT_EQ(EIO, tcnc_query(controller, query.hash, &found));
    EXPECT_TRUE(!found);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_copy_entries_deduplicates_carrier_pair(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_prepare_pair(&kernel));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));

    tcnm_entry *entries = NULL;
    uint32_t entryCount = 0;
    EXPECT_EQ(0, tcnc_copy_entries(controller, &entries, &entryCount));
    EXPECT_EQ(2, entryCount);
    if (entryCount == 2) {
        EXPECT_EQ(0xf0, entries[0].hash[0]);
        EXPECT_EQ(0xf1, entries[1].hash[0]);
    }
    free(entries);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_query_snapshot_preserves_payload_error_order(void) {
    fake_kernel foundBeforeInvalid = {0};
    EXPECT_EQ(0, fk_prepare_pair(&foundBeforeInvalid));
    fake_node *laterNode = fk_node(&foundBeforeInvalid, 1);
    fake_module *laterModule = fk_pointer(&foundBeforeInvalid, laterNode->module, FK_MODULE_SIZE);
    EXPECT_TRUE(laterNode != NULL);
    EXPECT_TRUE(laterModule != NULL);
    laterModule->payload[0] = 0xff;

    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&foundBeforeInvalid, true, &controller));
    tcnm_entry carrierEntry = fk_entry(0xf0, 1);
    bool found = false;
    EXPECT_EQ(0, tcnc_query(controller, carrierEntry.hash, &found));
    EXPECT_TRUE(found);
    tcnm_entry missing = fk_entry(0x70, 1);
    EXPECT_EQ(EPROTO, tcnc_query(controller, missing.hash, &found));
    EXPECT_TRUE(!found);
    tcnc_controller_destroy(controller);
    fk_destroy(&foundBeforeInvalid);

    fake_kernel invalidBeforeFound = {0};
    EXPECT_EQ(0, fk_prepare_pair(&invalidBeforeFound));
    fake_node *firstNode = fk_node(&invalidBeforeFound, 0);
    fake_module *firstModule = fk_pointer(&invalidBeforeFound, firstNode->module, FK_MODULE_SIZE);
    EXPECT_TRUE(firstNode != NULL);
    EXPECT_TRUE(firstModule != NULL);
    firstModule->payload[0] = 0xff;

    EXPECT_EQ(0, fk_controller_create(&invalidBeforeFound, true, &controller));
    tcnm_entry laterSource = fk_entry(TCNM_SOURCE_OS, 1);
    EXPECT_EQ(EPROTO, tcnc_query(controller, laterSource.hash, &found));
    EXPECT_TRUE(!found);
    tcnc_controller_destroy(controller);
    fk_destroy(&invalidBeforeFound);
}

static void test_batch_missing_query_scans_once(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_prepare_pair(&kernel));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));

    tcnm_entry present = fk_entry(0xf0, 1);
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(controller, &present, 1));
    uint64_t singleEntryReads = kernel.readCalls;
    EXPECT_TRUE(singleEntryReads > 0);
    EXPECT_EQ(0, kernel.protectedCalls);

    tcnm_entry presentBatch[] = {
        fk_entry(0xf0, 1),
        fk_entry(0xf1, 1),
        fk_entry(0xf0, 1),
        fk_entry(0xf1, 1),
    };
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(controller, presentBatch, (uint32_t)(sizeof(presentBatch) / sizeof(presentBatch[0]))));
    EXPECT_EQ(singleEntryReads, kernel.readCalls);
    EXPECT_EQ(0, kernel.protectedCalls);

    fk_new_session(&kernel);
    kernel.failReadCall = singleEntryReads;
    EXPECT_EQ(EIO, tcnc_append(controller, presentBatch, (uint32_t)(sizeof(presentBatch) / sizeof(presentBatch[0]))));
    EXPECT_EQ(0, kernel.protectedCalls);

    tcnm_entry mixedBatch[] = {
        fk_entry(0xf0, 1),
        fk_entry(0x80, 1),
        fk_entry(0xf1, 1),
        fk_entry(0x81, 1),
        fk_entry(0x80, 1),
    };
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(controller, mixedBatch, (uint32_t)(sizeof(mixedBatch) / sizeof(mixedBatch[0]))));
    EXPECT_TRUE(kernel.protectedCalls > 0);
    bool found = false;
    EXPECT_EQ(0, tcnc_query(controller, mixedBatch[1].hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(0, tcnc_query(controller, mixedBatch[3].hash, &found));
    EXPECT_TRUE(found);

    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_append_is_uuid_free_idempotent_and_batches(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_prepare_pair(&kernel));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    tcnm_entry entry = fk_entry(0xf6, 1);
    EXPECT_EQ(0, tcnc_append(controller, &entry, 1));
    /* There is deliberately no caller/logical UUID in this API. */
    EXPECT_EQ(0, tcnc_append(controller, &entry, 1));
    bool found = false;
    EXPECT_EQ(0, tcnc_query(controller, entry.hash, &found));
    EXPECT_TRUE(found);

    tcnm_entry batch[FK_CAPACITY - 3] = {0};
    for (uint32_t index = 0; index < FK_CAPACITY - 3; index++) {
        batch[index] = fk_entry((uint8_t)(0x80 + index), 1);
    }
    fk_new_session(&kernel);
    EXPECT_EQ(0, tcnc_append(controller, batch, FK_CAPACITY - 3));
    EXPECT_TRUE(kernel.protectedCalls > 0);
    EXPECT_EQ(0, kernel.reloadCalls);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

typedef struct {
    pthread_mutex_t *lock;
    tcnc_controller *controller;
    tcnm_entry entry;
    int status;
} owner_call;

static void *owner_append_thread(void *context) {
    owner_call *call = context;
    pthread_mutex_lock(call->lock);
    call->status = tcnc_append(call->controller, &call->entry, 1);
    pthread_mutex_unlock(call->lock);
    return NULL;
}

static void test_two_clients_are_owner_serialized(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnc_controller *bootstrap = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &bootstrap));
    tcnm_entry initial = fk_entry(0xf0, 1);
    EXPECT_EQ(0, tcnc_bootstrap_append(bootstrap, &initial, 1));
    tcnc_controller_destroy(bootstrap);

    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(owner));
    EXPECT_EQ(0, tcnc_prepare_runtime_pair(owner));
    pthread_mutex_t ownerLock = PTHREAD_MUTEX_INITIALIZER;
    owner_call first = {
        .lock = &ownerLock,
        .controller = owner,
        .entry = fk_entry(0xf2, 1),
    };
    owner_call second = first;
    second.entry = fk_entry(0xf3, 1);
    pthread_t threads[2] = {0};
    EXPECT_EQ(0, pthread_create(&threads[0], NULL, owner_append_thread, &first));
    EXPECT_EQ(0, pthread_create(&threads[1], NULL, owner_append_thread, &second));
    EXPECT_EQ(0, pthread_join(threads[0], NULL));
    EXPECT_EQ(0, pthread_join(threads[1], NULL));
    EXPECT_EQ(0, first.status);
    EXPECT_EQ(0, second.status);
    bool found = false;
    EXPECT_EQ(0, tcnc_query(owner, first.entry.hash, &found));
    EXPECT_TRUE(found);
    EXPECT_EQ(0, tcnc_query(owner, second.entry.hash, &found));
    EXPECT_TRUE(found);
    tcnc_controller_destroy(owner);
    fk_destroy(&kernel);
}

static void test_runtime_subwrite_crash_recovers(void) {
    fake_kernel base = {0};
    EXPECT_EQ(0, fk_prepare_pair(&base));
    EXPECT_EQ(0, fk_capture_required_carrier_hashes(&base));
    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *owner = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, true, &owner));
    tcnm_entry additions[2] = {
        fk_entry(0x80, 1),
        fk_entry(0xf5, 1),
    };
    EXPECT_EQ(0, tcnc_append(owner, additions, 2));
    tcnc_controller_destroy(owner);
    uint64_t protectedCalls = baseline.protectedCalls;
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(protectedCalls > 4);
    EXPECT_TRUE(subwrites >= protectedCalls);
    EXPECT_TRUE(!baseline.missingRequiredHashObserved);
    EXPECT_TRUE(fk_recover_and_is_terminal(&baseline));
    EXPECT_TRUE(!baseline.missingRequiredHashObserved);

    for (uint64_t failure = 1; failure <= protectedCalls; failure++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failProtectedCall = failure;
        owner = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
        (void)tcnc_append(owner, additions, 2);
        tcnc_controller_destroy(owner);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(!kernel.missingRequiredHashObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr, "runtime protected failure %llu did not recover\n", (unsigned long long)failure);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(!kernel.missingRequiredHashObserved);
        bool exactSnapshot = fk_matches_either_snapshot(&kernel, &base, &baseline);
        if (!exactSnapshot) {
            fprintf(stderr,
                    "runtime protected failure %llu" " reached a non-endpoint snapshot\n",
                    (unsigned long long)failure);
        }
        EXPECT_TRUE(exactSnapshot);
        fk_destroy(&kernel);
    }
    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        owner = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &owner));
        (void)tcnc_append(owner, additions, 2);
        tcnc_controller_destroy(owner);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(!kernel.missingRequiredHashObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr, "runtime subwrite crash %llu did not recover\n", (unsigned long long)crash);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(!kernel.missingRequiredHashObserved);
        bool exactSnapshot = fk_matches_either_snapshot(&kernel, &base, &baseline);
        if (!exactSnapshot) {
            fprintf(stderr,
                    "runtime subwrite crash %llu" " reached a non-endpoint snapshot\n",
                    (unsigned long long)crash);
        }
        EXPECT_TRUE(exactSnapshot);
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
}

static void run_bootstrap_all_write_faults_recover(uint8_t moduleSkew) {
    fake_kernel base = {0};
    EXPECT_EQ(0, fk_initialize_with_module_skew(&base, moduleSkew));
    tcnm_entry additions[2] = {
        fk_entry(0xf0, 2),
        fk_entry(0xf1, 2),
    };

    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, additions, 2));
    tcnc_controller_destroy(controller);
    uint64_t protectedCalls = baseline.protectedCalls;
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(fk_recover_and_is_terminal(&baseline));

    for (uint64_t failure = 1; failure <= protectedCalls; failure++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failProtectedCall = failure;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
        (void)tcnc_bootstrap_append(controller, additions, 2);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(fk_recover_and_is_terminal(&kernel));
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &base, &baseline));
        fk_destroy(&kernel);
    }
    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
        (void)tcnc_bootstrap_append(controller, additions, 2);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(fk_recover_and_is_terminal(&kernel));
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &base, &baseline));
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
}

static void test_bootstrap_all_write_faults_recover(void) {
    for (uint8_t moduleSkew = 0; moduleSkew < sizeof(uint32_t); moduleSkew++) {
        run_bootstrap_all_write_faults_recover(moduleSkew);
    }
}

static void run_expansion_all_write_and_reload_faults_recover(uint8_t moduleSkew) {
    fake_kernel base = {0};
    EXPECT_EQ(0, fk_prepare_unpaired_with_module_skew(&base, moduleSkew));
    /*
	 * launchd restores the source consumed by Task07 before it asks the
	 * owner to turn that exact source into the bootstrap peer.
	 */
    EXPECT_EQ(0, fk_reload(&base, TCNM_SOURCE_APP));
    fk_new_session(&base);

    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, true, &controller));
    uint32_t carriersBefore = fk_type_count(&baseline, 2);
    EXPECT_EQ(0, tcnc_prepare_runtime_pair(controller));
    EXPECT_EQ(carriersBefore + 1, fk_type_count(&baseline, 2));
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&baseline));
    tcnc_controller_destroy(controller);
    /*
	 * This is the complete fixed point, including the normalizer's final
	 * READY-to-pair marker rebind. The fault bounds below therefore include
	 * every protected word used to publish that reciprocal binding.
	 */
    uint64_t protectedCalls = baseline.protectedCalls;
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(protectedCalls > 0);
    EXPECT_TRUE(subwrites >= protectedCalls);
    EXPECT_TRUE(fk_recover_and_is_terminal(&baseline));

    for (uint64_t failure = 1; failure <= protectedCalls; failure++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failProtectedCall = failure;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_prepare_runtime_pair(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr,
                    "expansion skew=%u protected failure=%llu" " did not recover\n",
                    moduleSkew,
                    (unsigned long long)failure);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &base, &baseline));
        fk_destroy(&kernel);
    }
    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_prepare_runtime_pair(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr,
                    "expansion skew=%u subwrite crash=%llu" " did not recover\n",
                    moduleSkew,
                    (unsigned long long)crash);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &base, &baseline));
        fk_destroy(&kernel);
    }
    for (uint32_t afterLink = 0; afterLink <= 1; afterLink++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failReloadBeforeLink = afterLink == 0;
        kernel.failReloadAfterLink = afterLink == 1;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        int reloadStatus = tcnc_prepare_runtime_pair(controller);
        if (afterLink == 0)
            EXPECT_TRUE(reloadStatus != 0);
        tcnc_controller_destroy(controller);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr, "expansion skew=%u reload after_link=%u" " did not recover\n", moduleSkew, afterLink);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &base, &baseline));
        fk_destroy(&kernel);
    }
    {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.reloadAddsUnexpectedNode = true;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        EXPECT_EQ(EPROTO, tcnc_prepare_runtime_pair(controller));
        tcnc_controller_destroy(controller);
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
}

static void test_expansion_all_write_and_reload_faults_recover(void) {
    for (uint8_t moduleSkew = 0; moduleSkew < sizeof(uint32_t); moduleSkew++) {
        run_expansion_all_write_and_reload_faults_recover(moduleSkew);
    }
}

static void test_unpaired_requires_clone_peer_zero_recovers(void) {
    fake_kernel base = {0};
    EXPECT_EQ(0, fk_initialize(&base));
    tcnm_entry addition = fk_entry(0xfa, 1);
    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, true, &controller));
    EXPECT_EQ(0, tcnc_append(controller, &addition, 1));
    tcnc_controller_destroy(controller);
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(subwrites > 0);
    EXPECT_TRUE(fk_linked_nodes_are_terminal(&baseline));

    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_append(controller, &addition, 1);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr,
                    "peer-zero subwrite crash %llu did not recover" " nodes=%u\n",
                    (unsigned long long)crash,
                    kernel.nodeCount);
            for (uint32_t index = 0; index < kernel.nodeCount; index++) {
                fake_node *node = fk_node(&kernel, index);
                fake_module *module = fk_pointer(&kernel, node->module, FK_MODULE_SIZE);
                fprintf(stderr,
                        " node%u type=%u phase=%u ver=%u peer=%08x\n",
                        index,
                        node->type,
                        module->marker[9],
                        module->marker[8],
                        *(uint32_t *)&module->marker[4]);
            }
        }
        EXPECT_TRUE(terminal);
        uint32_t carriers = fk_type_count(&kernel, 2);
        EXPECT_TRUE(carriers == 0 || carriers == 2);
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
}

static void test_version_zero_source_is_not_a_carrier(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    for (uint32_t index = 0; index < kernel.nodeCount; index++) {
        fake_node *node = fk_node(&kernel, index);
        fake_module *module = fk_pointer(&kernel, node->module, FK_MODULE_SIZE);
        module->version = 0;
        module->capacity = 1;
        memset(module->payload, 0, sizeof(module->payload));
    }
    fake_module *appSource = (fake_module *)kernel.appSource;
    fake_module *osSource = (fake_module *)kernel.osSource;
    appSource->version = 0;
    appSource->capacity = 1;
    memset(appSource->payload, 0, sizeof(appSource->payload));
    osSource->version = 0;
    osSource->capacity = 1;
    memset(osSource->payload, 0, sizeof(osSource->payload));

    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    tcnm_entry entry = fk_entry(0xf0, 1);
    fk_new_session(&kernel);
    EXPECT_EQ(ENOSPC, tcnc_bootstrap_append(controller, &entry, 1));
    EXPECT_EQ(0, kernel.protectedCalls);
    tcnc_controller_destroy(controller);

    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    fk_new_session(&kernel);
    EXPECT_EQ(ENOENT, tcnc_append(controller, &entry, 1));
    EXPECT_EQ(0, kernel.protectedCalls);
    EXPECT_EQ(0, kernel.nodeCount - 2);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_config_resource_ceiling(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    static tcnc_signed_source sources[2];
    sources[0] = (tcnc_signed_source){
        .sourceKind = TCNM_SOURCE_APP,
        .bytes = kernel.appSource,
        .size = sizeof(kernel.appSource),
    };
    sources[1] = (tcnc_signed_source){
        .sourceKind = TCNM_SOURCE_OS,
        .bytes = kernel.osSource,
        .size = sizeof(kernel.osSource),
    };
    tcnc_config config = {
        .listSlot = FK_LIST_SLOT,
        .pointerMask = UINT64_C(0xffff000000000000),
        .pointerMinimum = UINT64_C(0xffff000000000000),
        .pageSize = 0x4000,
        .maxNodes = FK_MAX_NODES + 4096,
        .sharedType = 2,
        .signedSources = sources,
        .signedSourceCount = 2,
        .nonce = fk_nonce,
        .nonceContext = &kernel,
    };
    tcnc_backend backend = {
        .read = fk_read,
        .protected_replace = fk_protected_replace,
        .reload_signed_source = fk_reload,
        .context = &kernel,
    };
    tcnc_controller *controller = NULL;
    EXPECT_EQ(EINVAL, tcnc_controller_create(&config, &backend, &controller));
    EXPECT_TRUE(controller == NULL);
    fk_destroy(&kernel);
}

static void test_recovery_itself_all_write_faults_converges(void) {
    fake_kernel exactOriginal = {0};
    EXPECT_EQ(0, fk_prepare_pair(&exactOriginal));
    EXPECT_EQ(0, fk_capture_required_carrier_hashes(&exactOriginal));
    tcnm_entry addition = fk_entry(0xf5, 1);

    fake_kernel exactReady = {0};
    EXPECT_EQ(0, fk_clone(&exactOriginal, &exactReady));
    fk_new_session(&exactReady);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&exactReady, true, &controller));
    EXPECT_EQ(0, tcnc_append(controller, &addition, 1));
    tcnc_controller_destroy(controller);
    EXPECT_TRUE(fk_matches_either_snapshot(&exactReady, &exactOriginal, &exactReady));

    fake_kernel base = {0};
    EXPECT_EQ(0, fk_clone(&exactOriginal, &base));
    fk_new_session(&base);
    base.crashSubwrite = 12;
    controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&base, true, &controller));
    (void)tcnc_append(controller, &addition, 1);
    tcnc_controller_destroy(controller);
    EXPECT_TRUE(!base.invalidLiveTableObserved);

    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    EXPECT_EQ(0, fk_controller_create(&baseline, true, &controller));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(controller));
    tcnc_controller_destroy(controller);
    uint64_t protectedCalls = baseline.protectedCalls;
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(fk_matches_either_snapshot(&baseline, &exactOriginal, &exactReady));

    for (uint64_t failure = 1; failure <= protectedCalls; failure++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failProtectedCall = failure;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_recover_to_fixed_point(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(fk_recover_and_is_terminal(&kernel));
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &exactOriginal, &exactReady));
        fk_destroy(&kernel);
    }
    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_recover_to_fixed_point(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        EXPECT_TRUE(fk_recover_and_is_terminal(&kernel));
        EXPECT_TRUE(fk_matches_either_snapshot(&kernel, &exactOriginal, &exactReady));
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
    fk_destroy(&exactReady);
    fk_destroy(&exactOriginal);
}

static int fk_prepare_adversarial_canonical_restore(fake_kernel *kernel, uint8_t moduleSkew) {
    int status = fk_initialize_with_module_skew(kernel, moduleSkew);
    if (status != 0)
        return status;
    fake_node *app = fk_node(kernel, 0);
    fake_module *module = fk_pointer(kernel, app->module, FK_MODULE_SIZE);
    fake_module *canonical = (fake_module *)kernel->appSource;
    if (!app || !module)
        return EFAULT;

    canonical->marker[TCNM_MARKER_VERSION_OFFSET] = UINT8_C(0x80);
    canonical->marker[TCNM_MARKER_PHASE_OFFSET] = TCNM_MARKER_PHASE_PREPARED_SOURCE;
    canonical->marker[TCNM_MARKER_SOURCE_OFFSET] = TCNM_SOURCE_OS;
    canonical->marker[TCNM_MARKER_FLAGS_OFFSET] = 0;

    app->type = 2;
    tcnm_marker_fields fields = {
        .nonce = {0x11, 0x22, 0x33, 0x44},
        .phase = TCNM_MARKER_PHASE_PREPARED_SOURCE,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = false,
    };
    tcnm_marker_binding binding = {
        .selfModuleLow32 = (uint32_t)app->module,
        .peerModuleLow32 = 0,
        .selfModuleSize = FK_MODULE_SIZE,
        .peerModuleSize = FK_MODULE_SIZE,
        .selfVersion = module->version,
        .peerVersion = module->version,
        .selfCapacity = module->capacity,
        .peerCapacity = module->capacity,
        .payload = module->payload,
        .payloadSize = sizeof(module->payload),
    };
    return tcnm_marker_encode(&fields, &binding, module->marker);
}

static void run_canonical_restore_adversarial_uuid(uint8_t moduleSkew) {
    fake_kernel base = {0};
    EXPECT_EQ(0, fk_prepare_adversarial_canonical_restore(&base, moduleSkew));
    fake_node *preparedNode = fk_node(&base, 0);
    fake_module *preparedModule = fk_pointer(&base, preparedNode->module, FK_MODULE_SIZE);
    EXPECT_EQ(2, preparedNode->type);
    EXPECT_EQ(TCNM_MARKER_VERSION, preparedModule->marker[TCNM_MARKER_VERSION_OFFSET]);
    EXPECT_EQ(TCNM_MARKER_PHASE_PREPARED_SOURCE, preparedModule->marker[TCNM_MARKER_PHASE_OFFSET]);

    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&base, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, true, &controller));
    EXPECT_EQ(0, tcnc_recover_to_fixed_point(controller));
    tcnc_controller_destroy(controller);
    uint64_t protectedCalls = baseline.protectedCalls;
    uint64_t subwrites = baseline.subwriteEvents;
    EXPECT_TRUE(protectedCalls > 5);
    EXPECT_TRUE(subwrites >= protectedCalls);
    EXPECT_TRUE(fk_recover_and_is_terminal(&baseline));
    fake_node *restoredApp = fk_node(&baseline, 0);
    fake_module *restoredModule = fk_pointer(&baseline, restoredApp->module, FK_MODULE_SIZE);
    EXPECT_EQ(TCNM_SOURCE_APP, restoredApp->type);
    EXPECT_TRUE(memcmp(restoredModule, baseline.appSource, FK_MODULE_SIZE) == 0);

    for (uint64_t failure = 1; failure <= protectedCalls; failure++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.failProtectedCall = failure;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_recover_to_fixed_point(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr,
                    "canonical restore skew=%u protected failure=%llu" " did not recover\n",
                    moduleSkew,
                    (unsigned long long)failure);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(fk_full_snapshot_equal(&kernel, &baseline));
        fk_destroy(&kernel);
    }
    for (uint64_t crash = 1; crash <= subwrites; crash++) {
        fake_kernel kernel = {0};
        EXPECT_EQ(0, fk_clone(&base, &kernel));
        fk_new_session(&kernel);
        kernel.crashSubwrite = crash;
        controller = NULL;
        EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
        (void)tcnc_recover_to_fixed_point(controller);
        tcnc_controller_destroy(controller);
        EXPECT_TRUE(!kernel.invalidLiveTableObserved);
        bool terminal = fk_recover_and_is_terminal(&kernel);
        if (!terminal) {
            fprintf(stderr,
                    "canonical restore skew=%u subwrite crash=%llu" " did not recover\n",
                    moduleSkew,
                    (unsigned long long)crash);
        }
        EXPECT_TRUE(terminal);
        EXPECT_TRUE(fk_full_snapshot_equal(&kernel, &baseline));
        fk_destroy(&kernel);
    }
    fk_destroy(&baseline);
    fk_destroy(&base);
}

static void test_canonical_restore_marker_words_then_type(void) {
    for (uint8_t moduleSkew = 0; moduleSkew < sizeof(uint32_t); moduleSkew++) {
        run_canonical_restore_adversarial_uuid(moduleSkew);
    }

    /* sourceType + canonical payload + a UUID-only tear also rolls back. */
    fake_kernel sourceTear = {0};
    EXPECT_EQ(0, fk_initialize(&sourceTear));
    fake_node *app = fk_node(&sourceTear, 0);
    fake_module *module = fk_pointer(&sourceTear, app->module, FK_MODULE_SIZE);
    memset(module->marker, 0x5a, sizeof(uint32_t));
    EXPECT_TRUE(fk_recover_and_is_terminal(&sourceTear));
    fk_destroy(&sourceTear);
}

static void test_ready_nonclone_with_peer_fails_closed(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry entry = fk_entry(0xec, 1);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    tcnc_controller_destroy(controller);

    fake_node *carrier = fk_node(&kernel, 0);
    fake_node *foreignPeer = fk_node(&kernel, 1);
    fake_module *module = fk_pointer(&kernel, carrier->module, FK_MODULE_SIZE);
    tcnm_marker_fields fields = {
        .nonce = {0x10, 0x20, 0x30, 0x40},
        .peerModuleLow32 = (uint32_t)foreignPeer->module,
        .phase = TCNM_MARKER_PHASE_READY,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = false,
    };
    tcnm_marker_binding binding = {
        .selfModuleLow32 = (uint32_t)carrier->module,
        .peerModuleLow32 = fields.peerModuleLow32,
        .selfModuleSize = carrier->moduleSize,
        .peerModuleSize = foreignPeer->moduleSize,
        .selfVersion = module->version,
        .peerVersion = module->version,
        .selfCapacity = module->capacity,
        .peerCapacity = module->capacity,
        .payload = module->payload,
        .payloadSize = sizeof(module->payload),
    };
    EXPECT_EQ(0, tcnm_marker_encode(&fields, &binding, module->marker));

    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    EXPECT_EQ(EPROTO, tcnc_recover_to_fixed_point(controller));
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_ready_crc_damage_fails_closed(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry entry = fk_entry(0xed, 1);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    tcnc_controller_destroy(controller);

    fake_node *carrier = fk_node(&kernel, 0);
    fake_module *module = fk_pointer(&kernel, carrier->module, FK_MODULE_SIZE);
    module->marker[TCNM_MARKER_CRC_OFFSET] ^= 1;
    fk_new_session(&kernel);
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    EXPECT_EQ(EPROTO, tcnc_recover_to_fixed_point(controller));
    EXPECT_EQ(0, kernel.reloadCalls);
    EXPECT_EQ(0, kernel.protectedCalls);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

static void test_ready_source_type_is_reported_recoverable_mismatch(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_initialize(&kernel));
    tcnm_entry entry = fk_entry(0xf0, 1);

    fake_kernel baseline = {0};
    EXPECT_EQ(0, fk_clone(&kernel, &baseline));
    fk_new_session(&baseline);
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&baseline, false, &controller));
    EXPECT_EQ(0, tcnc_bootstrap_append(controller, &entry, 1));
    tcnc_controller_destroy(controller);
    uint64_t commitCall = baseline.protectedCalls;
    fk_destroy(&baseline);

    fk_new_session(&kernel);
    kernel.failProtectedCall = commitCall;
    EXPECT_EQ(0, fk_controller_create(&kernel, false, &controller));
    EXPECT_TRUE(tcnc_bootstrap_append(controller, &entry, 1) != 0);
    fake_node *pendingNode = fk_node(&kernel, 0);
    fake_module *pendingModule = fk_pointer(&kernel, pendingNode->module, FK_MODULE_SIZE);
    EXPECT_EQ(TCNM_SOURCE_APP, pendingNode->type);
    EXPECT_EQ(TCNM_MARKER_VERSION, pendingModule->marker[TCNM_MARKER_VERSION_OFFSET]);
    EXPECT_EQ(TCNM_MARKER_PHASE_READY, pendingModule->marker[TCNM_MARKER_PHASE_OFFSET]);
    tcnc_controller_destroy(controller);
    EXPECT_TRUE(fk_recover_and_is_terminal(&kernel));
    fk_destroy(&kernel);
}

static void test_collapsed_ready_detached_metadata_is_verified(void) {
    fake_kernel kernel = {0};
    EXPECT_EQ(0, fk_prepare_pair(&kernel));
    fake_node *bootstrapNode = fk_node(&kernel, 0);
    fake_node *pairedNode = fk_node(&kernel, 2);
    uint64_t detachedAddress = bootstrapNode->module;
    bootstrapNode->module = pairedNode->module;
    fake_module *detached = fk_pointer(&kernel, detachedAddress, FK_MODULE_SIZE);
    uint32_t wrongPeer = (uint32_t)pairedNode->module + (uint32_t)FK_MODULE_STEP;
    tcnm_marker_fields fields = {
        .peerModuleLow32 = wrongPeer,
        .phase = TCNM_MARKER_PHASE_READY,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = true,
        .nonce = {9, 8, 7, 6},
    };
    tcnm_marker_binding binding = {
        .selfModuleLow32 = (uint32_t)detachedAddress,
        .peerModuleLow32 = wrongPeer,
        .selfModuleSize = FK_MODULE_SIZE,
        .peerModuleSize = FK_MODULE_SIZE,
        .selfVersion = 1,
        .peerVersion = 1,
        .selfCapacity = FK_CAPACITY,
        .peerCapacity = FK_CAPACITY,
        .payload = detached->payload,
        .payloadSize = sizeof(detached->payload),
    };
    EXPECT_EQ(0, tcnm_marker_encode(&fields, &binding, detached->marker));
    tcnc_controller *controller = NULL;
    EXPECT_EQ(0, fk_controller_create(&kernel, true, &controller));
    EXPECT_TRUE(tcnc_recover_to_fixed_point(controller) != 0);
    tcnc_controller_destroy(controller);
    fk_destroy(&kernel);
}

int main(void) {
    test_bootstrap_reboot_adopts_then_prepares_pair();
    test_bootstrap_singleton_is_ready_without_loader();
    test_bootstrap_recovery_does_not_call_unavailable_loader();
    test_ready_clone_without_source_uses_loader_policy();
    test_bootstrap_uses_empty_carrier_capacity();
    test_scans_follow_forward_links_only();
    test_bootstrap_quarantines_unmanaged_nodes_and_repairs_chain();
    test_bootstrap_preserves_managed_intermediate_carrier();
    test_unmanaged_quarantine_failure_is_retryable();
    test_previous_link_repair_failures_are_best_effort();
    test_previous_link_readback_failure_is_best_effort();
    test_bootstrap_ignores_oversized_foreign_source();
    test_query_read_error_is_terminal();
    test_copy_entries_deduplicates_carrier_pair();
    test_query_snapshot_preserves_payload_error_order();
    test_batch_missing_query_scans_once();
    test_append_is_uuid_free_idempotent_and_batches();
    test_two_clients_are_owner_serialized();
    test_bootstrap_all_write_faults_recover();
    test_expansion_all_write_and_reload_faults_recover();
    test_unpaired_requires_clone_peer_zero_recovers();
    test_runtime_subwrite_crash_recovers();
    test_recovery_itself_all_write_faults_converges();
    test_canonical_restore_marker_words_then_type();
    test_ready_nonclone_with_peer_fails_closed();
    test_ready_crc_damage_fails_closed();
    test_ready_source_type_is_reported_recoverable_mismatch();
    test_collapsed_ready_detached_metadata_is_verified();
    test_version_zero_source_is_not_a_carrier();
    test_config_resource_ceiling();
    if (gTest.failures) {
        fprintf(stderr, "trustcache_nokcall_controller: %u failure(s)\n", gTest.failures);
        return 1;
    }
    puts("trustcache_nokcall_controller: all tests passed");
    return 0;
}
