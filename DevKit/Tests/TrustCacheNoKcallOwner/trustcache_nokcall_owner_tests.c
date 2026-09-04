#include "trustcache_nokcall_owner.h"

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define FAKE_ENTRY_LIMIT 16U

struct tcnc_controller {
    uint32_t sentinel;
};

typedef enum {
    FAKE_APPEND_NORMAL,
    FAKE_APPEND_AMBIGUOUS_COMMITTED,
    FAKE_APPEND_ENOTSUP_COMMITTED,
    FAKE_APPEND_EXPAND_NO_CARRIER,
} fake_append_mode;

typedef struct {
    uint32_t destroyCalls;
    uint32_t destroyOrder;
} fake_resource;

typedef struct {
    pthread_mutex_t entriesLock;
    tcnm_entry entries[FAKE_ENTRY_LIMIT];
    uint32_t entryCount;
    fake_append_mode appendMode;
    bool ambiguousFired;
    int queryStatus;
    atomic_int activeAppends;
    atomic_int maxActiveAppends;
    uint32_t controllerCreateCalls;
    int controllerCreateStatus;
    uint32_t controllerDestroyCalls;
    uint32_t recoverCalls;
    uint32_t recoverFailuresRemaining;
    uint32_t preparePairCalls;
    int preparePairStatus;
    atomic_uint appendCalls;
    uint32_t queryCalls;
    uint32_t bootstrapCalls;
    uint32_t expansionCalls;
    uint32_t liveInPlaceMutationCalls;
    uint32_t destructionOrder;
    uint32_t controllerDestroyOrder;
} fake_state;

static struct tcnc_controller gController;
static fake_resource gPrimaryResource;
static fake_resource gRejectedResource;
static fake_state gFake = {
    .entriesLock = PTHREAD_MUTEX_INITIALIZER,
};
static void fake_reset(fake_append_mode appendMode) {
    pthread_mutex_lock(&gFake.entriesLock);
    memset(gFake.entries, 0, sizeof(gFake.entries));
    gFake.entryCount = 0;
    pthread_mutex_unlock(&gFake.entriesLock);
    gFake.appendMode = appendMode;
    gFake.ambiguousFired = false;
    gFake.queryStatus = 0;
    atomic_store(&gFake.activeAppends, 0);
    atomic_store(&gFake.maxActiveAppends, 0);
    gFake.controllerCreateCalls = 0;
    gFake.controllerCreateStatus = 0;
    gFake.controllerDestroyCalls = 0;
    gFake.recoverCalls = 0;
    gFake.recoverFailuresRemaining = 0;
    gFake.preparePairCalls = 0;
    gFake.preparePairStatus = 0;
    atomic_store(&gFake.appendCalls, 0);
    gFake.queryCalls = 0;
    gFake.bootstrapCalls = 0;
    gFake.expansionCalls = 0;
    gFake.liveInPlaceMutationCalls = 0;
    gFake.destructionOrder = 0;
    gFake.controllerDestroyOrder = 0;
    gPrimaryResource = (fake_resource){0};
    gRejectedResource = (fake_resource){0};
}

static tcnm_entry fake_entry(uint8_t seed) {
    tcnm_entry entry = {
        .hashType = 2,
        .flags = 0,
    };
    for (size_t index = 0; index < sizeof(entry.hash); index++) {
        entry.hash[index] = (uint8_t)(seed + index);
    }
    return entry;
}

static void fake_record_entries(const tcnm_entry *entries, uint32_t entryCount) {
    pthread_mutex_lock(&gFake.entriesLock);
    assert(gFake.entryCount + entryCount <= FAKE_ENTRY_LIMIT);
    memcpy(&gFake.entries[gFake.entryCount], entries, (size_t)entryCount * sizeof(*entries));
    gFake.entryCount += entryCount;
    pthread_mutex_unlock(&gFake.entriesLock);
}

static bool fake_contains_hash(const uint8_t hash[TCNM_HASH_SIZE]) {
    bool found = false;
    pthread_mutex_lock(&gFake.entriesLock);
    for (uint32_t index = 0; index < gFake.entryCount; index++) {
        if (memcmp(gFake.entries[index].hash, hash, TCNM_HASH_SIZE) == 0) {
            found = true;
            break;
        }
    }
    pthread_mutex_unlock(&gFake.entriesLock);
    return found;
}

static void fake_note_active_append(int active) {
    int maximum = atomic_load(&gFake.maxActiveAppends);
    while (active > maximum && !atomic_compare_exchange_weak(&gFake.maxActiveAppends, &maximum, active)) {
    }
}

