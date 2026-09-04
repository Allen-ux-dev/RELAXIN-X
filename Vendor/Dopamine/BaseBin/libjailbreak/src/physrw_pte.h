#ifndef PHYSRW_PTE_H
#define PHYSRW_PTE_H

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

typedef struct {
    uint64_t cacheHits;
    uint64_t freshSlotAssignments;
    uint64_t reclaimedSlotAssignments;
    uint64_t reclaimAttempts;
    uint64_t reclaimSuccesses;
    uint64_t reclaimFailures;
    uint64_t acquireFailures;
    uint64_t generationBuildAttempts;
    uint64_t generationBuildFailures;
    uint64_t generationRotations;
    uint64_t generationRetirementFailures;
    uint64_t activeGenerationSlotsUsed;
    uint64_t activeGenerationCapacity;
    uint64_t standbyGenerationReady;
    uint64_t lastFailedPhysicalAddress;
    int32_t lastReclaimGroup;
    int32_t lastReclaimStatus;
    int32_t lastReclaimMachStatus;
    uint32_t lastReclaimStage;
} physrw_pte_diagnostics;

int physrw_pte_preseed(uint64_t *pageTableVirtualAddressOut);
int physrw_pte_handoff(pid_t pid, uint64_t pageTableVirtualAddress, uint64_t *swAsidPtr);
int libjailbreak_physrw_pte_init(bool receivedHandoff, uint64_t asidPtr);
int physrw_pte_prepare_standby_generation(void);
int physrw_pte_copy_diagnostics(physrw_pte_diagnostics *diagnosticsOut);

#endif
