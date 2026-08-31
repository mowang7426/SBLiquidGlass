#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>
#import <CoreText/CoreText.h>

// 锁屏时间样式：自定义字体、字号、磨砂玻璃背景、模糊半径。
// hook 锁屏时间标签（SBUILabel / CSDateTimeView 内的标签）。

static void *kLockTimeGlassKey = &kLockTimeGlassKey;
static void *kLockTimeOriginalFontKey = &kLockTimeOriginalFontKey;

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

static NSString *lgPrefString(NSString *key, NSString *fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    return fallback;
}

static BOOL isLockScreenTimeLabel(UIView *view) {
    if (!lgHostEnabled(@"LockScreenTime")) return NO;
    // 锁屏时间标签通常是 SBUILabel 子类，且在 CSDateTimeView / SBDashBoard 内
    if (![view isKindOfClass:[UILabel class]]) return NO;
    UILabel *label = (UILabel *)view;
    // 时间标签字体通常很大（>40pt）
    if (label.font.pointSize < 30.0) return NO;
    if (hasAncestorOfClassName(view, @"CSDateTimeView")) return YES;
    if (hasAncestorOfClassName(view, @"CSCombinedDateTimeView")) return YES;
    if (hasAncestorOfClassName(view, @"SBDashBoardDateTimeLabel")) return YES;
    if (ancestorNameContains(view, @"DateTime")) return YES;
    return NO;
}

static UIFont *lgLockTimeFont(CGFloat pointSize) {
    NSString *fontName = lgPrefString(@"LockScreenTime.FontName", @"");
    if (fontName.length) {
        UIFont *custom = [UIFont fontWithName:fontName size:pointSize];
        if (custom) return custom;
    }
    // 尝试加载内置的 iOS26Clock 字体（如果存在）
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *fontPath = [docsPath stringByAppendingPathComponent:@"iOS26Clock-Bold.ttf"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        fontPath = [appSupport stringByAppendingPathComponent:@"Liquidify/iOS26Clock-Bold.ttf"];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
        CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
        if (cgFont) {
            NSString *name = (__bridge_transfer NSString *)CGFontCopyPostScriptName(cgFont);
            CTFontManagerRegisterGraphicsFont(cgFont, NULL);
            UIFont *font = [UIFont fontWithName:name size:pointSize];
            CGFontRelease(cgFont);
            CGDataProviderRelease(provider);
            if (font) return font;
        }
        CGDataProviderRelease(provider);
    }
    return [UIFont systemFontOfSize:pointSize weight:UIFontWeightBold];
}

static void applyLockTimeStyle(UILabel *label) {
    if (!isLockScreenTimeLabel(label)) return;

    // 保存原始字体
    UIFont *originalFont = objc_getAssociatedObject(label, kLockTimeOriginalFontKey);
    if (!originalFont) {
        originalFont = label.font;
        objc_setAssociatedObject(label, kLockTimeOriginalFontKey, originalFont, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 字号缩放
    CGFloat scale = lgPrefFloat(@"LockScreenTime.FontSizeScale", 1.0);
    CGFloat baseSize = originalFont.pointSize;
    CGFloat newSize = baseSize * MAX(0.5, MIN(3.5, scale));

    // 自定义字体
    label.font = lgLockTimeFont(newSize);

    // 磨砂玻璃背景
    CGFloat frostedOpacity = lgPrefFloat(@"LockScreenTime.FrostedGlassOpacity", 0.0);
    LGLiveBackdropView *glass = objc_getAssociatedObject(label, kLockTimeGlassKey);

    if (frostedOpacity > 0.01) {
        if (!glass) {
            glass = [[LGLiveBackdropView alloc] initWithFrame:label.bounds];
            glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            glass.layer.cornerRadius = 12.0;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.clipsToBounds = YES;
            glass.userInteractionEnabled = NO;
            [label.superview insertSubview:glass belowSubview:label];
            objc_setAssociatedObject(label, kLockTimeGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            lgTrackGlass(glass, @"LockScreenTime", label);
        }
        glass.frame = label.frame;
        glass.alpha = frostedOpacity;
        glass.hidden = NO;
    } else if (glass) {
        glass.hidden = YES;
    }
}

// 使用 method swizzling 而不是 %hook，因为需要同时处理多个标签类
@interface UILabel (LGLockTime)
@end

@implementation UILabel (LGLockTime)

- (void)lg_lockTimeDidMoveToWindow {
    [self lg_lockTimeDidMoveToWindow];
    if ([self isKindOfClass:[UILabel class]]) {
        applyLockTimeStyle((UILabel *)self);
    }
}

- (void)lg_lockTimeLayoutSubviews {
    [self lg_lockTimeLayoutSubviews];
    if ([self isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)self;
        LGLiveBackdropView *glass = objc_getAssociatedObject(label, kLockTimeGlassKey);
        if (glass && !glass.hidden) {
            glass.frame = label.frame;
        }
    }
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UILabel class];
        Method orig1 = class_getInstanceMethod(cls, @selector(didMoveToWindow));
        Method new1 = class_getInstanceMethod(cls, @selector(lg_lockTimeDidMoveToWindow));
        if (orig1 && new1) method_exchangeImplementations(orig1, new1);

        Method orig2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
        Method new2 = class_getInstanceMethod(cls, @selector(lg_lockTimeLayoutSubviews));
        if (orig2 && new2) method_exchangeImplementations(orig2, new2);
    });
}

@end
