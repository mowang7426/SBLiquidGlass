#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, LGDockMode) {
    LGDockModeNone = 0,
    LGDockModeRegular,
    LGDockModeFloating,
};

static const void *kDockHomeButtonBorderKey = &kDockHomeButtonBorderKey;

static BOOL dockInsideCategoryStackBackground(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"StackViewBackground"])
            return YES;
    }
    return NO;
}

static LGDockMode dockModeForMaterial(UIView *material) {
    // each dock family exposes different host geometry
    if (!isExactClass(material, @"MTMaterialView") ||
        dockInsideCategoryStackBackground(material)) return LGDockModeNone;

    CGSize size = material.bounds.size;
    if (size.width < 160.0 || size.height < 40.0) return LGDockModeNone;

    if (hasAncestorOfClassName(material, @"SBFloatingDockPlatterView") &&
        size.width >= size.height * 2.0) {
        return LGDockModeFloating;
    }
    if (hasAncestorOfClassName(material, @"SBDockView")) {
        return LGDockModeRegular;
    }
    return LGDockModeNone;
}

static BOOL dockIsFullScreenPhone(UIView *material) {
    UIEdgeInsets safeArea = material.window.safeAreaInsets;
    return safeArea.top > 20.0 || safeArea.bottom > 0.0;
}

static void dockUpdateHomeButtonBorder(LGLiveBackdropView *glass,
                                       BOOL needsBorder) {
    CAShapeLayer *border =
        objc_getAssociatedObject(glass, kDockHomeButtonBorderKey);
    if (!needsBorder) {
        [border removeFromSuperlayer];
        objc_setAssociatedObject(glass, kDockHomeButtonBorderKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    if (!border) {
        border = [CAShapeLayer layer];
        border.fillColor = UIColor.clearColor.CGColor;
        border.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        objc_setAssociatedObject(glass, kDockHomeButtonBorderKey, border,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [glass.layer addSublayer:border];
    CGFloat scale = glass.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    CGFloat lineWidth = 1.0 / MAX(scale, 1.0);
    CGRect borderRect = CGRectInset(glass.bounds, lineWidth * 0.5,
                                    lineWidth * 0.5);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    border.frame = glass.bounds;
    border.contentsScale = scale;
    border.lineWidth = lineWidth;
    border.path = [UIBezierPath bezierPathWithRect:borderRect].CGPath;
    [CATransaction commit];
}

static void configureDockGlass(UIView *material, LGLiveBackdropView *glass) {
    // home button docks use a border instead of specular
    LGDockMode mode = dockModeForMaterial(material);
    BOOL homeButtonDock = mode == LGDockModeRegular &&
                          !dockIsFullScreenPhone(material);
    glass.lgSpecularEnabledOverride = homeButtonDock ? @NO : nil;
    dockUpdateHomeButtonBorder(glass, homeButtonDock);
}

%ctor {
    LGRegisterMaterialHost(@"Dock", 80, ^BOOL(UIView *material) {
        return dockModeForMaterial(material) != LGDockModeNone;
    }, UIEdgeInsetsZero, ^CGFloat(__unused UIView *material) {

        return -1.0;
    }, nil, ^(UIView *material, LGLiveBackdropView *glass) {
        configureDockGlass(material, glass);
    });
}
