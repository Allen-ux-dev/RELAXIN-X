//
//  RLXEngineDiagnostic.h
//  RelaxinEngine
//
//  Structured builder for the `key=value` diagnostic carried in
//  RLXEngineDiagnosticKey.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * An ordered sequence of diagnostic lines rendered as `key=value` separated by
 * newlines, with no trailing newline.
 *
 * The sequence is deliberately *not* a dictionary. A failing run appends a
 * cleanup block whose `phase` shadows the phase the stage already reported, and
 * both lines are meaningful — the diagnostic is a log of what happened, not a
 * description of final state. Duplicate keys are therefore preserved in the
 * order they were appended.
 *
 * The rendered form crosses the framework boundary into
 * `EngineSession+FailureReport.swift`, so it is a contract: this type exists to
 * build that string, never to redefine it.
 */
@interface RLXEngineDiagnostic : NSObject

+ (instancetype)diagnostic;

/// Convenience for the near-universal opening line, `stage=<stage>`.
+ (instancetype)diagnosticWithStage:(NSString *)stage;

#pragma mark - Appending

/// Appends `key=value`. An existing entry with the same key is left alone.
- (void)appendKey:(NSString *)key value:(NSString *)value;
/// Appends `key=true` or `key=false`.
- (void)appendKey:(NSString *)key boolValue:(BOOL)value;
/// Appends `key=<decimal>`.
- (void)appendKey:(NSString *)key integerValue:(NSInteger)value;
/// Appends `key=0x<hex>`.
- (void)appendKey:(NSString *)key hexValue:(unsigned int)value;
/// Appends `key=0x<hex>` for the 64-bit values — kernel addresses, slides, and
/// sizes — that most of the framework's diagnostics are made of.
- (void)appendKey:(NSString *)key hex64Value:(uint64_t)value;

/// Appends `key=value`, or `key=<fallback>` when `value` is nil.
- (void)appendKey:(NSString *)key value:(nullable NSString *)value fallback:(NSString *)fallback;

/**
 * Appends an already-rendered diagnostic, splitting it back into entries so
 * that `containsKey:` and `setValue:forEveryKey:` see through it.
 *
 * An empty string appends one empty line, which is what concatenating it into
 * a `…\n%@` format produced before.
 */
- (void)appendRenderedDiagnostic:(NSString *)rendered;

#pragma mark - Recurring keys

- (void)appendStage:(NSString *)stage;
- (void)appendPhase:(NSString *)phase;
- (void)appendStatus:(int)status;
- (void)appendKernelStateMayBeDirty:(BOOL)dirty;

#pragma mark - Revision

/// Whether any entry carries this key, regardless of its value.
- (BOOL)containsKey:(NSString *)key;

/**
 * Rewrites the value of every entry carrying `key`, and does nothing when no
 * entry carries it.
 *
 * This replaces the text substitution the task queue used to perform on the
 * rendered string to flip `kernel_state_may_be_dirty` after a successful
 * cleanup, so it matches that substitution: absent means absent. A caller that
 * wants the key stated regardless pairs this with `containsKey:` and appends.
 */
- (void)setValue:(NSString *)value forEveryKey:(NSString *)key;
- (void)setBoolValue:(BOOL)value forEveryKey:(NSString *)key;

#pragma mark - Rendering

/// `key=value` lines joined by `\n`, with no trailing newline.
@property(nonatomic, readonly, copy) NSString *renderedValue;

@end

NS_ASSUME_NONNULL_END
