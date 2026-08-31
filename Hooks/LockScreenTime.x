#import <UIKit/UIKit.h>
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>
#import <CoreText/CoreText.h>

// 锁屏时间样式：自定义字体、字号、磨砂玻璃背景。
// 使用 UIVisualEffectView + UIBlurEffect（UIKit 标准 API），避免 CABackdropLayer 私有类崩溃。
// swizzle UILabel 的 didMoveToWindow / layoutSubviews，识别锁屏时间标签。

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
    if (![view isKindOfClass:[UILabel class]]) return NO;
    UILabel *label = (UILabel *)view;
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
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *fontPath = [docsPath stringByAppendingPathComponent:@"iOS26Clock-Bold.ttf"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        fontPath = [appSupport stringByAppendingPathComponent:@"Liquidify/iOS26Clock-Bold.ttf"];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        @try {
            NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
            if (provider) {
                CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
                if (cgFont) {
                    NSString *name = (__bridge_transfer NSString *)CGFontCopyPostScriptName(cgFont);
                    CTFontManagerRegisterGraphicsFont(cgFont, NULL);
                    UIFont *font = [UIFont fontWithName:name size:pointSize];
                    CGFontRelease(cgFont);
                    CGDataProviderRelease(provider);
                    if (font) return font;
                } else {
                    CGDataProviderRelease(provider);
                }
            }
        } @catch (__unused NSException *e) {}
    }
    return [UIFont systemFontOfSize:pointSize weight:UIFontWeightBold];
}

static void applyLockTimeStyle(UILabel *label) {
    if (!isLockScreenTimeLabel(label)) return;

    UIFont *originalFont = objc_getAssociatedObject(label, kLockTimeOriginalFontKey);
    if (!originalFont) {
        originalFont = label.font;
        objc_setAssociatedObject(label, kLockTimeOriginalFontKey, originalFont, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat scale = lgPrefFloat(@"LockScreenTime.FontSizeScale", 1.0);
    CGFloat baseSize = originalFont.pointSize;
    CGFloat newSize = baseSize * MAX(0.5, MIN(3.5, scale));
    label.font = lgLockTimeFont(newSize);

    CGFloat frostedOpacity = lgPrefFloat(@"LockScreenTime.FrostedGlassOpacity", 0.0);
    UIVisualEffectView *blurView = objc_getAssociatedObject(label, kLockTimeGlassKey);

    if (frostedOpacity > 0.01) {
        if (!blurView) {
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            blurView.layer.cornerRadius = 12.0;
            blurView.layer.cornerCurve = kCACornerCurveContinuous;
            blurView.clipsToBounds = YES;
            blurView.userInteractionEnabled = NO;
            if (label.superview) {
                [label.superview insertSubview:blurView belowSubview:label];
            }
            objc_setAssociatedObject(label, kLockTimeGlassKey, blurView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        blurView.frame = label.frame;
        blurView.alpha = frostedOpacity;
        blurView.hidden = NO;
    } else if (blurView) {
        blurView.hidden = YES;
    }
}

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
        UIVisualEffectView *blurView = objc_getAssociatedObject(label, kLockTimeGlassKey);
        if (blurView && !blurView.hidden) {
            blurView.frame = label.frame;
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
