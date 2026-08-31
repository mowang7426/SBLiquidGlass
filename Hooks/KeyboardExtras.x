#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 键盘增强：自定义背景图片 + 强制暗色模式。
// 作为 Keyboard.x 的补充，不修改原有复杂渲染逻辑。

static void *kKeyboardBGKey = &kKeyboardBGKey;

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

static BOOL keyboardExtrasEnabled(void) {
    return lgHostEnabled(@"Keyboard");
}

#pragma mark - 自定义背景

static UIImage *loadKeyboardBackground(void) {
    NSString *bgFile = lgPrefString(@"Keyboard.BackgroundFile", @"");
    if (!bgFile.length) return nil;

    NSArray *searchPaths = @[
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject],
        [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"Liquidify/Backgrounds"],
    ];

    for (NSString *dir in searchPaths) {
        NSString *path = [dir stringByAppendingPathComponent:bgFile];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) return img;
        }
    }
    return nil;
}

static void applyKeyboardBackground(UIView *keyboardView) {
    if (!keyboardExtrasEnabled()) return;

    UIImage *bgImage = loadKeyboardBackground();
    UIImageView *bgView = objc_getAssociatedObject(keyboardView, kKeyboardBGKey);

    if (!bgImage) {
        [bgView removeFromSuperview];
        objc_setAssociatedObject(keyboardView, kKeyboardBGKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    if (!bgView) {
        bgView = [[UIImageView alloc] initWithFrame:keyboardView.bounds];
        bgView.contentMode = UIViewContentModeScaleAspectFill;
        bgView.clipsToBounds = YES;
        bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        bgView.userInteractionEnabled = NO;
        [keyboardView insertSubview:bgView atIndex:0];
        objc_setAssociatedObject(keyboardView, kKeyboardBGKey, bgView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    bgView.image = bgImage;
    bgView.frame = keyboardView.bounds;
    bgView.alpha = lgPrefFloat(@"Keyboard.BackgroundOpacity", 0.7);
    bgView.layer.cornerRadius = lgPrefFloat(@"Keyboard.CornerRadius", 30.0);
    bgView.layer.cornerCurve = kCACornerCurveContinuous;
    bgView.layer.masksToBounds = YES;
}

#pragma mark - 强制暗色模式

static void applyForceDarkMode(UIView *keyboardView) {
    if (!keyboardExtrasEnabled()) return;
    BOOL forceDark = lgPrefFloat(@"Keyboard.ForceDarkMode", 0.0) > 0.5;
    if (forceDark) {
        keyboardView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    } else {
        keyboardView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
}

#pragma mark - Hook

%hook UIKeyboard
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (self_.window) {
        applyKeyboardBackground(self_);
        applyForceDarkMode(self_);
    }
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    UIImageView *bgView = objc_getAssociatedObject(self_, kKeyboardBGKey);
    if (bgView) {
        bgView.frame = self_.bounds;
    }
}
%end

// 键盘布局容器也应用背景和暗色
%hook UIKeyboardLayoutStar
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (self_.window && self_.superview) {
        applyKeyboardBackground(self_.superview);
        applyForceDarkMode(self_.superview);
    }
}
%end