bool tcnm_hash_is_zero(const uint8_t hash[TCNM_HASH_SIZE]) {
    for (size_t index = 0; index < TCNM_HASH_SIZE; index++) {
        if (hash[index] != 0)
            return false;
    }
    return true;
}

int tcnc_controller_create(const tcnc_config *config, const tcnc_backend *backend, tcnc_controller **controllerOut) {
    assert(config);
    assert(backend);
    assert(controllerOut);
    gFake.controllerCreateCalls++;
    if (gFake.controllerCreateStatus != 0) {
        *controllerOut = NULL;
        return gFake.controllerCreateStatus;
    }
    gController.sentinel = UINT32_C(0x54434E4F);
    *controllerOut = &gController;
    return 0;
}

void tcnc_controller_destroy(tcnc_controller *controller) {
    assert(controller == &gController);
    gFake.controllerDestroyCalls++;
    gFake.controllerDestroyOrder = ++gFake.destructionOrder;
}

int tcnc_bootstrap_append(tcnc_controller *controller, const tcnm_entry *entries, uint32_t entryCount) {
    (void)controller;
    (void)entries;
    (void)entryCount;
    gFake.bootstrapCalls++;
    return EPROTO;
}

int tcnc_recover_to_fixed_point(tcnc_controller *controller) {
    assert(controller == &gController);
    gFake.recoverCalls++;
    if (gFake.recoverFailuresRemaining != 0) {
        gFake.recoverFailuresRemaining--;
        return EIO;
    }
    return 0;
}

int tcnc_prepare_runtime_pair(tcnc_controller *controller) {
    assert(controller == &gController);
    gFake.preparePairCalls++;
    return gFake.preparePairStatus;
}

int tcnc_append(tcnc_controller *controller, const tcnm_entry *entries, uint32_t entryCount) {
    assert(controller == &gController);
    assert(entries);
    assert(entryCount != 0);
    atomic_fetch_add(&gFake.appendCalls, 1);

    int active = atomic_fetch_add(&gFake.activeAppends, 1) + 1;
    fake_note_active_append(active);
    struct timespec delay = {
        .tv_nsec = 20 * 1000 * 1000,
    };
    nanosleep(&delay, NULL);

    int status = 0;
    if (gFake.appendMode == FAKE_APPEND_EXPAND_NO_CARRIER) {
        gFake.expansionCalls++;
        fake_record_entries(entries, entryCount);
    } else if (gFake.appendMode == FAKE_APPEND_AMBIGUOUS_COMMITTED && !gFake.ambiguousFired) {
        gFake.ambiguousFired = true;
        fake_record_entries(entries, entryCount);
        status = EIO;
    } else if (gFake.appendMode == FAKE_APPEND_ENOTSUP_COMMITTED && !gFake.ambiguousFired) {
        gFake.ambiguousFired = true;
        fake_record_entries(entries, entryCount);
        status = ENOTSUP;
    } else {
        fake_record_entries(entries, entryCount);
    }

    atomic_fetch_sub(&gFake.activeAppends, 1);
    return status;
}

int tcnc_query(tcnc_controller *controller, const uint8_t hash[TCNM_HASH_SIZE], bool *foundOut) {
    assert(controller == &gController);
    assert(hash);
    assert(foundOut);
    gFake.queryCalls++;
    *foundOut = false;
    if (gFake.queryStatus != 0)
        return gFake.queryStatus;
    *foundOut = fake_contains_hash(hash);
    return 0;
}

int tcnc_copy_entries(tcnc_controller *controller, tcnm_entry **entriesOut, uint32_t *entryCountOut) {
    assert(controller == &gController);
    assert(entriesOut);
    assert(entryCountOut);
    *entriesOut = NULL;
    *entryCountOut = 0;

    pthread_mutex_lock(&gFake.entriesLock);
    if (gFake.entryCount != 0) {
        *entriesOut = malloc((size_t)gFake.entryCount * sizeof(**entriesOut));
        assert(*entriesOut);
        memcpy(*entriesOut, gFake.entries, (size_t)gFake.entryCount * sizeof(**entriesOut));
        *entryCountOut = gFake.entryCount;
    }
    pthread_mutex_unlock(&gFake.entriesLock);
    return 0;
}

int tcnc_signed_sources_present(tcnc_controller *controller, bool *osPresentOut, bool *appPresentOut) {
    assert(controller == &gController);
    assert(osPresentOut);
    assert(appPresentOut);
    *osPresentOut = true;
    *appPresentOut = true;
    return 0;
}

