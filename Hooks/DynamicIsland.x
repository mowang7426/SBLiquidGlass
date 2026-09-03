// Dynamic Island - 参考 Liquidify 实现
// 只在 SpringBoard 里加液态玻璃，不碰任何内容视图（专辑封面等）
// 黑色背景由 DIContentClear.x 在内容进程里清除

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static NSString *kDILogPath = @"/var/mobile/Documents/di_native_log.txt";

#pragma mark - 日志工具

static void diLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[DI-Native] %@", msg);
        NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kDILogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:kDILogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:kDILogPath];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kDILogPath error:nil];
        });
        
        diLog(@"=== diApplyGlassToRoot called ===");
        diLog(@"root.frame=%@ root.bounds=%@",
              NSStringFromCGRect(root.frame), NSStringFromCGRect(root.bounds));
        
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;
        
        // 玻璃层 frame 直接用 root.bounds（最准确，不会有坐标系偏移）
        CGRect glassFrame = root.bounds;
        diLog(@"Glass frame: %@", NSStringFromCGRect(glassFrame));
        
        // 创建或获取液态玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
            glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;
            // 插到最底层，在内容下面
            [root insertSubview:glass atIndex:0];
            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            diLog(@"Glass attached, frame=%@", NSStringFromCGRect(glassFrame));
        }
        
        // 同步玻璃层的 frame 和 cornerRadius
        glass.frame = glassFrame;
        CGFloat radius = root.layer.cornerRadius;
        if (radius <= 0) radius = CGRectGetHeight(glassFrame) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 确保玻璃层在最底层
        if ([root.subviews indexOfObject:glass] != 0) {
            [root insertSubview:glass atIndex:0];
        }
        
        diLog(@"Glass updated: frame=%@ cornerRadius=%.1f",
              NSStringFromCGRect(glass.frame), glass.layer.cornerRadius);
        
    } @catch (NSException *e) {
        diLog(@"EXCEPTION: %@", e);
    }
}

static void diRemoveGlass(SBSystemApertureContainerView *root) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (glass) [glass removeFromSuperview];
        objc_setAssociatedObject(root, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView
- (void)didMoveToWindow {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
    else diRemoveGlass(self);
}
- (void)layoutSubviews {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
}
%end
