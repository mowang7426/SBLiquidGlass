// Dynamic Island Test21 - 最简单的窗口半透明测试
// 只做一件事：让灵动岛窗口半透明，不加液态玻璃，先确认半透明能不能生效

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static NSString *kDILogPath = @"/var/mobile/Documents/di_native_log.txt";

#pragma mark - 日志工具

static void diLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[DI-Test] %@", msg);
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

#pragma mark - Hooks

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kDILogPath error:nil];
        });
        
        if (self.window && lgHostEnabled(@"DynamicIsland")) {
            diLog(@"=== Test21: Window alpha test ===");
            diLog(@"Before: window.alpha = %.2f", self.window.alpha);
            
            // 只做一件事：让窗口半透明
            self.window.alpha = 0.5;
            
            diLog(@"After: window.alpha = %.2f", self.window.alpha);
            diLog(@"root.frame = %@", NSStringFromCGRect(self.frame));
            diLog(@"root.subviews.count = %lu", (unsigned long)self.subviews.count);
        }
    } @catch (NSException *e) {
        diLog(@"EXCEPTION: %@", e);
    }
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (self.window && lgHostEnabled(@"DynamicIsland")) {
            // 每次 layout 都重新设置 alpha，防止被系统恢复
            self.window.alpha = 0.5;
        }
    } @catch (__unused NSException *e) {}
}

%end
