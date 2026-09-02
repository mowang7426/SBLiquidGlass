// Test25: Disable experimental Dynamic Island content/background clearing.
// Keep Apple's native Dynamic Island content completely untouched.
#import <UIKit/UIKit.h>

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test25] DI content clearing disabled");
}
