#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

#pragma mark - 通知横幅深灰色半透明磨砂玻璃效果（Mango风格）

static void *kLGBannerDarkOverlayKey = &kLGBannerDarkOverlayKey;

static void LGApplyBannerDarkFrostedEffect(UIView *material, BOOL isTopBanner) {
    @try {
        if (!material || !material.superview) return;
        
        // 只对顶部横幅（Banner）应用效果，通知中心的通知保持原样
        if (!isTopBanner) return;
        
        UIView *parent = material.superview;
        
        // 查找或创建深灰色半透明叠加层
        UIView *darkOverlay = objc_getAssociatedObject(material, kLGBannerDarkOverlayKey);
        if (!darkOverlay) {
            darkOverlay = [[UIView alloc] initWithFrame:material.bounds];
            darkOverlay.userInteractionEnabled = NO;
            darkOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            objc_setAssociatedObject(material, kLGBannerDarkOverlayKey, darkOverlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        
        // 深灰色半透明背景（更透明，参考用户效果）
        // alpha 0.35 可以更清楚地看到后面的内容
        CGFloat alpha = 0.35;
        @try {
            id alphaValue = LGGlassPreferenceValue(@"Banner.DarkOverlay.Alpha");
            if (alphaValue && [alphaValue respondsToSelector:@selector(floatValue)]) {
                alpha = [alphaValue floatValue];
            }
        } @catch (__unused NSException *e) {}
        
        darkOverlay.backgroundColor = [UIColor colorWithWhite:0.08 alpha:alpha];
        darkOverlay.frame = material.bounds;
        darkOverlay.layer.cornerRadius = material.layer.cornerRadius > 0 ? material.layer.cornerRadius : 22.0;
        darkOverlay.layer.cornerCurve = kCACornerCurveContinuous;
        darkOverlay.layer.masksToBounds = YES;
        // 添加白色边框（参考用户效果）
        darkOverlay.layer.borderWidth = 1.0;
        darkOverlay.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        
        // 把叠加层放在液态玻璃上面，内容下面
        if (darkOverlay.superview != parent) {
            [parent insertSubview:darkOverlay aboveSubview:material];
        }
        
        // 确保原始 MTMaterialView 是透明的，让液态玻璃显示出来
        material.backgroundColor = [UIColor clearColor];
        if (material.layer.backgroundColor) {
            material.layer.backgroundColor = [UIColor clearColor].CGColor;
        }
        
        // 遍历子视图，清除不透明的背景
        for (UIView *sub in [material.subviews copy]) {
            if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                UIVisualEffectView *ev = (UIVisualEffectView *)sub;
                ev.effect = nil;
            }
        }
        
        NSLog(@"[SBLiquidGlass-Banner] Dark frosted effect applied (alpha=%.2f)", alpha);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-Banner] Dark frosted exception: %@", e);
    }
}

static BOOL LGHasMaterialAncestorBefore(UIView *material, NSString *stopClassName) {
    Class stopCls = NSClassFromString(stopClassName);
    Class materialClass = NSClassFromString(@"MTMaterialView");
    for (UIView *v = material.superview; v; v = v.superview) {
        if (stopCls && [v isKindOfClass:stopCls]) return NO;
        if (materialClass && [v isKindOfClass:materialClass]) return YES;
    }
    return NO;
}

static BOOL LGIsPlatterMaterial(UIView *material) {
    if (!hasAncestorOfClassName(material, @"PLPlatterView")) return NO;
    if (hasAncestorOfClassName(material, @"SBSwitcherAppSuggestionBannerView")) return NO;
    return !LGHasMaterialAncestorBefore(material, @"PLPlatterView");
}

static BOOL LGIsPlatterActionMaterial(UIView *material) {
    if (!hasAncestorOfClassName(material, @"PLPlatterActionButton")) return NO;
    if (hasAncestorOfClassName(material, @"SBSwitcherAppSuggestionBannerView")) return NO;
    return !LGHasMaterialAncestorBefore(material, @"PLPlatterActionButton");
}