static void fake_destroy_resources(void *context) {
    fake_resource *resource = context;
    assert(resource);
    resource->destroyCalls++;
    resource->destroyOrder = ++gFake.destructionOrder;
}

static int fake_prepare(fake_resource *resource) {
    tcnc_config config = {0};
    tcnc_backend backend = {0};
    return tcno_prepare_and_recover(&config, &backend, fake_destroy_resources, resource);
}

static void test_initial_gate(void) {
    fake_reset(FAKE_APPEND_NORMAL);
    tcnm_entry entry = fake_entry(0x10);
    bool found = true;

    assert(tcno_status() == EAGAIN);
    assert(tcno_append(&entry, 1) == EAGAIN);
    assert(tcno_query(entry.hash, &found) == EAGAIN);
    assert(!found);
    assert(gFake.controllerCreateCalls == 0);
}

static void test_no_carrier_uses_runtime_expansion(void) {
    fake_reset(FAKE_APPEND_EXPAND_NO_CARRIER);
    assert(fake_prepare(&gPrimaryResource) == 0);
    assert(tcno_status() == 0);

    tcnm_entry entry = fake_entry(0x20);
    assert(tcno_append(&entry, 1) == 0);
    assert(atomic_load(&gFake.appendCalls) == 1);
    assert(gFake.expansionCalls == 1);
    assert(gFake.bootstrapCalls == 0);
    assert(gFake.liveInPlaceMutationCalls == 0);

    bool found = false;
    assert(tcno_query(entry.hash, &found) == 0);
    assert(found);
    assert(gPrimaryResource.destroyCalls == 0);
}

static void test_create_failure_consumes_resources(void) {
    fake_reset(FAKE_APPEND_NORMAL);
    gFake.controllerCreateStatus = ENOMEM;
    assert(fake_prepare(&gPrimaryResource) == ENOMEM);
    assert(gFake.controllerCreateCalls == 1);
    assert(gFake.controllerDestroyCalls == 0);
    assert(gPrimaryResource.destroyCalls == 1);
    assert(tcno_status() == EAGAIN);
}

static void test_operation_errors_recover_before_returning(void) {
    fake_reset(FAKE_APPEND_ENOTSUP_COMMITTED);
    assert(fake_prepare(&gPrimaryResource) == 0);

    tcnm_entry entry = fake_entry(0x24);
    uint32_t recoverCallsBefore = gFake.recoverCalls;
    assert(tcno_append(&entry, 1) == 0);
    assert(gFake.recoverCalls == recoverCallsBefore + 1);
    assert(fake_contains_hash(entry.hash));
    assert(tcno_status() == 0);
}

static void test_next_mutation_retries_recovery(void) {
    fake_reset(FAKE_APPEND_AMBIGUOUS_COMMITTED);
    assert(fake_prepare(&gPrimaryResource) == 0);

    gFake.recoverFailuresRemaining = 1;
    tcnm_entry entry = fake_entry(0x26);
    assert(tcno_append(&entry, 1) == EAGAIN);
    assert(tcno_status() == EAGAIN);

    bool found = true;
    assert(tcno_query(entry.hash, &found) == EAGAIN);
    assert(!found);

    assert(tcno_append(&entry, 1) == 0);
    assert(tcno_status() == 0);
    assert(tcno_query(entry.hash, &found) == 0);
    assert(found);
}

static void test_non_owner_gate(void) {
    fake_reset(FAKE_APPEND_NORMAL);
    tcnm_entry entry = fake_entry(0x28);
    bool found = true;

    assert(fake_prepare(&gPrimaryResource) == EPERM);
    assert(gPrimaryResource.destroyCalls == 1);
    assert(gFake.controllerCreateCalls == 0);
    assert(tcno_recover() == EPERM);
    assert(tcno_prepare_runtime_pair() == EPERM);
    assert(tcno_append(&entry, 1) == EPERM);
    assert(tcno_query(entry.hash, &found) == EPERM);
    assert(!found);
    assert(atomic_load(&gFake.appendCalls) == 0);
    assert(gFake.queryCalls == 0);
    assert(gFake.expansionCalls == 0);
}

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t condition;
    uint32_t waiting;
    bool open;
} start_gate;

typedef struct {
    start_gate *gate;
    tcnm_entry entry;
    int status;
} append_call;

