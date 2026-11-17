#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^VMJavaScriptEvaluator)(NSString *script, NSString *inputJSON, NSString *requestID,
                                      void (^completion)(NSString *_Nullable, NSError *_Nullable));
typedef void (^VMJavaScriptCanceller)(NSString *requestID);
/// App-owned single embedded interpreter, serialized off-main. Never executes a shell.
@interface VMPythonRuntime : NSObject
- (instancetype)initWithJavaScriptEvaluator:(VMJavaScriptEvaluator)evaluator
                                  canceller:(VMJavaScriptCanceller)canceller;
/// Returns identity immediately; cancellation is cooperative and suppresses late output.
- (NSString *)resolveJSON:(NSString *)request completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion;
- (void)cancelRequest:(NSString *)requestID;
@end
NS_ASSUME_NONNULL_END
