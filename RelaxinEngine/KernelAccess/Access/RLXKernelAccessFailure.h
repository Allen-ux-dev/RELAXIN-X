//
//  RLXKernelAccessFailure.h
//  RelaxinEngine
//
//  What a kernel-access failure knows, before anything turns it into an error.
//

#import <Foundation/Foundation.h>

@class RLXEngineDiagnostic;

NS_ASSUME_NONNULL_BEGIN

/**
 * Which of this layer's contracts the failure belongs to.
 *
 * KernelAccess sits below Engine and cannot name `RLXEngineErrorCode`, so it
 * states the kind in its own terms and the kernel stages map it one to one.
 *
 * There is deliberately no separate kind for the patchfinder. Everything the
 * XPF session reports reaches exactly one caller — the kernel-access build —
 * and one caller with one cleanup behaviour should not produce two engine error
 * codes depending on which branch inside it failed. The session states the
 * facts; `-failureByFoldingIntoKernelAccessBuild` is where the build says what
 * they mean for it.
 */
typedef NS_ENUM(NSInteger, RLXKernelAccessFailureKind) {
    RLXKernelAccessFailureKindAccessUnavailable,
    RLXKernelAccessFailureKindPrivilegeEscalation,
};

/**
 * Appends what one failure knows, on top of the fields its factory has already
 * opened.
 *
 * Taking a block rather than a rendered string keeps the ordering with the
 * factory and the `key=value` rendering in RLXEngineDiagnostic, instead of
 * putting the diagnostic format in every call site.
 */
typedef void (^RLXKernelAccessDiagnosticDetails)(RLXEngineDiagnostic *diagnostic);

/// An immutable statement of one failure: everything the stage above needs to
/// build an engine error, and nothing about how that error is shaped.
@interface RLXKernelAccessFailure : NSObject

@property(nonatomic, readonly) RLXKernelAccessFailureKind kind;
/// errno-style, or zero when the failure has no status of its own.
@property(nonatomic, readonly) int status;
@property(nonatomic, readonly, copy) NSString *failureDescription;
@property(nonatomic, readonly, copy, nullable) NSString *failureReason;
@property(nonatomic, readonly, copy) NSString *recoverySuggestion;
@property(nonatomic, readonly, strong) RLXEngineDiagnostic *diagnostic;

+ (instancetype)failureWithKind:(RLXKernelAccessFailureKind)kind
                         status:(int)status
                    description:(NSString *)description
                  failureReason:(nullable NSString *)failureReason
             recoverySuggestion:(NSString *)recoverySuggestion
                     diagnostic:(RLXEngineDiagnostic *)diagnostic;

/**
 * Restates a failure as one the kernel-access build reports.
 *
 * The XPF session runs after the exploit and cannot know that, so it builds its
 * failures with the kernel clean and says nothing about dirt. The build knows
 * both, and folds: the kind becomes access-unavailable, the recovery suggestion
 * becomes the reboot-first one, and `kernel_state_may_be_dirty` is stated in the
 * diagnostic — set rather than appended when the failure already carries it, so
 * the task queue's later rewrite still finds one field to correct.
 *
 * Takes over the receiver's diagnostic rather than copying it; a failure is
 * built once and consumed once, and the receiver is dropped here.
 */
- (RLXKernelAccessFailure *)failureByFoldingIntoKernelAccessBuild;

- (instancetype)init NS_UNAVAILABLE;

@end

/// The recovery suggestion every kernel-access failure attaches.
NSString *rlx_kernel_access_recovery_suggestion(BOOL kernelStateMayBeDirty);

/**
 * Builds the failure every stage of the kernel-access build reports.
 *
 * `kernelStateMayBeDirty` drives both the recovery suggestion and the
 * `kernel_state_may_be_dirty` diagnostic field the task queue later rewrites
 * once cleanup has run, so it is the caller's statement about whether the
 * kernel can still be left as it was found.
 */
RLXKernelAccessFailure *rlx_kernel_access_failure(NSString *phase,
                                                  int status,
                                                  NSString *reason,
                                                  BOOL kernelStateMayBeDirty,
                                                  RLXKernelAccessDiagnosticDetails _Nullable details);

NS_ASSUME_NONNULL_END