static void start_gate_wait(start_gate *gate) {
    pthread_mutex_lock(&gate->lock);
    gate->waiting++;
    pthread_cond_broadcast(&gate->condition);
    while (!gate->open) {
        pthread_cond_wait(&gate->condition, &gate->lock);
    }
    pthread_mutex_unlock(&gate->lock);
}

static void *append_thread(void *context) {
    append_call *call = context;
    start_gate_wait(call->gate);
    call->status = tcno_append(&call->entry, 1);
    return NULL;
}

static void test_lifecycle_and_serialization(void) {
    fake_reset(FAKE_APPEND_NORMAL);
    assert(fake_prepare(&gPrimaryResource) == 0);
    assert(fake_prepare(&gRejectedResource) == EALREADY);
    assert(gFake.controllerCreateCalls == 1);
    assert(gRejectedResource.destroyCalls == 1);
    assert(gPrimaryResource.destroyCalls == 0);

    gFake.preparePairStatus = ENOTSUP;
    uint32_t recoverCallsBefore = gFake.recoverCalls;
    assert(tcno_prepare_runtime_pair() == ENOTSUP);
    assert(gFake.preparePairCalls == 1);
    assert(gFake.recoverCalls == recoverCallsBefore + 1);
    assert(tcno_status() == 0);
    gFake.preparePairStatus = 0;
    assert(tcno_prepare_runtime_pair() == 0);
    assert(gFake.preparePairCalls == 2);

    start_gate gate = {
        .lock = PTHREAD_MUTEX_INITIALIZER,
        .condition = PTHREAD_COND_INITIALIZER,
    };
    append_call first = {
        .gate = &gate,
        .entry = fake_entry(0x30),
    };
    append_call second = {
        .gate = &gate,
        .entry = fake_entry(0x50),
    };
    pthread_t threads[2] = {0};
    assert(pthread_create(&threads[0], NULL, append_thread, &first) == 0);
    assert(pthread_create(&threads[1], NULL, append_thread, &second) == 0);

    pthread_mutex_lock(&gate.lock);
    while (gate.waiting != 2) {
        pthread_cond_wait(&gate.condition, &gate.lock);
    }
    gate.open = true;
    pthread_cond_broadcast(&gate.condition);
    pthread_mutex_unlock(&gate.lock);

    assert(pthread_join(threads[0], NULL) == 0);
    assert(pthread_join(threads[1], NULL) == 0);
    assert(first.status == 0);
    assert(second.status == 0);
    assert(atomic_load(&gFake.maxActiveAppends) == 1);

    gFake.appendMode = FAKE_APPEND_AMBIGUOUS_COMMITTED;
    tcnm_entry ambiguous = fake_entry(0x70);
    recoverCallsBefore = gFake.recoverCalls;
    assert(tcno_append(&ambiguous, 1) == 0);
    assert(gFake.recoverCalls == recoverCallsBefore + 1);
    assert(gFake.queryCalls != 0);
    assert(fake_contains_hash(ambiguous.hash));
    assert(tcno_status() == 0);

    gFake.queryStatus = EPROTO;
    bool found = true;
    assert(tcno_query(ambiguous.hash, &found) == EPROTO);
    assert(!found);
    assert(tcno_status() == 0);

    gFake.queryStatus = 0;
    uint32_t appendCallsBefore = atomic_load(&gFake.appendCalls);
    tcnm_entry final = fake_entry(0x80);
    assert(tcno_append(&final, 1) == 0);
    assert(atomic_load(&gFake.appendCalls) == appendCallsBefore + 1);
    assert(gPrimaryResource.destroyCalls == 0);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    if (strcmp(argv[1], "gate") == 0) {
        test_initial_gate();
    } else if (strcmp(argv[1], "no-carrier") == 0) {
        test_no_carrier_uses_runtime_expansion();
    } else if (strcmp(argv[1], "create-failure") == 0) {
        test_create_failure_consumes_resources();
    } else if (strcmp(argv[1], "operation-errors") == 0) {
        test_operation_errors_recover_before_returning();
    } else if (strcmp(argv[1], "retry-recovery") == 0) {
        test_next_mutation_retries_recovery();
    } else if (strcmp(argv[1], "non-owner") == 0) {
        test_non_owner_gate();
    } else if (strcmp(argv[1], "lifecycle") == 0) {
        test_lifecycle_and_serialization();
    } else {
        fprintf(stderr, "unknown scenario: %s\n", argv[1]);
        return 2;
    }
    printf("trustcache_nokcall_owner: %s passed\n", argv[1]);
    return 0;
}
