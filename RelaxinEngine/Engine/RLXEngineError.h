//
//  RLXEngineError.h
//  RelaxinEngine
//
//  The framework's single NSError factory.
//

#import <Foundation/Foundation.h>

#import "RLXEngine.h"
#import "../Diagnostic/RLXEngineDiagnostic.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Builds the `RLXEngineErrorDomain` errors every layer of the framework
 * reports.
 *
 * Each error carries the same four pieces of user info — description, failure
 * reason, recovery suggestion, and a rendered `RLXEngineDiagnostic` — plus an
 * optional underlying error. The domain, the codes, and the diagnostic key are
 * all ABI: the Swift app persists the code and parses the diagnostic, so this
 * type centralises how the payload is assembled without changing what it says.
 */
@interface RLXEngineError : NSObject

/// `failureReason` and `recoverySuggestion` may be nil; several stages report
/// only a description and a diagnostic, and omitting a key is not the same as
/// giving it an empty value.
+ (NSError *)errorWithCode:(RLXEngineErrorCode)code
               description:(NSString *)description
             failureReason:(nullable NSString *)failureReason
        recoverySuggestion:(nullable NSString *)recoverySuggestion
                diagnostic:(nullable RLXEngineDiagnostic *)diagnostic;

+ (NSError *)errorWithCode:(RLXEngineErrorCode)code
               description:(NSString *)description
             failureReason:(nullable NSString *)failureReason
        recoverySuggestion:(nullable NSString *)recoverySuggestion
                diagnostic:(nullable RLXEngineDiagnostic *)diagnostic
           underlyingError:(nullable NSError *)underlyingError;

/**
 * Returns a copy of `error` whose user info has been revised.
 *
 * The block receives the error's mutable user info; any `RLXEngineDiagnostic`
 * the caller re-renders must be written back under `RLXEngineDiagnosticKey`.
 * Domain and code are preserved, which is what lets the task queue stamp
 * failure context onto an error a stage already built.
 */
+ (NSError *)errorFromError:(NSError *)error
           revisingUserInfo:(void (^)(NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo))revision;

/**
 * Parses the diagnostic already attached to `error` back into a builder, so a
 * later layer can revise it structurally instead of by text substitution.
 * Returns an empty diagnostic when the error carries none.
 */
+ (RLXEngineDiagnostic *)diagnosticFromError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
