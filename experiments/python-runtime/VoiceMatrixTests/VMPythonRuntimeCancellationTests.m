#import <XCTest/XCTest.h>
#import "VMPythonRuntime.h"
@protocol VMHarnessWebKit
- (void)evaluateScript:(NSString *)script inputJSON:(NSString *)input requestID:(NSString *)requestID completion:(void (^)(NSString *,NSError *))completion;
- (void)cancelRequest:(NSString *)requestID;
@end
// Run only in the isolated PythonRuntimeHarness host described in tests/runtime-harness/README.md.
@interface VMPythonRuntimeCancellationTests : XCTestCase
@end
@implementation VMPythonRuntimeCancellationTests
- (void)testValidPausedResolverCancellationAndNextRequestIsolation {
    NSString *valid=@"{\"schemaVersion\":1,\"authorized\":true}";
    __block void (^reply)(NSString *,NSError *);
    __block NSString *challengeID;
    __block XCTestExpectation *launched;
    __block NSUInteger launches=0;
    __block NSMutableArray<NSString *> *cancelled=[NSMutableArray new];
    id<VMHarnessWebKit> realProvider=(id<VMHarnessWebKit>)[NSClassFromString(@"VMWebKitChallengeProvider") new];
    XCTAssertNotNil(realProvider);
    VMPythonRuntime *runtime=[[VMPythonRuntime alloc] initWithJavaScriptEvaluator:
        ^(NSString *script,NSString *input,NSString *requestID,void (^completion)(NSString *,NSError *)) {
            XCTAssertTrue(NSThread.isMainThread);
            if ([script isEqualToString:@"return {bridge: 'native-webkit'};"]) {
                [realProvider evaluateScript:script inputJSON:input requestID:requestID completion:completion];return;
            }
            launches++;challengeID=requestID;reply=[completion copy];[launched fulfill];
            // Deliberately leave valid Python execution paused inside real vm_webkit.
        } canceller:^(NSString *requestID) { [cancelled addObject:requestID]; [realProvider cancelRequest:requestID]; }];

    // Cancel on main before its queued evaluator invocation can execute.
    XCTestExpectation *before=[self expectationWithDescription:@"cancel before launch"];
    NSString *early=[runtime resolveJSON:valid completion:^(NSString *result,NSError *error) {
        XCTAssertNil(result);XCTAssertNotNil(error);[before fulfill];
    }];
    [runtime cancelRequest:early];
    [self waitForExpectations:@[before] timeout:10];
    XCTAssertEqual(launches,0u);

    launched=[self expectationWithDescription:@"first valid resolver reaches bridge"];
    XCTestExpectation *done=[self expectationWithDescription:@"active cancellation finishes"];
    __block NSUInteger completions=0;
    NSString *first=[runtime resolveJSON:valid completion:^(NSString *result,NSError *error) {
        completions++;XCTAssertNil(result);XCTAssertNotNil(error);[done fulfill];
    }];
    [self waitForExpectations:@[launched] timeout:10];
    NSString *firstChallenge=[challengeID copy];
    void (^lateReply)(NSString *,NSError *)=[reply copy];
    [runtime cancelRequest:first];
    [self waitForExpectations:@[done] timeout:10];
    XCTAssertTrue([cancelled containsObject:firstChallenge]);
    lateReply(@"{\"status\":\"ready\"}",nil); // must not resurrect cancelled result

    launched=[self expectationWithDescription:@"next valid resolver reaches bridge"];
    XCTestExpectation *next=[self expectationWithDescription:@"next request succeeds"];
    [runtime resolveJSON:valid completion:^(NSString *result,NSError *error) {
        XCTAssertEqualObjects(result,@"{\"status\":\"ready\"}");XCTAssertNil(error);[next fulfill];
    }];
    [self waitForExpectations:@[launched] timeout:10];
    XCTAssertNotEqualObjects(challengeID,firstChallenge);
    [runtime cancelRequest:first]; // removal committed first completion; stale ID is inert
    XCTAssertFalse([cancelled containsObject:challengeID]);
    reply(@"{\"status\":\"ready\"}",nil);
    [self waitForExpectations:@[next] timeout:10];
    XCTAssertEqual(completions,1u);
    XCTestExpectation *smoke=[self expectationWithDescription:@"real CPython production imports and WebKit"];
    [runtime resolveJSON:@"{\"schemaVersion\":1,\"authorized\":true,\"mode\":\"native-production-smoke\"}" completion:^(NSString *result,NSError *error) {
        XCTAssertNil(error);XCTAssertNotNil(result);
        NSDictionary *data=result?[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
        XCTAssertEqualObjects(data[@"yt_dlp"],@"2026.10.26");
        XCTAssertEqualObjects(data[@"certifi"],@"2026.10.23");
        XCTAssertTrue([data[@"roots"] integerValue]>0);
        XCTAssertEqualObjects(data[@"verify"],@YES);XCTAssertEqualObjects(data[@"hostname"],@YES);
        XCTAssertEqualObjects(data[@"bridge"],@"native-webkit");
        XCTAssertEqualObjects(data[@"rejects_untrusted_tls"],@YES);[smoke fulfill];
    }];
    [self waitForExpectations:@[smoke] timeout:30];
}
@end
