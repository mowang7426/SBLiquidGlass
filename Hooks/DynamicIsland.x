#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 灵动岛视图识别

static void *kDIGlassKey = &kDIGlassKey;

// 检查视图是否在灵动岛的视图层级中
static BOOL diIsInDynamicIslandHierarchy(UIView *view) {
    @try {
        UIView *candidate = view;
        for (NSInteger level = 0; candidate && level < 20; level++, candidate = candidate.superview) {
            NSString *className = NSStringFromClass(candidate.class);
            if ([className containsString:@"Aperture"] ||
                [className containsString:@"DynamicIsland"] ||
                [className containsString:@"Island"] ||
                [className hasPrefix:@"NBX"] ||
                [className containsString:@"NiceAperture"] ||
                [className containsString:@"NiceIsland"]) {
                return YES;
            }
        }
        UIWindow *window = view.window;
        if (window) {
            NSString *windowClass = NSStringFromClass(window.class);
            if ([windowClass containsString:@"Aperture"] ||
                [windowClass containsString:@"DynamicIsland"] ||
                [windowClass containsString:@"Island"]) {
                return YES;
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查是否是灵动岛的材质视图
static BOOL diIsDynamicIslandMaterial(UIView *mat) {
    @try {
        NSString *className = NSStringFromClass(mat.class);
        BOOL isMaterial = [className containsString:@"Material"] ||
                          [className containsString:@"Backdrop"] ||
                          [className containsString:@"Blur"] ||
                          [className containsString:@"Glass"] ||
                          [className containsString:@"VisualEffect"] ||
                          [className containsString:@"KeyLine"];
        if (!isMaterial) return NO;
        if (!diIsInDynamicIslandHierarchy(mat)) return NO;
        CGFloat w = CGRectGetWidth(mat.bounds), h = CGRectGetHeight(mat.bounds);
        if (w < 10.0 || h < 5.0) return NO;
        return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 液态玻璃效果应用

static void diApplyGlassToView(UIView *view) {
    @try {
        if (!lgHostEnabled(@"DynamicIsland")) return;
        
        LGLiveBackdropView *existing = objc_getAssociatedObject(view, kDIGlassKey);
        if (existing) {
            existing.hidden = NO;
            existing.frame = view.bounds;
            return;
        }
        
        NSLog(@"[SBLiquidGlass-DI] Applying glass to view: %@ frame=%@",
              NSStringFromClass(view.class), NSStringFromCGRect(view.frame));
        
        CGFloat cornerRadius = CGRectGetHeight(view.bounds) * 0.5;
        LGLiveBackdropView *glass = LGInstallRegisteredGlassInMaterial(view, kDIGlassKey, @"DynamicIsland",
                                                                         UIEdgeInsetsZero, cornerRadius, nil);
        if (glass) {
            NSLog(@"[SBLiquidGlass-DI] Glass applied successfully to %@", NSStringFromClass(view.class));
        } else {
            NSLog(@"[SBLiquidGlass-DI] Failed to apply glass to %@", NSStringFromClass(view.class));
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception while applying glass: %@", e);
    }
}

static void diApplyGlassToMaterial(UIView *mat) {
    @try {
        if (!diIsDynamicIslandMaterial(mat)) return;
        diApplyGlassToView(mat);
    } @catch (__unused NSException *e) {}
}

static void diRemoveGlassFromView(UIView *view) {
    @try {
        LGLiveBackdropView *existing = objc_getAssociatedObject(view, kDIGlassKey);
        if (existing) {
            [existing removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook 系统灵动岛的材质视图

%hook MTMaterialView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToMaterial(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToMaterial(self);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook nice 灵动岛的自定义视图

%hook NBXLddClassic2View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

%hook NBXLddClassic3View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (fixed parameter count)");
    } @catch (__unused NSException *e) {}
}
