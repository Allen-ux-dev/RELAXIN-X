#include "trustcache_nokcall_model.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_STRIDE 22U
#define TEST_CAPACITY 6U

static unsigned int gFailureCount;

#define EXPECT_TRUE(expression) \
	do { \
		if (!(expression)) { \
			fprintf(stderr, \
			        "%s:%d: expected true: %s\n", \
			        __FILE__, \
			        __LINE__, \
			        #expression); \
			gFailureCount++; \
		} \
	} while (0)

#define EXPECT_EQ(expected, observed) \
	do { \
		long long expectedValue = (long long)(expected); \
		long long observedValue = (long long)(observed); \
		if (expectedValue != observedValue) { \
			fprintf(stderr, \
			        "%s:%d: expected %lld, observed %lld: %s\n", \
			        __FILE__, \
			        __LINE__, \
			        expectedValue, \
			        observedValue, \
			        #observed); \
			gFailureCount++; \
		} \
	} while (0)

static tcnm_entry entry_with_leading_byte(uint8_t byte) {
    tcnm_entry entry = {0};
    entry.hash[0] = byte;
    entry.hashType = 2;
    entry.flags = 1;
    return entry;
}

static void encode_entry(uint8_t *raw, uint32_t index, const tcnm_entry *entry) {
    uint8_t *target = raw + (size_t)index * TEST_STRIDE;
    memcpy(target, entry->hash, TCNM_HASH_SIZE);
    target[TCNM_HASH_SIZE] = entry->hashType;
    target[TCNM_HASH_SIZE + 1] = entry->flags;
}

static void test_entries_decode_and_validate(void) {
    uint8_t raw[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_entry a = entry_with_leading_byte(0x20);
    tcnm_entry b = entry_with_leading_byte(0x40);
    encode_entry(raw, 4, &a);
    encode_entry(raw, 5, &b);

    EXPECT_EQ(0, tcnm_entries_validate(raw, TEST_CAPACITY, TEST_STRIDE));
    tcnm_entry decoded[TEST_CAPACITY] = {0};
    uint32_t used = 0;
    EXPECT_EQ(0, tcnm_entries_decode(raw, TEST_CAPACITY, TEST_STRIDE, decoded, TEST_CAPACITY, &used));
    EXPECT_EQ(2, used);
    EXPECT_TRUE(memcmp(decoded[0].hash, a.hash, TCNM_HASH_SIZE) == 0);
    EXPECT_TRUE(memcmp(decoded[1].hash, b.hash, TCNM_HASH_SIZE) == 0);

    memset(raw, 0, sizeof(raw));
    encode_entry(raw, 3, &a);
    encode_entry(raw, 5, &b);
    EXPECT_EQ(EPROTO, tcnm_entries_validate(raw, TEST_CAPACITY, TEST_STRIDE));

    memset(raw, 0, sizeof(raw));
    encode_entry(raw, 4, &b);
    encode_entry(raw, 5, &a);
    EXPECT_EQ(EPROTO, tcnm_entries_validate(raw, TEST_CAPACITY, TEST_STRIDE));
}

static void test_entries_merge_regression(void) {
    uint8_t current[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_entry a = entry_with_leading_byte(0x20);
    tcnm_entry d = entry_with_leading_byte(0x80);
    encode_entry(current, 4, &a);
    encode_entry(current, 5, &d);

    tcnm_entry additions[] = {
        entry_with_leading_byte(0x60),
        entry_with_leading_byte(0x40),
        entry_with_leading_byte(0x40),
        entry_with_leading_byte(0x20),
    };
    uint8_t target[sizeof(current)] = {0};
    uint32_t used = 0;
    EXPECT_EQ(0,
              tcnm_entries_merge(current,
                                 TEST_CAPACITY,
                                 TEST_STRIDE,
                                 additions,
                                 sizeof(additions) / sizeof(additions[0]),
                                 target,
                                 &used));
    EXPECT_EQ(4, used);
    EXPECT_EQ(0, tcnm_entries_validate(target, TEST_CAPACITY, TEST_STRIDE));
    EXPECT_EQ(0x20, target[2 * TEST_STRIDE]);
    EXPECT_EQ(0x40, target[3 * TEST_STRIDE]);
    EXPECT_EQ(0x60, target[4 * TEST_STRIDE]);
    EXPECT_EQ(0x80, target[5 * TEST_STRIDE]);

    tcnm_entry zero = {0};
    EXPECT_EQ(EINVAL, tcnm_entries_merge(current, TEST_CAPACITY, TEST_STRIDE, &zero, 1, target, &used));
}

static void test_v2_merge_preserves_existing_constraint_bytes(void) {
    enum { capacity = 4 };
    uint8_t current[capacity * TCNM_ENTRY_V2_SIZE] = {0};
    tcnm_entry existing = entry_with_leading_byte(0x20);
    uint8_t *existingRaw = current + (capacity - 1) * TCNM_ENTRY_V2_SIZE;
    memcpy(existingRaw, existing.hash, TCNM_HASH_SIZE);
    existingRaw[TCNM_HASH_SIZE] = existing.hashType;
    existingRaw[TCNM_HASH_SIZE + 1] = existing.flags;
    existingRaw[TCNM_HASH_SIZE + 2] = 0x34;
    existingRaw[TCNM_HASH_SIZE + 3] = 0x12;

    tcnm_entry addition = entry_with_leading_byte(0x40);
    uint8_t target[sizeof(current)] = {0};
    uint32_t used = 0;
    EXPECT_EQ(0, tcnm_entries_merge(current, capacity, TCNM_ENTRY_V2_SIZE, &addition, 1, target, &used));
    EXPECT_EQ(2, used);
    const uint8_t *preserved = target + (capacity - 2) * TCNM_ENTRY_V2_SIZE;
    EXPECT_EQ(0x34, preserved[TCNM_HASH_SIZE + 2]);
    EXPECT_EQ(0x12, preserved[TCNM_HASH_SIZE + 3]);
    const uint8_t *inserted = target + (capacity - 1) * TCNM_ENTRY_V2_SIZE;
    EXPECT_EQ(0, inserted[TCNM_HASH_SIZE + 2]);
    EXPECT_EQ(0, inserted[TCNM_HASH_SIZE + 3]);
}

static void make_marker_pair(tcnm_marker_phase preparedPhase,
                             bool requiresClone,
                             uint8_t prepared[TCNM_MARKER_SIZE],
                             uint8_t ready[TCNM_MARKER_SIZE]) {
    static const uint8_t payload[TEST_CAPACITY * TEST_STRIDE] = {0};
    const tcnm_marker_binding binding = {
        .selfModuleLow32 = UINT32_C(0x1000),
        .peerModuleLow32 = UINT32_C(0x2000),
        .selfModuleSize = TCNM_FILE_HEADER_SIZE + sizeof(payload),
        .peerModuleSize = TCNM_FILE_HEADER_SIZE + sizeof(payload),
        .selfVersion = 1,
        .peerVersion = 1,
        .selfCapacity = TEST_CAPACITY,
        .peerCapacity = TEST_CAPACITY,
        .payload = payload,
        .payloadSize = sizeof(payload),
    };
    tcnm_marker_fields fields = {
        .nonce = {0, 1, 2, 3},
        .peerModuleLow32 = binding.peerModuleLow32,
        .phase = preparedPhase,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = requiresClone,
    };
    EXPECT_EQ(0, tcnm_marker_encode(&fields, &binding, prepared));
    fields.phase = TCNM_MARKER_PHASE_READY;
    EXPECT_EQ(0, tcnm_marker_encode(&fields, &binding, ready));
}

static void test_marker_crc_parse_and_damage_detection(void) {
    static uint8_t payload[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_marker_binding binding = {
        .selfModuleLow32 = UINT32_C(0x1000),
        .peerModuleLow32 = UINT32_C(0x2000),
        .selfModuleSize = TCNM_FILE_HEADER_SIZE + sizeof(payload),
        .peerModuleSize = TCNM_FILE_HEADER_SIZE + sizeof(payload),
        .selfVersion = 1,
        .peerVersion = 1,
        .selfCapacity = TEST_CAPACITY,
        .peerCapacity = TEST_CAPACITY,
        .payload = payload,
        .payloadSize = sizeof(payload),
    };
    EXPECT_EQ(UINT32_C(0xCBF43926), tcnm_crc32("123456789", 9));
    uint8_t prepared[TCNM_MARKER_SIZE] = {0};
    uint8_t ready[TCNM_MARKER_SIZE] = {0};
    make_marker_pair(TCNM_MARKER_PHASE_PREPARED_SOURCE, true, prepared, ready);

    tcnm_marker_fields decoded = {0};
    EXPECT_EQ(0, tcnm_marker_decode(prepared, &binding, &decoded));
    EXPECT_EQ(TCNM_MARKER_PHASE_PREPARED_SOURCE, decoded.phase);
    EXPECT_EQ(TCNM_SOURCE_APP, decoded.sourceKind);
    EXPECT_EQ(binding.peerModuleLow32, decoded.peerModuleLow32);
    EXPECT_TRUE(decoded.requiresClone);

    uint8_t damaged[TCNM_MARKER_SIZE] = {0};
    memcpy(damaged, prepared, sizeof(damaged));
    damaged[0] ^= 1;
    EXPECT_EQ(EBADMSG, tcnm_marker_decode(damaged, &binding, &decoded));
    for (size_t index = 0; index < TCNM_MARKER_SIZE; index++) {
        memcpy(damaged, prepared, sizeof(damaged));
        damaged[index] ^= UINT8_C(0x40);
        EXPECT_TRUE(tcnm_marker_decode(damaged, &binding, &decoded) != 0);
    }
    payload[0] = 1;
    EXPECT_EQ(EBADMSG, tcnm_marker_decode(prepared, &binding, &decoded));
    payload[0] = 0;
    binding.peerCapacity--;
    EXPECT_EQ(EINVAL, tcnm_marker_decode(prepared, &binding, &decoded));
    binding.peerCapacity++;
    binding.peerModuleLow32 = UINT32_C(0x3000);
    EXPECT_EQ(EPROTO, tcnm_marker_decode(prepared, &binding, &decoded));
    binding.peerModuleLow32 = UINT32_C(0x2000);

    /* Low 32 address bits may legitimately be zero for an unpaired bank. */
    binding.selfModuleLow32 = 0;
    binding.peerModuleLow32 = 0;
    tcnm_marker_fields unpairedFields = {
        .nonce = {0x12, 0x34, 0x56, 0x78},
        .peerModuleLow32 = 0,
        .phase = TCNM_MARKER_PHASE_READY,
        .sourceKind = TCNM_SOURCE_APP,
        .requiresClone = true,
    };
    uint8_t unpaired[TCNM_MARKER_SIZE] = {0};
    EXPECT_EQ(0, tcnm_marker_encode(&unpairedFields, &binding, unpaired));
    EXPECT_EQ(0, tcnm_marker_decode(unpaired, &binding, &decoded));
    binding.selfModuleLow32 = UINT32_C(0x1000);
    binding.peerModuleLow32 = UINT32_C(0x2000);
}

static void expect_observed_policy(const tcnm_observed_evidence *evidence,
                                   tcnm_observed_state expectedState,
                                   tcnm_recovery_action expectedAction) {
    tcnm_observed_state observed = tcnm_observed_classify(evidence);
    EXPECT_EQ(expectedState, observed);
    EXPECT_EQ(expectedAction, tcnm_recovery_decide(observed));
}

static tcnm_observed_evidence base_observed_evidence(const uint8_t *observedPayload, const uint8_t *canonicalPayload) {
    return (tcnm_observed_evidence){
        .observedType = 2,
        .sourceKind = TCNM_SOURCE_APP,
        .carrierType = 2,
        .markerHeaderKnown = true,
        .markerValid = true,
        .markerPhase = TCNM_MARKER_PHASE_READY,
        .markerSourceKind = TCNM_SOURCE_APP,
        .observedPayload = observedPayload,
        .canonicalPayload = canonicalPayload,
        .capacity = TEST_CAPACITY,
        .stride = TEST_STRIDE,
    };
}

static void test_observed_state_and_recovery_table(void) {
    uint8_t canonical[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_entry source = entry_with_leading_byte(0x40);
    encode_entry(canonical, 5, &source);
    uint8_t other[sizeof(canonical)] = {0};
    tcnm_entry addition = entry_with_leading_byte(0x60);
    encode_entry(other, 5, &addition);
    uint8_t invalid[sizeof(canonical)] = {0};
    encode_entry(invalid, 3, &addition);
    encode_entry(invalid, 5, &source);

    tcnm_observed_evidence evidence = base_observed_evidence(other, canonical);

    /* The exact signed source is the only accepted original state. */
    evidence.observedType = TCNM_SOURCE_APP;
    evidence.exactSource = true;
    evidence.markerHeaderKnown = false;
    evidence.markerValid = false;
    evidence.observedPayload = canonical;
    expect_observed_policy(&evidence, TCNM_OBSERVED_EXACT_ORIGINAL, TCNM_RECOVERY_ACCEPT_ORIGINAL);

    /* A marker-only source tear is rolled back to canonical signed bytes. */
    evidence.exactSource = false;
    expect_observed_policy(&evidence, TCNM_OBSERVED_ROLLBACK_ONLY, TCNM_RECOVERY_RESTORE_ORIGINAL);
    evidence.exactCloneCount = 1;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);
    evidence.exactCloneCount = 0;
    evidence.markerHeaderKnown = true;
    evidence.markerPhase = TCNM_MARKER_PHASE_PREPARED_SOURCE;
    evidence.markerSourceKind = TCNM_SOURCE_APP;
    evidence.observedPayload = invalid;
    expect_observed_policy(&evidence, TCNM_OBSERVED_ROLLBACK_ONLY, TCNM_RECOVERY_RESTORE_ORIGINAL);

    /* READY nonclone is a stable bootstrap singleton and needs no loader. */
    evidence = base_observed_evidence(other, canonical);
    expect_observed_policy(&evidence, TCNM_OBSERVED_STABLE_READY, TCNM_RECOVERY_ACCEPT_READY);
    evidence.exactCloneCount = 1;
    expect_observed_policy(&evidence, TCNM_OBSERVED_STABLE_READY, TCNM_RECOVERY_ACCEPT_READY);
    evidence.peerDeclared = true;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);

    /* READY clone policy is the loader boundary. */
    evidence = base_observed_evidence(other, canonical);
    evidence.requiresClone = true;
    evidence.exactCloneCount = 1;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CLONED_READY, TCNM_RECOVERY_ACCEPT_READY);
    evidence.exactCloneCount = 0;
    expect_observed_policy(&evidence, TCNM_OBSERVED_READY_WITHOUT_CLONE, TCNM_RECOVERY_RELOAD_SOURCE);
    evidence.exactCloneCount = 2;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CLONED_READY, TCNM_RECOVERY_ACCEPT_READY);

    /* PREPARED clone transactions finish only when the source exists. */
    evidence = base_observed_evidence(other, canonical);
    evidence.markerPhase = TCNM_MARKER_PHASE_PREPARED_SOURCE;
    evidence.requiresClone = true;
    evidence.markerValid = false; /* Expected while payload changes. */
    expect_observed_policy(&evidence, TCNM_OBSERVED_PREPARED_WITHOUT_CLONE, TCNM_RECOVERY_RESTORE_ORIGINAL);
    evidence.exactCloneCount = 1;
    expect_observed_policy(&evidence, TCNM_OBSERVED_PREPARED_WITH_CLONE, TCNM_RECOVERY_RESTORE_EMPTY_READY);
    evidence.markerPhase = TCNM_MARKER_PHASE_PREPARED_FILL;
    expect_observed_policy(&evidence, TCNM_OBSERVED_PREPARED_WITH_CLONE, TCNM_RECOVERY_RESTORE_EMPTY_READY);

    /* PREPARED nonclone can only be the bootstrap rollback path. */
    evidence = base_observed_evidence(other, canonical);
    evidence.markerPhase = TCNM_MARKER_PHASE_PREPARED_SOURCE;
    expect_observed_policy(&evidence, TCNM_OBSERVED_ROLLBACK_ONLY, TCNM_RECOVERY_RESTORE_ORIGINAL);
    evidence.exactCloneCount = 1;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);

    /* CRC damage is never accepted as READY. */
    evidence = base_observed_evidence(other, canonical);
    evidence.markerValid = false;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);
    evidence.observedPayload = canonical;
    expect_observed_policy(&evidence, TCNM_OBSERVED_ROLLBACK_ONLY, TCNM_RECOVERY_RESTORE_ORIGINAL);

    /* A pre-version marker tear is safe only over canonical payload. */
    evidence = base_observed_evidence(canonical, canonical);
    evidence.markerHeaderKnown = false;
    evidence.markerValid = false;
    expect_observed_policy(&evidence, TCNM_OBSERVED_ROLLBACK_ONLY, TCNM_RECOVERY_RESTORE_ORIGINAL);
    evidence.observedPayload = other;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);

    /* Read failures retry; invalid/ambiguous evidence fails closed. */
    evidence = base_observed_evidence(other, canonical);
    evidence.cloneScanStatus = EIO;
    expect_observed_policy(&evidence, TCNM_OBSERVED_UNREADABLE, TCNM_RECOVERY_RETRY);
    evidence.cloneScanStatus = 0;
    evidence.observedPayload = NULL;
    expect_observed_policy(&evidence, TCNM_OBSERVED_UNREADABLE, TCNM_RECOVERY_RETRY);
    evidence.observedPayload = invalid;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);
    evidence.observedPayload = other;
    evidence.canonicalPayload = NULL;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);
    evidence.canonicalPayload = canonical;
    evidence.observedType = 7;
    expect_observed_policy(&evidence, TCNM_OBSERVED_CONFLICT, TCNM_RECOVERY_FAIL_CLOSED);

    /* Both signed source kinds intentionally share one carrier Type. */
    const uint8_t sourceKinds[] = {
        TCNM_SOURCE_APP,
        TCNM_SOURCE_OS,
    };
    for (size_t index = 0; index < sizeof(sourceKinds) / sizeof(sourceKinds[0]); index++) {
        EXPECT_EQ(TCNM_TYPE_OBSERVED_CARRIER, tcnm_type_classify(2, sourceKinds[index], 2));
    }
}

