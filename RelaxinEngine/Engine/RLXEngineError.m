//
//  RLXEngineError.m
//  RelaxinEngine
//

#import "RLXEngineError.h"

@implementation RLXEngineError

+ (NSError *)errorWithCode:(RLXEngineErrorCode)code
               description:(NSString *)description
             failureReason:(nullable NSString *)failureReason
        recoverySuggestion:(nullable NSString *)recoverySuggestion
                diagnostic:(nullable RLXEngineDiagnostic *)diagnostic {
    return [self errorWithCode:code description:description failureReason:failureReason
            recoverySuggestion:recoverySuggestion
                    diagnostic:diagnostic
               underlyingError:nil];
}

+ (NSError *)errorWithCode:(RLXEngineErrorCode)code
               description:(NSString *)description
             failureReason:(nullable NSString *)failureReason
        recoverySuggestion:(nullable NSString *)recoverySuggestion
                diagnostic:(nullable RLXEngineDiagnostic *)diagnostic
           underlyingError:(nullable NSError *)underlyingError {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = description;
    userInfo[NSLocalizedFailureReasonErrorKey] = failureReason;
    userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion;
    if (diagnostic) {
        userInfo[RLXEngineDiagnosticKey] = diagnostic.renderedValue;
    }
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:RLXEngineErrorDomain code:code userInfo:userInfo];
}

+ (NSError *)errorFromError:(NSError *)error
           revisingUserInfo:(void (^)(NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo))revision {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [error.userInfo mutableCopy]
        ?: [NSMutableDictionary dictionary];
    revision(userInfo);
    return [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
}

+ (RLXEngineDiagnostic *)diagnosticFromError:(NSError *)error {
    RLXEngineDiagnostic *diagnostic = [RLXEngineDiagnostic diagnostic];
    NSString *rendered = error.userInfo[RLXEngineDiagnosticKey];
    if (rendered.length > 0) {
        [diagnostic appendRenderedDiagnostic:rendered];
    }
    return diagnostic;
}

@end
