#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#include <string>

@interface ArchProbeDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ArchProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    BOOL reproduce = [arguments containsObject:@"--constructor"];
    if (!reproduce && ![arguments containsObject:@"--guarded"]) { return YES; }
    if (!documents) { return YES; }
    [NSFileManager.defaultManager createDirectoryAtURL:documents withIntermediateDirectories:YES
                                           attributes:nil error:nullptr];
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTLArchitecture *architecture = device.architecture;
    NSString *name = architecture.name;
    // ObjC dispatch is the equivalent of the exact metal-cpp selector chain.
    const char *raw = name.UTF8String;
    NSDictionary *inputs = @{@"hasDevice": @(device != nil), @"hasArchitecture": @(architecture != nil),
                              @"hasName": @(name != nil), @"hasUTF8": @(raw != nullptr),
                              @"apple7": @([device supportsFamily:MTLGPUFamilyApple7] != NO),
                              @"reproduce": @(reproduce)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:inputs options:0 error:nullptr];
    NSURL *measured = [documents URLByAppendingPathComponent:
                       (reproduce ? @"constructor-inputs.json" : @"guarded-inputs.json")];
    if (![data writeToURL:measured options:NSDataWritingAtomic error:nullptr]) { return YES; }
    if (reproduce) {
        // Exact NULL-sensitive std::string operation in pinned MLX's Device constructor.
        std::string architectureString(raw);
        NSData *proof = [NSJSONSerialization dataWithJSONObject:@{@"returned": @YES,
                                                                   @"length": @(architectureString.size())}
                                                       options:0 error:nullptr];
        [proof writeToURL:[documents URLByAppendingPathComponent:@"constructor-returned.json"]
                  options:NSDataWritingAtomic error:nullptr];
    }
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ArchProbeDelegate.class));
    }
}
