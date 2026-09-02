// Test25: Disable the SBLiquidGlassDI experimental sub-tweak.
// Native Dynamic Island is left untouched for baseline testing.
#import <UIKit/UIKit.h>

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test25] SBLiquidGlassDI sub-tweak disabled");
}