static BOOL LGResponderChainContainsClass(UIResponder *responder, NSString *name) {
    Class cls = NSClassFromString(name);
    for (UIResponder *r = responder; r; r = r.nextResponder)
        if (cls && [r isKindOfClass:cls]) return YES;
    return NO;
}

static void *kLGPlatterClassificationKey = &kLGPlatterClassificationKey;
static void *kLGNotificationAdaptiveOverlayKey = &kLGNotificationAdaptiveOverlayKey;

// 通知中心背景自适应：根据深浅色模式叠加半透明遮罩，增强文字可读性
static void LGUpdateNotificationAdaptiveOverlay(UIView *material) {
    @try {
        UIView *parent = material.superview;
        if (!parent) return;

        BOOL enabled = [LGGlassPreferenceValue(@"Notification.BackgroundAdaptive") floatValue] > 0.5;
        UIView *overlay = objc_getAssociatedObject(material, kLGNotificationAdaptiveOverlayKey);

        if (!enabled) {
            if (overlay) {
                [overlay removeFromSuperview];
                objc_setAssociatedObject(material, kLGNotificationAdaptiveOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return;
        }

        if (!overlay) {
            overlay = [[UIView alloc] initWithFrame:material.bounds];
            overlay.userInteractionEnabled = NO;
            overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            objc_setAssociatedObject(material, kLGNotificationAdaptiveOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        // 从用户偏好读取透明度，默认 0.12
        CGFloat alpha = 0.12;
        @try {
            id alphaValue = LGGlassPreferenceValue(@"Notification.BackgroundAlpha");
            if (alphaValue && [alphaValue respondsToSelector:@selector(floatValue)]) {
                alpha = [alphaValue floatValue];
            }
        } @catch (__unused NSException *e) {}

        // 浅色模式叠加白色，深色模式叠加黑色，增强文字对比度
        if (material.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
            overlay.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
        } else {
            overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:alpha];
        }

        overlay.frame = material.frame;
        if (overlay.superview != parent) {
            [parent insertSubview:overlay aboveSubview:material];
        }
    } @catch (NSException *e) {}
}

static BOOL LGIsTopBannerPresentation(UIView *view) {
    if (!view.window) return NO;
    if ([NSStringFromClass(view.window.class) isEqualToString:@"SBBannerWindow"]) return YES;
    if (hasAncestorOfClassName(view, @"BNContentViewControllerView")) return YES;
    if (LGResponderChainContainsClass(view, @"BNContentViewController")) return YES;
    return LGResponderChainContainsClass(view, @"SBNotificationPresentableViewController");
}

static BOOL LGIsLightLockscreenNotificationView(UIView *view) {
    if (!view || LGIsTopBannerPresentation(view)) return NO;
    if (view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight) return NO;
    return hasAncestorOfClassName(view, @"NCNotificationShortLookView") ||
           hasAncestorOfClassName(view, @"NCNotificationLongLookView") ||
           hasAncestorOfClassName(view, @"PLPlatterView");
}

static UIColor *LGForcedPlatterTextColor(UIView *view) {
    if (!view || view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight) return nil;
    if (LGIsTopBannerPresentation(view)) return UIColor.blackColor;
    return LGIsLightLockscreenNotificationView(view) ? UIColor.whiteColor : nil;
}

static NSAttributedString *LGAttributedTextWithColor(NSAttributedString *text, UIColor *color) {
    if (!color) return text;
    if (!text.length) return text;
    NSMutableAttributedString *copy = [text mutableCopy];
    [copy addAttribute:NSForegroundColorAttributeName
                 value:color
                 range:NSMakeRange(0, copy.length)];
    return copy;
}

static void LGDisableLockscreenStackDimming(id controller) {
    // stack dimming belongs to notifications and not top banners
    if (!controller || LGIsTopBannerPresentation([controller isKindOfClass:[UIViewController class]]
                                                   ? ((UIViewController *)controller).view : nil)) return;
    @try {
        id preview = [controller valueForKey:@"viewForPreview"];
        UIView *dimming = [preview valueForKey:@"stackDimmingOverlayView"];
        if (!dimming) {
            id contentSizeManager = [controller valueForKey:@"contentSizeManagingView"];
            dimming = [contentSizeManager valueForKey:@"stackDimmingView"];
        }
        if (dimming) dimming.hidden = lgHostEnabled(@"Notification");
    } @catch (__unused NSException *exception) {

    }
}

static CGFloat LGActionButtonRadius(UIView *material) {
    UIView *button = material;
    for (UIView *v = material; v; v = v.superview)
        if ([NSStringFromClass(v.class) isEqualToString:@"PLPlatterActionButton"]) {
            button = v;
            break;
        }
    if (button.layer.cornerRadius > 0.5) return button.layer.cornerRadius;
    if (material.layer.cornerRadius > 0.5) return material.layer.cornerRadius;
    return CGRectGetHeight(button.bounds) * 0.5;
}

static void LGUpdatePlatterGlass(UIView *material) {
    // one platter class serves banners notifications and action buttons

    if (!material.window) return;

    if (LGIsPlatterMaterial(material)) {
        BOOL topBanner = LGIsTopBannerPresentation(material);
        NSString *prefix = topBanner ? @"Banner" : @"Notification";
        NSString *previous = objc_getAssociatedObject(material, kLGPlatterClassificationKey);
        if (previous && ![previous isEqualToString:prefix]) {
            LGRemoveGlassFromMaterial(material, kGlassKey);
        }
        if (![previous isEqualToString:prefix]) {
            objc_setAssociatedObject(material, kLGPlatterClassificationKey, prefix,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        LGInstallRegisteredGlassInMaterial(material, kGlassKey, prefix,
                                           UIEdgeInsetsZero, -1.0, nil);
        // 通知中心背景自适应（仅 Notification，不影响顶部横幅 Banner）
        if ([prefix isEqualToString:@"Notification"]) {
            LGUpdateNotificationAdaptiveOverlay(material);
        }
        // 顶部横幅应用深灰色半透明磨砂玻璃效果（Mango风格）
        if ([prefix isEqualToString:@"Banner"]) {
            LGApplyBannerDarkFrostedEffect(material, topBanner);
        }
    } else if (LGIsPlatterActionMaterial(material)) {

        LGInstallRegisteredGlassInMaterial(material, kGlassKey, @"Notification",
                                           UIEdgeInsetsZero,
                                           LGActionButtonRadius(material), nil);
    }
}

%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (self_.window) LGUpdatePlatterGlass(self_);
}
- (void)layoutSubviews {
    %orig;
    LGUpdatePlatterGlass((UIView *)self);
}
%end

%hook UILabel
- (void)setTextColor:(UIColor *)color {
    UIColor *forced = LGForcedPlatterTextColor((UIView *)self);
    if (forced) color = forced;
    %orig(color);
}
- (void)setAttributedText:(NSAttributedString *)text {
    text = LGAttributedTextWithColor(text, LGForcedPlatterTextColor((UIView *)self));
    %orig(text);
}
- (void)didMoveToWindow {
    %orig;
    UIColor *forced = LGForcedPlatterTextColor((UIView *)self);
    if (!forced) return;
    if (self.attributedText.length) self.attributedText = LGAttributedTextWithColor(self.attributedText, forced);
    self.textColor = forced;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    UIColor *forced = LGForcedPlatterTextColor((UIView *)self);
    if (!forced) return;
    if (self.attributedText.length) self.attributedText = LGAttributedTextWithColor(self.attributedText, forced);
    self.textColor = forced;
}
%end

%hook NCNotificationShortLookViewController
- (void)viewDidLoad {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LGDisableLockscreenStackDimming(self);
}
%end
