#import <UIKit/UIKit.h>
#import <math.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

static BOOL isFolderIconMaterial(UIView *mat) {
    static Class folderCls, iconCls;
    if (!folderCls) folderCls = NSClassFromString(@"SBFolderIconImageView");
    if (!iconCls)   iconCls   = NSClassFromString(@"SBIconView");
    for (UIView *v = mat.superview; v; v = v.superview) {
        if ([v isKindOfClass:folderCls]) return YES;
        if ([v isKindOfClass:iconCls])   break;
    }
    return NO;
}

static BOOL isOpenFolderMaterial(UIView *mat) {
    if (!hasAncestorOfClassName(mat, @"SBFolderBackgroundView")) return NO;
    CGRect b = mat.bounds;
    return CGRectGetWidth(b) >= 200.0 && CGRectGetHeight(b) >= 200.0;
}

#pragma mark - folder-open coordination

static NSHashTable<UIView *> *sFolderIconGlasses;
static NSHashTable<UIView *> *sFolderIconMaterials;
static NSHashTable<UIView *> *sOpenFolderMaterials;

CGFloat LGFolderIconCornerRadiusFallback(void) {
    // app icon glass borrows this when its image view exposes no radius
    for (UIView *glass in sFolderIconGlasses.allObjects) {
        CGFloat radius = glass.layer.cornerRadius;
        if (isfinite(radius) && radius > 0.0) return radius;
    }
    for (UIView *material in sFolderIconMaterials.allObjects) {
        CGFloat radius = material.layer.cornerRadius;
        if (isfinite(radius) && radius > 0.0) return radius;
    }
    return 0.0;
}

static BOOL anyOpenFolderActive(void) {
    for (UIView *m in sOpenFolderMaterials.allObjects)
        if (m.window) return YES;
    return NO;
}

static void hideFolderIconGlasses(void) {
    // open folder and folder icon captures cannot overlap cleanly
    for (UIView *g in sFolderIconGlasses.allObjects) {
        [g.layer removeAllAnimations];
        g.alpha  = 1.0;
        g.hidden = YES;
    }
}

static void fadeInFolderIconGlasses(void) {
    for (UIView *g in sFolderIconGlasses.allObjects) {
        g.hidden = NO;
        g.alpha  = 0.0;
        [UIView animateWithDuration:0.2 delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ g.alpha = 1.0; }
                         completion:nil];
    }
}

#pragma mark - inject

static void injectFolderIcon(UIView *mat) {
    if (!sFolderIconMaterials) sFolderIconMaterials = [NSHashTable weakObjectsHashTable];
    [sFolderIconMaterials addObject:mat];

    UIView *g = LGInstallRegisteredGlassInMaterial(mat, kGlassKey, @"FolderIcon",
                                                    UIEdgeInsetsZero, -1.0, nil);
    if (!g) return;
    if (!sFolderIconGlasses) sFolderIconGlasses = [NSHashTable weakObjectsHashTable];
    [sFolderIconGlasses addObject:g];
    g.hidden = anyOpenFolderActive();
}

static void injectOpenFolder(UIView *mat) {
    if (!LGInstallRegisteredGlassInMaterial(mat, kGlassKey, @"OpenFolder",
                                            UIEdgeInsetsZero, -1.0, nil)) {
        [sOpenFolderMaterials removeObject:mat];
        if (!anyOpenFolderActive()) fadeInFolderIconGlasses();
        return;
    }
    if (!sOpenFolderMaterials) sOpenFolderMaterials = [NSHashTable weakObjectsHashTable];
    if (![sOpenFolderMaterials containsObject:mat]) {
        [sOpenFolderMaterials addObject:mat];
        hideFolderIconGlasses();
    }
}

%hook MTMaterialView
- (void)didMoveToWindow {
    %orig;
    UIView *self_ = (UIView *)self;
    if (!self_.window) {
        [sFolderIconMaterials removeObject:self_];

        if ([sOpenFolderMaterials containsObject:self_]) {
            [sOpenFolderMaterials removeObject:self_];
            if (!anyOpenFolderActive()) fadeInFolderIconGlasses();
        }
        return;
    }
    if (isFolderIconMaterial(self_))      injectFolderIcon(self_);
    else if (isOpenFolderMaterial(self_)) injectOpenFolder(self_);
}
- (void)layoutSubviews {
    %orig;
    UIView *self_ = (UIView *)self;
    if (isFolderIconMaterial(self_))      injectFolderIcon(self_);
    else if (isOpenFolderMaterial(self_)) injectOpenFolder(self_);
}
%end
