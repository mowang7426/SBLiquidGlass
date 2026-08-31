#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 灵动岛液态玻璃：hook SBSystemApertureWindow / CCSystemApertureBackgroundDriver
// 内含的 MTMaterialView，注入 LGLiveBackdropView，并叠加 5 色渐变阴影。

static void *kDynamicIslandGlassKey = &kDynamicIslandGlassKey;
static void *kDynamicIslandGradientKey = &kDynamicIslandGradientKey;
static void *kDynamicIslandBackgroundKey = &kDynamicIslandBackgroundKey;

static BOOL isDynamicIslandMaterial(UIView *mat) {
    if (!isExactClass(mat, @"MTMaterialView")) return NO;
    // 灵动岛窗口内的材质
    if (hasAncestorOfClassName(mat, @"SBSystemApertureWindow")) return YES;
    if (hasAncestorOfClassName(mat, @"CCSystemApertureBackgroundDriver")) return YES;
    // 灵动岛展开态内容
    if (ancestorNameContains(mat, @"SystemAperture")) return YES;
    return NO;
}

static UIColor *lgColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]] || hex.length < 7) return nil;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex];
    if (![scanner scanHexInt:&rgb]) return nil;
    CGFloat a = (hex.length > 8) ? ((rgb >> 24) & 0xFF) / 255.0 : 1.0;
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static NSString *lgPref(NSString *key, NSString *fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    return fallback;
}

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

static void configureDynamicIslandGradient(UIView *glass) {
    if (!lgHostEnabled(@"DynamicIsland")) return;
    BOOL gradientEnabled = lgPrefFloat(@"DynamicIsland.GradientShadow", 1.0) > 0.5;
    CAGradientLayer *gradient = objc_getAssociatedObject(glass, kDynamicIslandGradientKey);

    if (!gradientEnabled) {
        [gradient removeFromSuperlayer];
        objc_setAssociatedObject(glass, kDynamicIslandGradientKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    if (!gradient) {
        gradient = [CAGradientLayer layer];
        gradient.startPoint = CGPointMake(0.0, 0.0);
        gradient.endPoint = CGPointMake(1.0, 1.0);
        gradient.cornerRadius = glass.layer.cornerRadius;
        gradient.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(glass, kDynamicIslandGradientKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [glass.layer addSublayer:gradient];
    }

    NSArray *hexColors = @[
        lgPref(@"DynamicIsland.GradientColor1", @"#FAFDFF"),
        lgPref(@"DynamicIsland.GradientColor2", @"#B8E8FF"),
        lgPref(@"DynamicIsland.GradientColor3", @"#9EB3FF"),
        lgPref(@"DynamicIsland.GradientColor4", @"#D1ABFF"),
        lgPref(@"DynamicIsland.GradientColor5", @"#FFC7F0"),
    ];
    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *hex in hexColors) {
        UIColor *c = lgColorFromHex(hex);
        if (c) [colors addObject:(id)c.CGColor];
    }
    gradient.colors = colors;
    gradient.opacity = lgPrefFloat(@"DynamicIsland.GradientOpacity", 0.35);
    gradient.frame = glass.bounds;
    gradient.cornerRadius = glass.layer.cornerRadius;
}

static void configureDynamicIslandBackground(UIView *material, UIView *glass) {
    NSString *bgFile = lgPref(@"DynamicIsland.BackgroundFile", @"");
    UIImageView *bgView = objc_getAssociatedObject(glass, kDynamicIslandBackgroundKey);

    if (!bgFile.length) {
        [bgView removeFromSuperview];
        objc_setAssociatedObject(glass, kDynamicIslandBackgroundKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *bgPath = [docsPath stringByAppendingPathComponent:bgFile];
    // 也检查 Application Support/Liquidify/Backgrounds
    if (![[NSFileManager defaultManager] fileExistsAtPath:bgPath]) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        bgPath = [appSupport stringByAppendingPathComponent:[@"Liquidify/Backgrounds" stringByAppendingPathComponent:bgFile]];
    }

    UIImage *bgImage = [UIImage imageWithContentsOfFile:bgPath];
    if (!bgImage) return;

    if (!bgView) {
        bgView = [[UIImageView alloc] initWithFrame:glass.bounds];
        bgView.contentMode = UIViewContentModeScaleAspectFill;
        bgView.clipsToBounds = YES;
        bgView.layer.cornerRadius = glass.layer.cornerRadius;
        bgView.layer.cornerCurve = kCACornerCurveContinuous;
        bgView.alpha = lgPrefFloat(@"DynamicIsland.BackgroundOpacity", 0.6);
        objc_setAssociatedObject(glass, kDynamicIslandBackgroundKey, bgView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [glass insertSubview:bgView atIndex:0];
    }
    bgView.image = bgImage;
    bgView.frame = glass.bounds;
    bgView.alpha = lgPrefFloat(@"DynamicIsland.BackgroundOpacity", 0.6);
}

static void injectDynamicIsland(UIView *material) {
    if (!lgHostEnabled(@"DynamicIsland")) return;

    LGLiveBackdropView *glass = (LGLiveBackdropView *)objc_getAssociatedObject(material, kDynamicIslandGlassKey);
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:material.bounds];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = material.layer.cornerRadius > 0 ? material.layer.cornerRadius : 22.0;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        [material insertSubview:glass atIndex:0];
        objc_setAssociatedObject(material, kDynamicIslandGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"DynamicIsland", material);
    }

    glass.frame = material.bounds;
    glass.layer.cornerRadius = material.layer.cornerRadius > 0 ? material.layer.cornerRadius : 22.0;
    glass.hidden = !lgHostEnabled(@"DynamicIsland");

    configureDynamicIslandGradient(glass);
    configureDynamicIslandBackground(material, glass);
}

%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (self_.window && isDynamicIslandMaterial(self_)) {
        injectDynamicIsland(self_);
    }
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (isDynamicIslandMaterial(self_)) {
        injectDynamicIsland(self_);
    }
}
%end

// 隐藏灵动岛选项
%hook SBSystemApertureWindow
- (void)didMoveToWindow {
    %orig;
    BOOL hide = lgPrefFloat(@"DynamicIsland.Hide", 0.0) > 0.5;
    if (hide && lgHostEnabled(@"DynamicIsland")) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}
%end

%ctor {
    // 灵动岛使用独立注入路径（非 LGRegisterMaterialHost），因为需要渐变层和自定义背景
    lgObservePreferenceReload(^{
        // 偏好变更时刷新已注入的灵动岛玻璃
    });
}
