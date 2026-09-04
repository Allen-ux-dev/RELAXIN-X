//
//  RLXBootstrapPreparationError.h
//  RelaxinEngine
//
//  The one factory for bootstrap-preparation errors.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Builds the RLXEngineErrorCodeBootstrapPreparationFailed error every step of
 * bootstrap preparation reports.
 *
 * `phase` also selects the recovery suggestion, and it decides the
 * `filesystem_state_may_be_partial` diagnostic field: the three read-only
 * phases cannot have left anything half-written, everything else can.
 */
/* Internal to the framework's bootstrap layer. */
#pragma GCC visibility push(hidden)

/// The errno-style status an NSFileManager/NSError failure should report.
int rlx_status_for_error(NSError *_Nullable error);

NSError *rlx_bootstrap_preparation_error(NSString *phase,
                                         int status,
                                         NSString *_Nullable detail,
                                         NSError *_Nullable underlying);

#pragma GCC visibility pop

NS_ASSUME_NONNULL_END
