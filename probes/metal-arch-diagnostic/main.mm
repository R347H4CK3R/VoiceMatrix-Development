#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <string>

@interface ArchProbeDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ArchProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTLArchitecture *architecture = device.architecture;
    NSString *name = architecture.name;
    // ObjC dispatch is the equivalent of the exact metal-cpp selector chain.
    const char *raw = name.UTF8String;
    const BOOL reproduce = [NSProcessInfo.processInfo.arguments containsObject:@"--reproduce"];
    fprintf(stdout, "METAL_ARCH_PROBE device=%d architecture=%d name=%d utf8=%d apple7=%d reproduce=%d\n",
            !!device, !!architecture, !!name, !!raw, !![device supportsFamily:MTLGPUFamilyApple7], !!reproduce);
    fflush(stdout);
    if (reproduce) {
        // Exact NULL-sensitive std::string operation in pinned MLX's Device constructor.
        std::string architectureString(raw);
        fprintf(stdout, "METAL_ARCH_CONSTRUCTOR_RETURNED length=%zu\n", architectureString.size());
        fflush(stdout);
    }
    // This disposable app has nothing to render. Let launch finish then exit
    // so simctl's console waits for a bounded process and returns normally.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        exit(0);
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ArchProbeDelegate.class));
    }
}
