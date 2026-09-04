//
//  RLXEngineStageRegistry.m
//  RelaxinEngine
//

#import "RLXEngineStageRegistry.h"

#import "RLXEngineRunContext.h"
#import "RLXEngineTask.h"

#import "../Stages/Bootstrap/RLXBaseBinTrustTask.h"
#import "../Stages/Bootstrap/RLXBootstrapFinalizationTask.h"
#import "../Stages/Bootstrap/RLXBootstrapPreparationTask.h"
#import "../Stages/Removal/RLXBootstrapRemovalTask.h"
#import "../Stages/Support/RLXEngineMockTask.h"
#import "../Stages/Runtime/RLXJailbreakdCheckinTask.h"
#import "../Stages/Kernel/RLXKernelAccessAcquisitionTask.h"
#import "../Stages/Preflight/RLXKernelCacheAcquisitionTask.h"
#import "../Stages/Preflight/RLXKernelCacheLayoutAnalysisTask.h"
#import "../Stages/Runtime/RLXLaunchdHandoffTask.h"
#import "../Stages/Removal/RLXPostRemovalCleanupTask.h"
#import "../Stages/Kernel/RLXPrivilegeEscalationTask.h"
#import "../Stages/Runtime/RLXSystemHookActivationTask.h"
#import "../Stages/Preflight/RLXTargetConfirmationTask.h"
#import "../Stages/Runtime/RLXUserspaceRebootTask.h"

typedef struct {
    RLXEngineStage stage;
    __unsafe_unretained Class taskClass;
    RLXEngineStageBranch branches;
    /*
     * The simulator has no kernel to exploit, so these stages run as mocks
     * there. The rest run for real in both places.
     */
    BOOL simulatorMocked;
} RLXEngineStageEntry;

/*
 * Execution order, and the only place it is written down.
 *
 * This is deliberately not the declaration order of RLXEngineStage: that order
 * is ABI — Swift persists and compares the raw values — and it places the two
 * removal stages between LaunchdHandoff and JailbreakdCheckin. Reordering the
 * enum to match would break persisted state; reordering this table is how
 * execution order changes.
 */
static const RLXEngineStageEntry kStageTable[] = {
    {RLXEngineStageTargetConfirmation, Nil, RLXEngineStageBranchAll, YES},
    {RLXEngineStageKernelCacheAcquisition, Nil, RLXEngineStageBranchAll, YES},
    {RLXEngineStageKernelCacheLayoutAnalysis, Nil, RLXEngineStageBranchAll, YES},
    {RLXEngineStageKernelAccessAcquisition, Nil, RLXEngineStageBranchAll, YES},
    {RLXEngineStagePrivilegeEscalation, Nil, RLXEngineStageBranchAll, YES},

    {RLXEngineStageBootstrapRemoval, Nil, RLXEngineStageBranchRemoval, YES},
    {RLXEngineStagePostRemovalCleanup, Nil, RLXEngineStageBranchRemoval, NO},

    {RLXEngineStageBootstrapPreparation, Nil, RLXEngineStageBranchJailbreak, YES},
    {RLXEngineStageBaseBinTrust, Nil, RLXEngineStageBranchJailbreak, NO},
    {RLXEngineStageLaunchdHandoff, Nil, RLXEngineStageBranchJailbreak, NO},
    {RLXEngineStageJailbreakdCheckin, Nil, RLXEngineStageBranchJailbreak, NO},
    {RLXEngineStageSystemHookActivation, Nil, RLXEngineStageBranchJailbreak, NO},
    {RLXEngineStageBootstrapFinalization, Nil, RLXEngineStageBranchJailbreak, NO},
    {RLXEngineStageUserspaceReboot, Nil, RLXEngineStageBranchJailbreak, YES},
};

static const size_t kStageCount = sizeof(kStageTable) / sizeof(kStageTable[0]);

/*
 * Task classes cannot appear in a static initialiser, so the table carries Nil
 * and this resolves each one. Keeping the mapping beside the table keeps the
 * two in step.
 */
static Class rlx_task_class_for_stage(RLXEngineStage stage) {
    switch (stage) {
        case RLXEngineStageTargetConfirmation:
            return RLXTargetConfirmationTask.class;
        case RLXEngineStageKernelCacheAcquisition:
            return RLXKernelCacheAcquisitionTask.class;
        case RLXEngineStageKernelCacheLayoutAnalysis:
            return RLXKernelCacheLayoutAnalysisTask.class;
        case RLXEngineStageKernelAccessAcquisition:
            return RLXKernelAccessAcquisitionTask.class;
        case RLXEngineStagePrivilegeEscalation:
            return RLXPrivilegeEscalationTask.class;
        case RLXEngineStageBootstrapPreparation:
            return RLXBootstrapPreparationTask.class;
        case RLXEngineStageBaseBinTrust:
            return RLXBaseBinTrustTask.class;
        case RLXEngineStageLaunchdHandoff:
            return RLXLaunchdHandoffTask.class;
        case RLXEngineStageJailbreakdCheckin:
            return RLXJailbreakdCheckinTask.class;
        case RLXEngineStageSystemHookActivation:
            return RLXSystemHookActivationTask.class;
        case RLXEngineStageBootstrapFinalization:
            return RLXBootstrapFinalizationTask.class;
        case RLXEngineStageUserspaceReboot:
            return RLXUserspaceRebootTask.class;
        case RLXEngineStageBootstrapRemoval:
            return RLXBootstrapRemovalTask.class;
        case RLXEngineStagePostRemovalCleanup:
            return RLXPostRemovalCleanupTask.class;
    }
    return Nil;
}

@implementation RLXEngineStageRegistry

+ (NSArray<NSNumber *> *)stagesForRemoval:(BOOL)removeJailbreak {
    RLXEngineStageBranch branch = removeJailbreak ? RLXEngineStageBranchRemoval : RLXEngineStageBranchJailbreak;
    NSMutableArray<NSNumber *> *stages = [NSMutableArray array];
    for (size_t index = 0; index < kStageCount; index++) {
        if (kStageTable[index].branches & branch) {
            [stages addObject:@(kStageTable[index].stage)];
        }
    }
    return stages;
}

+ (BOOL)isSimulatorMockedStage:(RLXEngineStage)stage {
    for (size_t index = 0; index < kStageCount; index++) {
        if (kStageTable[index].stage == stage) {
            return kStageTable[index].simulatorMocked;
        }
    }
    return NO;
}

+ (NSArray<RLXEngineTask *> *)tasksForContext:(RLXEngineRunContext *)context {
    BOOL removeJailbreak = context.manifest[RLXEngineManifestRemoveJailbreakEnabledKey].boolValue;
    NSMutableArray<RLXEngineTask *> *tasks = [NSMutableArray array];
    for (NSNumber *boxedStage in [self stagesForRemoval:removeJailbreak]) {
        RLXEngineStage stage = (RLXEngineStage)boxedStage.integerValue;
#if TARGET_OS_SIMULATOR
        if ([self isSimulatorMockedStage:stage]) {
            [tasks addObject:[[RLXEngineMockTask alloc] initWithStage:stage context:context]];
            continue;
        }
#endif
        [tasks addObject:[[rlx_task_class_for_stage(stage) alloc] initWithContext:context]];
    }
    return tasks;
}

@end