static void test_query_policy(void) {
    uint8_t raw[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_entry a = entry_with_leading_byte(0x20);
    tcnm_entry b = entry_with_leading_byte(0x40);
    encode_entry(raw, 4, &a);
    encode_entry(raw, 5, &b);

    bool found = false;
    EXPECT_EQ(0, tcnm_entries_query(raw, TEST_CAPACITY, TEST_STRIDE, a.hash, &found));
    EXPECT_TRUE(found);
    tcnm_entry missing = entry_with_leading_byte(0x30);
    EXPECT_EQ(0, tcnm_entries_query(raw, TEST_CAPACITY, TEST_STRIDE, missing.hash, &found));
    EXPECT_TRUE(!found);
    uint8_t zero[TCNM_HASH_SIZE] = {0};
    EXPECT_EQ(EINVAL, tcnm_entries_query(raw, TEST_CAPACITY, TEST_STRIDE, zero, &found));

    const tcnm_query_observation missingWithError[] = {
        {.status = EIO, .found = false},
        {.status = 0, .found = false},
    };
    EXPECT_EQ(EIO, tcnm_query_reduce(missingWithError, sizeof(missingWithError) / sizeof(missingWithError[0]), &found));
    EXPECT_TRUE(!found);

    const tcnm_query_observation foundAfterError[] = {
        {.status = EIO, .found = false},
        {.status = 0, .found = true},
    };
    EXPECT_EQ(EIO, tcnm_query_reduce(foundAfterError, sizeof(foundAfterError) / sizeof(foundAfterError[0]), &found));
    EXPECT_TRUE(!found);

    const tcnm_query_observation foundBeforeUnreadNode[] = {
        {.status = 0, .found = true},
        {.status = EIO, .found = false},
    };
    EXPECT_EQ(0,
              tcnm_query_reduce(foundBeforeUnreadNode,
                                sizeof(foundBeforeUnreadNode) / sizeof(foundBeforeUnreadNode[0]),
                                &found));
    EXPECT_TRUE(found);
}

static void test_entries_relation(void) {
    uint8_t left[TEST_CAPACITY * TEST_STRIDE] = {0};
    uint8_t right[TEST_CAPACITY * TEST_STRIDE] = {0};
    tcnm_entry a = entry_with_leading_byte(0x20);
    tcnm_entry b = entry_with_leading_byte(0x40);
    tcnm_entry c = entry_with_leading_byte(0x60);

    encode_entry(left, 4, &a);
    encode_entry(left, 5, &b);
    encode_entry(right, 4, &a);
    encode_entry(right, 5, &b);
    EXPECT_EQ(TCNM_TABLE_RELATION_EQUAL, tcnm_entries_relation(left, right, TEST_CAPACITY, TEST_STRIDE));

    memset(left, 0, sizeof(left));
    encode_entry(left, 3, &a);
    encode_entry(left, 4, &b);
    encode_entry(left, 5, &c);
    EXPECT_EQ(TCNM_TABLE_RELATION_LEFT_STRICT_SUPERSET, tcnm_entries_relation(left, right, TEST_CAPACITY, TEST_STRIDE));
    EXPECT_EQ(TCNM_TABLE_RELATION_RIGHT_STRICT_SUPERSET,
              tcnm_entries_relation(right, left, TEST_CAPACITY, TEST_STRIDE));

    memset(right, 0, sizeof(right));
    tcnm_entry d = entry_with_leading_byte(0x80);
    encode_entry(right, 4, &a);
    encode_entry(right, 5, &d);
    EXPECT_EQ(TCNM_TABLE_RELATION_NONCOMPARABLE, tcnm_entries_relation(left, right, TEST_CAPACITY, TEST_STRIDE));

    memset(left, 0, sizeof(left));
    memset(right, 0, sizeof(right));
    encode_entry(left, 5, &a);
    b = a;
    b.flags++;
    encode_entry(right, 5, &b);
    EXPECT_EQ(TCNM_TABLE_RELATION_NONCOMPARABLE, tcnm_entries_relation(left, right, TEST_CAPACITY, TEST_STRIDE));

    memset(left, 0, sizeof(left));
    memset(right, 0, sizeof(right));
    encode_entry(left, 3, &a);
    encode_entry(left, 5, &c);
    encode_entry(right, 5, &a);
    EXPECT_EQ(TCNM_TABLE_RELATION_LEFT_INVALID, tcnm_entries_relation(left, right, TEST_CAPACITY, TEST_STRIDE));
    EXPECT_EQ(TCNM_TABLE_RELATION_RIGHT_INVALID, tcnm_entries_relation(right, left, TEST_CAPACITY, TEST_STRIDE));
    EXPECT_EQ(TCNM_TABLE_RELATION_BOTH_INVALID, tcnm_entries_relation(left, left, TEST_CAPACITY, TEST_STRIDE));
    EXPECT_EQ(TCNM_TABLE_RELATION_UNREADABLE, tcnm_entries_relation(NULL, right, TEST_CAPACITY, TEST_STRIDE));
}

static tcnm_ab_recovery_action decide_ab(tcnm_bank_pointer nodeA,
                                         tcnm_bank_pointer nodeB,
                                         tcnm_table_relation relation,
                                         bool detachedBankKnown,
                                         bool bank0Ready,
                                         bool bank1Ready) {
    tcnm_ab_observed_state state = {
        .nodeA = nodeA,
        .nodeB = nodeB,
        .relation = relation,
        .readComplete = true,
        .geometryExact = true,
        .typesShared = true,
        .detachedBankKnown = detachedBankKnown,
        .bank0Ready = bank0Ready,
        .bank1Ready = bank1Ready,
    };
    return tcnm_ab_recovery_decide(&state);
}

static void test_ab_recovery_table(void) {
    typedef struct {
        tcnm_table_relation relation;
        tcnm_ab_recovery_action split;
        tcnm_ab_recovery_action collapsedBank0;
        tcnm_ab_recovery_action collapsedBank1;
    } recovery_case;
    const recovery_case cases[] = {
        {
            TCNM_TABLE_RELATION_EQUAL,
            TCNM_AB_RECOVERY_ACCEPT_READY,
            TCNM_AB_RECOVERY_PUBLISH_BANK1,
            TCNM_AB_RECOVERY_PUBLISH_BANK0,
        },
        {
            TCNM_TABLE_RELATION_LEFT_STRICT_SUPERSET,
            TCNM_AB_RECOVERY_ACCEPT_READY,
            TCNM_AB_RECOVERY_REBUILD_BANK1_FROM_BANK0,
            TCNM_AB_RECOVERY_PUBLISH_BANK0,
        },
        {
            TCNM_TABLE_RELATION_RIGHT_STRICT_SUPERSET,
            TCNM_AB_RECOVERY_ACCEPT_READY,
            TCNM_AB_RECOVERY_PUBLISH_BANK1,
            TCNM_AB_RECOVERY_REBUILD_BANK0_FROM_BANK1,
        },
        {
            TCNM_TABLE_RELATION_NONCOMPARABLE,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
        },
        {
            TCNM_TABLE_RELATION_LEFT_INVALID,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_REBUILD_BANK0_FROM_BANK1,
        },
        {
            TCNM_TABLE_RELATION_RIGHT_INVALID,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_REBUILD_BANK1_FROM_BANK0,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
        },
        {
            TCNM_TABLE_RELATION_BOTH_INVALID,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
            TCNM_AB_RECOVERY_FAIL_CLOSED,
        },
        {
            TCNM_TABLE_RELATION_UNREADABLE,
            TCNM_AB_RECOVERY_RETRY,
            TCNM_AB_RECOVERY_RETRY,
            TCNM_AB_RECOVERY_RETRY,
        },
    };

    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        EXPECT_EQ(cases[index].split,
                  decide_ab(TCNM_BANK_POINTER_BANK0,
                            TCNM_BANK_POINTER_BANK1,
                            cases[index].relation,
                            false,
                            true,
                            true));
        EXPECT_EQ(cases[index].split,
                  decide_ab(TCNM_BANK_POINTER_BANK1,
                            TCNM_BANK_POINTER_BANK0,
                            cases[index].relation,
                            false,
                            true,
                            true));
        EXPECT_EQ(cases[index].collapsedBank0,
                  decide_ab(TCNM_BANK_POINTER_BANK0, TCNM_BANK_POINTER_BANK0, cases[index].relation, true, true, true));
        EXPECT_EQ(cases[index].collapsedBank1,
                  decide_ab(TCNM_BANK_POINTER_BANK1, TCNM_BANK_POINTER_BANK1, cases[index].relation, true, true, true));

        tcnm_ab_recovery_action withoutDetached = cases[index].relation == TCNM_TABLE_RELATION_UNREADABLE
            ? TCNM_AB_RECOVERY_RETRY
            : TCNM_AB_RECOVERY_FAIL_CLOSED;
        EXPECT_EQ(withoutDetached,
                  decide_ab(TCNM_BANK_POINTER_BANK0,
                            TCNM_BANK_POINTER_BANK0,
                            cases[index].relation,
                            false,
                            true,
                            true));
    }

    EXPECT_EQ(TCNM_AB_RECOVERY_REBUILD_BANK1_FROM_BANK0,
              decide_ab(TCNM_BANK_POINTER_BANK0,
                        TCNM_BANK_POINTER_BANK0,
                        TCNM_TABLE_RELATION_RIGHT_STRICT_SUPERSET,
                        true,
                        true,
                        false));
    EXPECT_EQ(TCNM_AB_RECOVERY_REBUILD_BANK1_FROM_BANK0,
              decide_ab(TCNM_BANK_POINTER_BANK0,
                        TCNM_BANK_POINTER_BANK0,
                        TCNM_TABLE_RELATION_NONCOMPARABLE,
                        true,
                        true,
                        false));
    EXPECT_EQ(TCNM_AB_RECOVERY_FAIL_CLOSED,
              decide_ab(TCNM_BANK_POINTER_BANK0,
                        TCNM_BANK_POINTER_BANK0,
                        TCNM_TABLE_RELATION_EQUAL,
                        true,
                        false,
                        true));
    EXPECT_EQ(TCNM_AB_RECOVERY_FAIL_CLOSED,
              decide_ab(TCNM_BANK_POINTER_BANK0,
                        TCNM_BANK_POINTER_BANK1,
                        TCNM_TABLE_RELATION_EQUAL,
                        false,
                        true,
                        false));

    EXPECT_EQ(TCNM_BANK_POINTER_BANK0,
              tcnm_bank_pointer_classify(0, UINT64_C(0x1000), UINT64_C(0x1000), UINT64_C(0x2000)));
    EXPECT_EQ(TCNM_BANK_POINTER_BANK1,
              tcnm_bank_pointer_classify(0, UINT64_C(0x2000), UINT64_C(0x1000), UINT64_C(0x2000)));
    EXPECT_EQ(TCNM_BANK_POINTER_FOREIGN,
              tcnm_bank_pointer_classify(0, UINT64_C(0x3000), UINT64_C(0x1000), UINT64_C(0x2000)));
    EXPECT_EQ(TCNM_BANK_POINTER_UNREADABLE, tcnm_bank_pointer_classify(EIO, 0, UINT64_C(0x1000), UINT64_C(0x2000)));

    tcnm_ab_observed_state invalidState = {
        .nodeA = TCNM_BANK_POINTER_BANK0,
        .nodeB = TCNM_BANK_POINTER_BANK1,
        .relation = TCNM_TABLE_RELATION_EQUAL,
        .readComplete = false,
        .geometryExact = true,
        .typesShared = true,
        .bank0Ready = true,
        .bank1Ready = true,
    };
    EXPECT_EQ(TCNM_AB_RECOVERY_RETRY, tcnm_ab_recovery_decide(&invalidState));
    invalidState.readComplete = true;
    invalidState.geometryExact = false;
    EXPECT_EQ(TCNM_AB_RECOVERY_FAIL_CLOSED, tcnm_ab_recovery_decide(&invalidState));
    invalidState.geometryExact = true;
    invalidState.typesShared = false;
    EXPECT_EQ(TCNM_AB_RECOVERY_FAIL_CLOSED, tcnm_ab_recovery_decide(&invalidState));
    invalidState.typesShared = true;
    invalidState.nodeA = TCNM_BANK_POINTER_FOREIGN;
    EXPECT_EQ(TCNM_AB_RECOVERY_FAIL_CLOSED, tcnm_ab_recovery_decide(&invalidState));
}

int main(void) {
    test_entries_decode_and_validate();
    test_entries_merge_regression();
    test_v2_merge_preserves_existing_constraint_bytes();
    test_marker_crc_parse_and_damage_detection();
    test_observed_state_and_recovery_table();
    test_query_policy();
    test_entries_relation();
    test_ab_recovery_table();

    if (gFailureCount) {
        fprintf(stderr, "trustcache_nokcall_model: %u failure(s)\n", gFailureCount);
        return EXIT_FAILURE;
    }
    printf("trustcache_nokcall_model: all tests passed\n");
    return EXIT_SUCCESS;
}
