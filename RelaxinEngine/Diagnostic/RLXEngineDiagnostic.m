//
//  RLXEngineDiagnostic.m
//  RelaxinEngine
//

#import "RLXEngineDiagnostic.h"

/// One rendered line. `key` is nil for a line that carries no `=`.
__attribute__((visibility("hidden")))
@interface RLXEngineDiagnosticEntry : NSObject

@property(nonatomic, copy, nullable) NSString *key;
@property(nonatomic, copy) NSString *line;

@end

@implementation RLXEngineDiagnosticEntry
@end

@implementation RLXEngineDiagnostic {
    NSMutableArray<RLXEngineDiagnosticEntry *> *_entries;
}

+ (instancetype)diagnostic {
    return [[self alloc] init];
}

+ (instancetype)diagnosticWithStage:(NSString *)stage {
    RLXEngineDiagnostic *diagnostic = [self diagnostic];
    [diagnostic appendStage:stage];
    return diagnostic;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

#pragma mark - Appending

- (void)appendKey:(NSString *)key value:(NSString *)value {
    RLXEngineDiagnosticEntry *entry = [[RLXEngineDiagnosticEntry alloc] init];
    entry.key = key;
    entry.line = [NSString stringWithFormat:@"%@=%@", key, value];
    [_entries addObject:entry];
}

- (void)appendKey:(NSString *)key boolValue:(BOOL)value {
    [self appendKey:key value:value ? @"true" : @"false"];
}

- (void)appendKey:(NSString *)key integerValue:(NSInteger)value {
    [self appendKey:key value:[NSString stringWithFormat:@"%ld", (long)value]];
}

- (void)appendKey:(NSString *)key hexValue:(unsigned int)value {
    [self appendKey:key value:[NSString stringWithFormat:@"0x%x", value]];
}

- (void)appendKey:(NSString *)key hex64Value:(uint64_t)value {
    [self appendKey:key value:[NSString stringWithFormat:@"0x%llx", (unsigned long long)value]];
}

- (void)appendKey:(NSString *)key value:(nullable NSString *)value fallback:(NSString *)fallback {
    [self appendKey:key value:value ?: fallback];
}

- (void)appendRenderedDiagnostic:(NSString *)rendered {
    for (NSString *line in [rendered componentsSeparatedByString:@"\n"]) {
        RLXEngineDiagnosticEntry *entry = [[RLXEngineDiagnosticEntry alloc] init];
        NSRange separator = [line rangeOfString:@"="];
        entry.key = separator.location == NSNotFound ? nil : [line substringToIndex:separator.location];
        entry.line = line;
        [_entries addObject:entry];
    }
}

#pragma mark - Recurring keys

- (void)appendStage:(NSString *)stage {
    [self appendKey:@"stage" value:stage];
}

- (void)appendPhase:(NSString *)phase {
    [self appendKey:@"phase" value:phase];
}

- (void)appendStatus:(int)status {
    [self appendKey:@"status" integerValue:status];
}

- (void)appendKernelStateMayBeDirty:(BOOL)dirty {
    [self appendKey:@"kernel_state_may_be_dirty" boolValue:dirty];
}

#pragma mark - Revision

- (BOOL)containsKey:(NSString *)key {
    for (RLXEngineDiagnosticEntry *entry in _entries) {
        if ([entry.key isEqualToString:key]) {
            return YES;
        }
    }
    return NO;
}

- (void)setValue:(NSString *)value forEveryKey:(NSString *)key {
    for (RLXEngineDiagnosticEntry *entry in _entries) {
        if ([entry.key isEqualToString:key]) {
            entry.line = [NSString stringWithFormat:@"%@=%@", key, value];
        }
    }
}

- (void)setBoolValue:(BOOL)value forEveryKey:(NSString *)key {
    [self setValue:value ? @"true" : @"false" forEveryKey:key];
}

#pragma mark - Rendering

- (NSString *)renderedValue {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:_entries.count];
    for (RLXEngineDiagnosticEntry *entry in _entries) {
        [lines addObject:entry.line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@>", NSStringFromClass(self.class), self.renderedValue];
}

@end
