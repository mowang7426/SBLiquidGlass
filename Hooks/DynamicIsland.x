// Test25: Native Dynamic Island baseline.
// Experimental Dynamic Island hook disabled intentionally.
#import <UIKit/UIKit.h>

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test25] Dynamic Island hook disabled");
}
