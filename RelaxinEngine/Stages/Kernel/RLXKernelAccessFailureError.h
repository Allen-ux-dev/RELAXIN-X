//
//  RLXKernelAccessFailureError.h
//  RelaxinEngine
//
//  Where a kernel-access failure becomes an engine error.
//

#import <Foundation/Foundation.h>

@class RLXKernelAccessFailure;

NS_ASSUME_NONNULL_BEGIN

/**
 * Turns what KernelAccess reported into the error the engine publishes.
 *
 * KernelAccess sits below Engine, so it states failures in its own terms and
 * never builds an `RLXEngineError`. The stage is the first layer that can see
 * both, which makes it the only place the error code is chosen and the only
 * place the two vocabularies meet.
 */
NSError *rlx_engine_error_from_kernel_access_failure(RLXKernelAccessFailure *failure);

NS_ASSUME_NONNULL_END
