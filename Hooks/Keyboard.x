#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"

@interface UIKeyboard : UIView
+ (instancetype)activeKeyboard;
+ (instancetype)activeKeyboardForScreen:(UIScreen *)screen;
+ (CGSize)sizeForInterfaceOrientation:(NSInteger)orientation
                      ignoreInputView:(BOOL)ignoreInputView;
- (BOOL)showPredictionBar;
- (void)_setPreferredHeight:(CGFloat)height;
- (void)updateLayout;
@end

@interface UIKBBackdropView : UIView
@end

@interface UIKBVisualEffectView : UIView
@end

@interface UIKBRenderer : NSObject
- (void)renderKeyContents:(id)contents withTraits:(id)traits;
- (void)renderBackgroundTraits:(id)traits allowCaching:(BOOL)allowCaching;
@end

@interface UIKBRenderGeometry : NSObject
- (CGFloat)roundRectRadius;
@end

@interface UIKBKeyView : UIView
- (id)keyplane;
@end

@interface UIKBSplitImageView : UIView
@end

@interface UIKeyboardLayoutStar : UIView
@end

@interface UIKBTextStyle : NSObject
- (NSString *)fontName;
@end

static BOOL gLGKeyboardPredictionStateKnown;
static BOOL gLGKeyboardHasPredictionStrip;
static __thread NSUInteger gLGKeyboardSizingDepth;
static const void *kLGKeyboardGlassKey = &kLGKeyboardGlassKey;
static const void *kLGKeyboardSuppressingHiddenKey =
    &kLGKeyboardSuppressingHiddenKey;
static const void *kLGKeyboardRequestedHiddenKey =
    &kLGKeyboardRequestedHiddenKey;
static const void *kLGKeyboardVisualEffectSuppressingHiddenKey =
    &kLGKeyboardVisualEffectSuppressingHiddenKey;
static const void *kLGKeyboardVisualEffectRequestedHiddenKey =
    &kLGKeyboardVisualEffectRequestedHiddenKey;
static const void *kLGKeyboardBorderKey = &kLGKeyboardBorderKey;
static const void *kLGKeyboardKeyOriginalRadiusKey =
    &kLGKeyboardKeyOriginalRadiusKey;
static const void *kLGKeyboardKeyOriginalMasksKey =
    &kLGKeyboardKeyOriginalMasksKey;
static const void *kLGKeyboardGeometryKeycapRadiusKey =
    &kLGKeyboardGeometryKeycapRadiusKey;
static NSHashTable<UIView *> *gLGKeyboardBackdrops;
static NSHashTable<UIView *> *gLGKeyboardVisualEffects;
static __thread NSUInteger gLGKeyboardAtlasRenderFlags;
static __thread BOOL gLGKeyboardRenderingActionKey;
static __thread __unsafe_unretained NSString *gLGKeyboardRenderingActionName;
static CGFloat gLGKeyboardKeycapRadius;
static NSUInteger gLGKeyboardActionLogCount;
static NSUInteger gLGKeyboardBackdropLogCount;
static NSHashTable *gLGKeyboardRegeneratedKeyplanes;
static NSHashTable *gLGKeyboardScheduledKeyplanes;
static NSMutableSet<NSString *> *gLGKeyboardHookedKeyplaneClasses;
static BOOL gLGKeyboardKeyplaneRefreshScheduled;
static __thread BOOL gLGKeyboardApplyingKeyplaneBounds;
static const CGFloat kLGKeyboardBottomGlassExtra = 10.0;

static CGFloat LGKeyboardCornerRadius(void) {
    return fmin(60.0, fmax(0.0,
        LG_prefFloat(@"Keyboard.CornerRadius",
                     LGKeyboardDefaultCornerRadius)));
}

static CGFloat LGKeyboardTopOverhang(void) {
    return fmin(60.0, fmax(0.0,
        LG_prefFloat(@"Keyboard.Overhang",
                     LGKeyboardDefaultOverhang)));
}

static CGFloat LGKeyboardKeyplaneCompensation(void) {
    return LGKeyboardTopOverhang() * 0.5;
}

static BOOL LGIsRemoteKeyboardWindow(UIWindow *window) {
    if (!window) return NO;

    Class remoteKeyboardWindowClass =
        NSClassFromString(@"UIRemoteKeyboardWindow");
    if (remoteKeyboardWindowClass) {
        return [window isKindOfClass:remoteKeyboardWindowClass];
    }

    return [NSStringFromClass(window.class)
        isEqualToString:@"UIRemoteKeyboardWindow"];
}

static id LGKeyboardSendObject(id target, SEL selector);
static void LGKeyboardSendVoid(id target, SEL selector);
static void LGKeyboardScheduleKeyplaneRefresh(void);

static id LGActiveKeyboardForScreen(UIScreen *screen) {
    Class keyboardClass = NSClassFromString(@"UIKeyboard");
    if (!keyboardClass) return nil;

    SEL perScreenSelector =
        NSSelectorFromString(@"activeKeyboardForScreen:");

    if (screen &&
        [keyboardClass respondsToSelector:perScreenSelector]) {
        return ((id (*)(id, SEL, id))objc_msgSend)(
            keyboardClass, perScreenSelector, screen);
    }

    return LGKeyboardSendObject(
        keyboardClass, NSSelectorFromString(@"activeKeyboard"));
}

static BOOL LGKeyboardNeedsTopReserve(void) {
    if (!lgHostEnabled(@"Keyboard")) return NO;

    if (gLGKeyboardPredictionStateKnown) {
        return !gLGKeyboardHasPredictionStrip;
    }

    id keyboard = LGActiveKeyboardForScreen(UIScreen.mainScreen);
    SEL predictionSelector = NSSelectorFromString(@"showPredictionBar");
    if (keyboard &&
        [keyboard respondsToSelector:predictionSelector]) {
        BOOL showsPrediction =
            ((BOOL (*)(id, SEL))objc_msgSend)(
                keyboard, predictionSelector);
        return !showsPrediction;
    }

    return NO;
}

static CGSize LGKeyboardReserveSize(CGSize size) {
    if (LGKeyboardNeedsTopReserve() && size.height > 1.0) {

        size.height += LGKeyboardTopOverhang();
    }

    return size;
}

static void LGKeyboardRefreshReportedGeometry(UIScreen *screen) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id keyboard = LGActiveKeyboardForScreen(screen);
        if (!keyboard) return;

        UIView *keyboardView = [keyboard isKindOfClass:UIView.class]
            ? (UIView *)keyboard
            : nil;
        if (!keyboardView) return;

        [keyboardView invalidateIntrinsicContentSize];
        [keyboardView setNeedsLayout];
        [keyboardView.superview setNeedsLayout];
        [keyboardView.window setNeedsLayout];

        SEL updateSelector = NSSelectorFromString(@"updateLayout");
        if ([keyboard respondsToSelector:updateSelector]) {
            ((void (*)(id, SEL))objc_msgSend)(
                keyboard, updateSelector);
        }

        [keyboardView.window layoutIfNeeded];
        LGKeyboardScheduleKeyplaneRefresh();
    });
}

static NSString *LGKeyboardCompactFontName(void) {
    static NSString *postScriptName;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        UIFontDescriptor *descriptor =
            [UIFontDescriptor preferredFontDescriptorWithTextStyle:
                @"UICTFontTextStyleCompact"];
        UIFont *font = descriptor
            ? [UIFont fontWithDescriptor:descriptor size:0.0] : nil;
        postScriptName = font.fontName;
        LGLog(@"[keyboard] compact system font style=%@ descriptor=%@ font=%@",
              @"UICTFontTextStyleCompact", descriptor,
              postScriptName ?: @"(unavailable)");
    });
    return postScriptName;
}

static NSUInteger LGKeyboardRendererFlags(id renderer) {
    static Ivar renderFlagsIvar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        renderFlagsIvar =
            class_getInstanceVariable(NSClassFromString(@"UIKBRenderer"),
                                      "_renderFlags");
    });
    if (!renderFlagsIvar) return 0;

    NSUInteger flags = 0;
    const uint8_t *bytes =
        (const uint8_t *)(__bridge const void *)renderer;
    memcpy(&flags, bytes + ivar_getOffset(renderFlagsIvar), sizeof(flags));
    return flags;
}

static id LGKeyboardValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id LGKeyboardSendObject(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static void LGKeyboardSendVoid(id target, SEL selector) {
    if (target && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(target, selector);
    }
}

static void LGKeyboardSendObjectArgument(id target, SEL selector, id value) {
    if (target && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    }
}

static UIView *LGKeyboardCurrentKeyplaneView(void) {
    Class implClass = NSClassFromString(@"UIKeyboardImpl");
    id impl = LGKeyboardSendObject(implClass,
                                   NSSelectorFromString(@"activeInstance"));
    if (!impl) {
        impl = LGKeyboardSendObject(implClass,
                                    NSSelectorFromString(@"sharedInstance"));
    }

    id layout = LGKeyboardSendObject(impl,
                                     NSSelectorFromString(@"activeLayout"));
    id keyplane = LGKeyboardSendObject(
        layout, NSSelectorFromString(@"currentKeyplaneView"));
    return [keyplane isKindOfClass:UIView.class] ? (UIView *)keyplane : nil;
}

static CGFloat LGKeyboardTargetKeyplaneBoundsY(void) {
    return LGKeyboardNeedsTopReserve()
        ? -LGKeyboardKeyplaneCompensation()
        : 0.0;
}

static BOOL LGKeyboardIsDirectKeyplaneAtlas(UIView *view) {
    if (!view || !view.superview) return NO;
    return [NSStringFromClass(view.class)
                isEqualToString:@"UIKBSplitImageView"] &&
           [NSStringFromClass(view.superview.class)
                isEqualToString:@"UIKBKeyplaneView"];
}

static void LGKeyboardNormalizeKeyplaneAtlasFrames(UIView *keyplane) {
    if (!keyplane || !LGKeyboardNeedsTopReserve()) return;

    // moving keyplane bounds must not move its baked image atlas twice
    CGFloat keyplaneBoundsY = keyplane.bounds.origin.y;
    if (fabs(keyplaneBoundsY) < 0.01) return;

    for (UIView *child in keyplane.subviews) {
        if (!LGKeyboardIsDirectKeyplaneAtlas(child)) continue;

        CGRect frame = child.frame;

        if (fabs(frame.origin.y - keyplaneBoundsY) < 0.51) {
            frame.origin.y -= keyplaneBoundsY;
            child.frame = frame;
        }
    }
}

static void LGKeyboardCallOriginalKeyplaneSetBounds(UIView *keyplane,
                                                     CGRect bounds) {
    SEL originalSelector =
        NSSelectorFromString(@"lg_keyboard_original_setBounds:");
    if ([keyplane respondsToSelector:originalSelector]) {
        ((void (*)(id, SEL, CGRect))objc_msgSend)(
            keyplane, originalSelector, bounds);
    }
}

static void LGKeyboardApplyKeyplaneBoundsOffset(UIView *keyplane) {
    if (!keyplane || gLGKeyboardApplyingKeyplaneBounds) return;

    CGRect bounds = keyplane.bounds;
    CGFloat targetY = LGKeyboardTargetKeyplaneBoundsY();
    if (fabs(bounds.origin.y - targetY) < 0.01) return;

    bounds.origin.y = targetY;
    gLGKeyboardApplyingKeyplaneBounds = YES;
    LGKeyboardCallOriginalKeyplaneSetBounds(keyplane, bounds);
    gLGKeyboardApplyingKeyplaneBounds = NO;
}

static void LGKeyboardKeyplaneSetBounds(id object, SEL selector,
                                         CGRect bounds) {
    UIView *keyplane = [object isKindOfClass:UIView.class]
        ? (UIView *)object
        : nil;
    if (!keyplane) return;

    bounds.origin.y = LGKeyboardTargetKeyplaneBoundsY();
    LGKeyboardCallOriginalKeyplaneSetBounds(keyplane, bounds);
}

static void LGKeyboardKeyplaneLayoutSubviews(id object, SEL selector) {
    SEL originalSelector =
        NSSelectorFromString(@"lg_keyboard_original_layoutSubviews");
    if ([object respondsToSelector:originalSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(object, originalSelector);
    }

    UIView *keyplane = [object isKindOfClass:UIView.class]
        ? (UIView *)object
        : nil;
    LGKeyboardApplyKeyplaneBoundsOffset(keyplane);
    LGKeyboardNormalizeKeyplaneAtlasFrames(keyplane);
}

static void LGKeyboardInstallKeyplaneHooks(UIView *keyplane) {
    if (!keyplane) return;

    // keyplane classes vary so hook each concrete class once
    Class keyplaneClass = object_getClass(keyplane);
    NSString *className = NSStringFromClass(keyplaneClass);
    if (!keyplaneClass || !className.length ||
        [gLGKeyboardHookedKeyplaneClasses containsObject:className]) {
        LGKeyboardApplyKeyplaneBoundsOffset(keyplane);
        LGKeyboardNormalizeKeyplaneAtlasFrames(keyplane);
        return;
    }

    @synchronized (gLGKeyboardHookedKeyplaneClasses) {
        if ([gLGKeyboardHookedKeyplaneClasses containsObject:className]) {
            LGKeyboardApplyKeyplaneBoundsOffset(keyplane);
            LGKeyboardNormalizeKeyplaneAtlasFrames(keyplane);
            return;
        }

        SEL setBoundsSelector = @selector(setBounds:);
        Method setBoundsMethod =
            class_getInstanceMethod(keyplaneClass, setBoundsSelector);
        if (!setBoundsMethod) return;

        IMP originalSetBounds = method_getImplementation(setBoundsMethod);
        const char *setBoundsTypes = method_getTypeEncoding(setBoundsMethod);
        SEL originalSetBoundsSelector =
            NSSelectorFromString(@"lg_keyboard_original_setBounds:");
        class_addMethod(keyplaneClass, originalSetBoundsSelector,
                        originalSetBounds, setBoundsTypes);

        if (!class_addMethod(keyplaneClass, setBoundsSelector,
                             (IMP)LGKeyboardKeyplaneSetBounds,
                             setBoundsTypes)) {
            Method directSetBoundsMethod =
                class_getInstanceMethod(keyplaneClass, setBoundsSelector);
            method_setImplementation(directSetBoundsMethod,
                                     (IMP)LGKeyboardKeyplaneSetBounds);
        }

        SEL layoutSelector = @selector(layoutSubviews);
        Method layoutMethod =
            class_getInstanceMethod(keyplaneClass, layoutSelector);
        if (layoutMethod) {
            IMP originalLayout = method_getImplementation(layoutMethod);
            const char *layoutTypes = method_getTypeEncoding(layoutMethod);
            SEL originalLayoutSelector =
                NSSelectorFromString(@"lg_keyboard_original_layoutSubviews");
            class_addMethod(keyplaneClass, originalLayoutSelector,
                            originalLayout, layoutTypes);

            if (!class_addMethod(keyplaneClass, layoutSelector,
                                 (IMP)LGKeyboardKeyplaneLayoutSubviews,
                                 layoutTypes)) {
                Method directLayoutMethod =
                    class_getInstanceMethod(keyplaneClass, layoutSelector);
                method_setImplementation(directLayoutMethod,
                                         (IMP)LGKeyboardKeyplaneLayoutSubviews);
            }
        }

        [gLGKeyboardHookedKeyplaneClasses addObject:className];
        LGLog(@"[keyboard] hooked runtime keyplane class=%@ offset=%.2f",
              className, LGKeyboardKeyplaneCompensation());
    }

    LGKeyboardApplyKeyplaneBoundsOffset(keyplane);
    LGKeyboardNormalizeKeyplaneAtlasFrames(keyplane);
}

static void LGKeyboardRefreshCurrentKeyplane(void) {
    UIView *keyplane = LGKeyboardCurrentKeyplaneView();
    LGKeyboardInstallKeyplaneHooks(keyplane);
}

static void LGKeyboardScheduleKeyplaneRefresh(void) {
    if (gLGKeyboardKeyplaneRefreshScheduled) return;
    gLGKeyboardKeyplaneRefreshScheduled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        gLGKeyboardKeyplaneRefreshScheduled = NO;
        LGKeyboardRefreshCurrentKeyplane();
    });
}

static void LGRegenerateKeyboardKeyplaneIfNeeded(id keyplaneIdentity) {
    if (!keyplaneIdentity ||
        [gLGKeyboardRegeneratedKeyplanes containsObject:keyplaneIdentity] ||
        [gLGKeyboardScheduledKeyplanes containsObject:keyplaneIdentity]) return;
    [gLGKeyboardScheduledKeyplanes addObject:keyplaneIdentity];
    dispatch_async(dispatch_get_main_queue(), ^{
        [gLGKeyboardScheduledKeyplanes removeObject:keyplaneIdentity];
        if ([gLGKeyboardRegeneratedKeyplanes containsObject:keyplaneIdentity]) return;

        Class implClass = NSClassFromString(@"UIKeyboardImpl");
        id impl = LGKeyboardSendObject(implClass,
                                      NSSelectorFromString(@"activeInstance"));
        if (!impl) {
            impl = LGKeyboardSendObject(implClass,
                                        NSSelectorFromString(@"sharedInstance"));
        }
        id layout = LGKeyboardSendObject(impl,
                                         NSSelectorFromString(@"activeLayout"));
        id keyplane = LGKeyboardSendObject(
            layout, NSSelectorFromString(@"currentKeyplaneView"));
        if (!layout || !keyplane) return;

        [gLGKeyboardRegeneratedKeyplanes addObject:keyplaneIdentity];

        if (!lgHostEnabled(@"Keyboard")) gLGKeyboardKeycapRadius = 0.0;
        LGKeyboardSendVoid(NSClassFromString(@"UIKBRenderer"),
                           NSSelectorFromString(@"clearInternalCaches"));
        LGKeyboardSendObjectArgument(layout,
                                     NSSelectorFromString(@"flushKeyCache:"), nil);
        LGKeyboardSendObjectArgument(keyplane,
                                     NSSelectorFromString(@"setCacheToken:"), nil);
        LGKeyboardSendObjectArgument(
            keyplane, NSSelectorFromString(@"setDefaultKeyplaneCacheToken:"), nil);
        LGKeyboardSendVoid(keyplane,
                           NSSelectorFromString(@"purgeActiveKeyViews"));
        LGKeyboardSendVoid(keyplane, NSSelectorFromString(@"purgeKeyViews"));
        LGKeyboardSendVoid(
            layout, NSSelectorFromString(@"didTriggerDestructiveRenderConfigChange"));
        LGKeyboardSendVoid(layout,
                           NSSelectorFromString(@"reloadCurrentKeyplane"));
        LGKeyboardSendVoid(layout,
                           NSSelectorFromString(@"updateCachedKeyplaneKeycaps"));
        LGKeyboardScheduleKeyplaneRefresh();
        NSString *name = LGKeyboardSendObject(
            layout, NSSelectorFromString(@"keyplaneName"));
        LGLog(@"[keyboard] regenerated keyplane=%@ identity=%p mode=%@",
              name ?: @"(unknown)", keyplaneIdentity,
              lgHostEnabled(@"Keyboard") ? @"rounded" : @"stock");
    });
}

static void LGUpdateKeyboardKeyCorner(UIView *keyView) {
    NSNumber *originalRadius =
        objc_getAssociatedObject(keyView, kLGKeyboardKeyOriginalRadiusKey);
    NSNumber *originalMasks =
        objc_getAssociatedObject(keyView, kLGKeyboardKeyOriginalMasksKey);
    if (!originalRadius) {
        originalRadius = @(keyView.layer.cornerRadius);
        originalMasks = @(keyView.layer.masksToBounds);
        objc_setAssociatedObject(keyView, kLGKeyboardKeyOriginalRadiusKey,
                                 originalRadius,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(keyView, kLGKeyboardKeyOriginalMasksKey,
                                 originalMasks,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!lgHostEnabled(@"Keyboard") || CGRectIsEmpty(keyView.bounds)) {
        keyView.layer.cornerRadius = originalRadius.doubleValue;
        keyView.layer.masksToBounds = originalMasks.boolValue;
        return;
    }

    CGFloat shortEdge =
        MIN(CGRectGetWidth(keyView.bounds), CGRectGetHeight(keyView.bounds));
    keyView.layer.cornerRadius =
        gLGKeyboardKeycapRadius > 0.0
            ? MIN(gLGKeyboardKeycapRadius, shortEdge * 0.5)
            : shortEdge * (10.0 / 46.0);
    keyView.layer.cornerCurve = kCACornerCurveContinuous;
    keyView.layer.masksToBounds = YES;
}

static BOOL LGIsKeyboardBackdrop(UIView *view) {
    return [NSStringFromClass(view.class) isEqualToString:@"UIKBBackdropView"] &&
           [NSStringFromClass(view.superview.class)
               isEqualToString:@"UIKBInputBackdropView"];
}

static void LGKeyboardSetStockHidden(UIView *stock, BOOL hidden) {
    objc_setAssociatedObject(stock, kLGKeyboardSuppressingHiddenKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    stock.hidden = hidden;
    objc_setAssociatedObject(stock, kLGKeyboardSuppressingHiddenKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
}

static void LGRemoveKeyboardGlass(UIView *stock) {
    LGLiveBackdropView *glass =
        objc_getAssociatedObject(stock, kLGKeyboardGlassKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(stock, kLGKeyboardGlassKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    LGKeyboardSetStockHidden(
        stock,
        [objc_getAssociatedObject(stock, kLGKeyboardRequestedHiddenKey)
            boolValue]);
}

static NSArray<UIView *> *LGKeyboardBackdropsInWindow(UIWindow *window) {
    if (!LGIsRemoteKeyboardWindow(window)) return @[];

    NSMutableArray<UIView *> *backdrops = [NSMutableArray array];
    for (UIView *candidate in gLGKeyboardBackdrops.allObjects) {
        if (candidate.window == window && LGIsKeyboardBackdrop(candidate)) {
            [backdrops addObject:candidate];
        }
    }
    return backdrops;
}

static CGRect LGKeyboardMergedBackdropFrame(NSArray<UIView *> *backdrops,
                                            UIView *container) {
    CGRect frame = CGRectNull;
    for (UIView *backdrop in backdrops) {
        CGRect converted = [backdrop.superview convertRect:backdrop.frame
                                                    toView:container];
        frame = CGRectIsNull(frame) ? converted : CGRectUnion(frame, converted);
    }
    return CGRectIsNull(frame) ? CGRectZero : CGRectIntegral(frame);
}

static NSString *LGKeyboardBackdropSummary(NSArray<UIView *> *backdrops) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UIView *view in backdrops) {
        [parts addObject:[NSString stringWithFormat:@"%@ frame=%@ bounds=%@ hidden=%d",
            NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
            NSStringFromCGRect(view.bounds), view.hidden]];
    }
    return [parts componentsJoinedByString:@"; "];
}

static void LGUpdateKeyboardBorder(LGLiveBackdropView *glass) {
    CAShapeLayer *border = objc_getAssociatedObject(glass, kLGKeyboardBorderKey);
    if (!border) {
        border = [CAShapeLayer layer];
        border.fillColor = UIColor.clearColor.CGColor;
        border.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        objc_setAssociatedObject(glass, kLGKeyboardBorderKey, border,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [glass.layer addSublayer:border];
    CGFloat scale = glass.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    CGFloat lineWidth = 1.0 / MAX(scale, 1.0);
    CGRect borderRect = CGRectInset(glass.bounds, lineWidth * 0.5,
                                    lineWidth * 0.5);
    CGFloat radius = MAX(0.0, glass.layer.cornerRadius - lineWidth * 0.5);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    border.frame = glass.bounds;
    border.contentsScale = scale;
    border.lineWidth = lineWidth;
    border.path = [UIBezierPath bezierPathWithRoundedRect:borderRect
                                              cornerRadius:radius].CGPath;
    [CATransaction commit];
}

static void LGUpdateKeyboardGlass(UIView *stock) {
    if (!LGIsKeyboardBackdrop(stock) || !stock.superview) return;

    if (!LGIsRemoteKeyboardWindow(stock.window)) {
        LGRemoveKeyboardGlass(stock);
        return;
    }

    if (!lgHostEnabled(@"Keyboard")) {
        LGRemoveKeyboardGlass(stock);
        return;
    }

    NSArray<UIView *> *backdrops = LGKeyboardBackdropsInWindow(stock.window);
    if (!backdrops.count) backdrops = @[ stock ];
    UIView *primary = stock;
    for (UIView *candidate in backdrops) {
        if (CGRectGetHeight(candidate.bounds) > CGRectGetHeight(primary.bounds)) {
            primary = candidate;
        }
    }

    if (stock != primary) {
        LGRemoveKeyboardGlass(stock);
        LGKeyboardSetStockHidden(stock, YES);
        return;
    }

    UIView *container = primary.superview;
    if (!container) return;
    CGRect mergedFrame = LGKeyboardMergedBackdropFrame(backdrops, container);
    if (CGRectIsEmpty(mergedFrame)) {
        mergedFrame = [primary.superview convertRect:primary.frame toView:container];
    }
    BOOL hasPredictionStrip = NO;
    for (UIView *backdrop in backdrops) {
        if (backdrop != primary &&
            CGRectGetHeight(backdrop.bounds) > 1.0) {
            hasPredictionStrip = YES;
            break;
        }
    }
    BOOL predictionStateChanged =
        !gLGKeyboardPredictionStateKnown ||
        gLGKeyboardHasPredictionStrip != hasPredictionStrip;

    gLGKeyboardPredictionStateKnown = YES;
    gLGKeyboardHasPredictionStrip = hasPredictionStrip;

    if (predictionStateChanged) {
        LGKeyboardRefreshReportedGeometry(stock.window.screen);
    }
    if (!hasPredictionStrip) {
        container.clipsToBounds = NO;
        container.layer.masksToBounds = NO;

        LGKeyboardScheduleKeyplaneRefresh();
    }

    mergedFrame.size.height += LGKeyboardTopOverhang() + kLGKeyboardBottomGlassExtra;

    if (gLGKeyboardBackdropLogCount++ < 24) {
        LGLog(@"[keyboard] backdrop merge count=%lu prediction=%d primary=%p container=%@ merged=%@ members=[%@]",
              (unsigned long)backdrops.count, hasPredictionStrip, primary,
              NSStringFromClass(container.class), NSStringFromCGRect(mergedFrame),
              LGKeyboardBackdropSummary(backdrops));
    }

    LGLiveBackdropView *glass =
        objc_getAssociatedObject(primary, kLGKeyboardGlassKey);
    if (!glass) {
        glass = LGCreateRegisteredGlass(mergedFrame, nil, @"Keyboard");
        if (!glass) return;
        glass.userInteractionEnabled = NO;
        glass.lgSpecularEnabledOverride = @NO;
        [container addSubview:glass];
        objc_setAssociatedObject(primary, kLGKeyboardGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"Keyboard", nil);
    } else if (glass.superview != container) {
        [glass removeFromSuperview];
        [container addSubview:glass];
    }

    glass.frame = mergedFrame;
    glass.layer.mask = nil;
    glass.layer.cornerRadius = LGKeyboardCornerRadius();
    glass.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        glass.layer.cornerCurve = kCACornerCurveContinuous;
    }
    LGUpdateKeyboardBorder(glass);
    glass.alpha = primary.alpha;
    glass.hidden =
        [objc_getAssociatedObject(primary, kLGKeyboardRequestedHiddenKey)
            boolValue];
    for (UIView *backdrop in backdrops) {
        if (backdrop != primary) LGRemoveKeyboardGlass(backdrop);
        LGKeyboardSetStockHidden(backdrop, YES);
    }
}

static void LGKeyboardSetVisualEffectHidden(UIView *effectView, BOOL hidden) {
    objc_setAssociatedObject(effectView,
                             kLGKeyboardVisualEffectSuppressingHiddenKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    effectView.hidden = hidden;
    objc_setAssociatedObject(effectView,
                             kLGKeyboardVisualEffectSuppressingHiddenKey,
                             nil, OBJC_ASSOCIATION_ASSIGN);
}

static void LGUpdateKeyboardVisualEffect(UIView *effectView) {
    if (!effectView.window) return;
    BOOL requestedHidden =
        [objc_getAssociatedObject(effectView,
                                  kLGKeyboardVisualEffectRequestedHiddenKey)
            boolValue];

    LGKeyboardSetVisualEffectHidden(effectView,
                                    lgHostEnabled(@"Keyboard") ? YES : requestedHidden);
}

%hook UIKBBackdropView

- (void)didMoveToWindow {
    %orig;
    if (LGIsRemoteKeyboardWindow(self.window)) {
        [gLGKeyboardBackdrops addObject:self];
        LGUpdateKeyboardGlass(self);
    } else {
        [gLGKeyboardBackdrops removeObject:self];
        LGRemoveKeyboardGlass(self);
    }
}

- (void)layoutSubviews {
    %orig;
    LGUpdateKeyboardGlass(self);
}

- (void)setFrame:(CGRect)frame {
    %orig;
    LGUpdateKeyboardGlass(self);
}

- (void)setBounds:(CGRect)bounds {
    %orig;
    LGUpdateKeyboardGlass(self);
}

- (void)setHidden:(BOOL)hidden {
    if ([objc_getAssociatedObject(self, kLGKeyboardSuppressingHiddenKey)
            boolValue]) {
        %orig(hidden);
        return;
    }

    objc_setAssociatedObject(self, kLGKeyboardRequestedHiddenKey, @(hidden),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LGLiveBackdropView *glass =
        objc_getAssociatedObject(self, kLGKeyboardGlassKey);
    if (glass && lgHostEnabled(@"Keyboard") &&
        LGIsRemoteKeyboardWindow(self.window)) {
        glass.hidden = hidden;
        %orig(YES);
        return;
    }
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(alpha);
    LGLiveBackdropView *glass =
        objc_getAssociatedObject(self, kLGKeyboardGlassKey);
    glass.alpha = alpha;
}

%end

%hook UIKBVisualEffectView

- (void)didMoveToWindow {
    %orig;
    [gLGKeyboardVisualEffects addObject:self];
    LGUpdateKeyboardVisualEffect(self);
}

- (void)layoutSubviews {
    %orig;
    LGUpdateKeyboardVisualEffect(self);
}

- (void)setHidden:(BOOL)hidden {
    if ([objc_getAssociatedObject(self,
                                  kLGKeyboardVisualEffectSuppressingHiddenKey)
            boolValue]) {
        %orig(hidden);
        return;
    }

    objc_setAssociatedObject(self, kLGKeyboardVisualEffectRequestedHiddenKey,
                             @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (lgHostEnabled(@"Keyboard")) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}

%end

%hook UIKBRenderer

- (void)renderBackgroundTraits:(id)traits allowCaching:(BOOL)allowCaching {
    id geometry = LGKeyboardValue(traits, @"geometry");
    SEL getter = NSSelectorFromString(@"roundRectRadius");
    SEL setter = NSSelectorFromString(@"setRoundRectRadius:");
    BOOL canOverride = lgHostEnabled(@"Keyboard") && geometry &&
        [geometry respondsToSelector:getter] &&
        [geometry respondsToSelector:setter];
    CGFloat stockRadius = 0.0;
    if (canOverride) {
        stockRadius = ((CGFloat (*)(id, SEL))objc_msgSend)(geometry, getter);
        CGFloat targetRadius = gLGKeyboardKeycapRadius > 0.0
            ? gLGKeyboardKeycapRadius
            : stockRadius * 2.0;
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(geometry, setter,
                                                   targetRadius);
        if (gLGKeyboardRenderingActionKey &&
            gLGKeyboardActionLogCount++ < 160) {
            LGLog(@"[keyboard] action background name=%@ flags=%lu cache=%d geometry=%p radius=%.2f->%.2f frame=%@ display=%@ symbol=%@",
                  gLGKeyboardRenderingActionName ?: @"(unknown)",
                  (unsigned long)LGKeyboardRendererFlags(self), allowCaching,
                  geometry, stockRadius, targetRadius,
                  LGKeyboardValue(geometry, @"frame"),
                  LGKeyboardValue(geometry, @"displayFrame"),
                  LGKeyboardValue(geometry, @"symbolFrame"));
        }
    }
    @try {
        %orig(traits, allowCaching);
    } @finally {
        if (canOverride) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(geometry, setter,
                                                       stockRadius);
        }
    }
}

- (void)renderKeyContents:(id)contents withTraits:(id)traits {

    NSUInteger flags = LGKeyboardRendererFlags(self);
    NSString *displayString = LGKeyboardValue(contents, @"displayString");
    id geometry = LGKeyboardValue(traits, @"geometry");
    NSValue *displayFrameValue = LGKeyboardValue(geometry, @"displayFrame");
    CGFloat displayWidth = displayFrameValue
        ? CGRectGetWidth(displayFrameValue.CGRectValue) : 0.0;
    BOOL actionKey = displayString.length != 1 || displayWidth > 48.0;
    if (actionKey && gLGKeyboardActionLogCount++ < 160) {
        LGLog(@"[keyboard] action render name=%@ flags=%lu contents=%@ geometry=%p radius=%@ layeredBG=%@ layeredFG=%@ frame=%@ display=%@ symbol=%@",
              displayString ?: @"(nil)", (unsigned long)flags,
              NSStringFromClass([contents class]), geometry,
              LGKeyboardValue(geometry, @"roundRectRadius"),
              LGKeyboardValue(geometry, @"layeredBackgroundRoundRectRadius"),
              LGKeyboardValue(geometry, @"layeredForegroundRoundRectRadius"),
              LGKeyboardValue(geometry, @"frame"),
              LGKeyboardValue(geometry, @"displayFrame"),
              LGKeyboardValue(geometry, @"symbolFrame"));
    }
    BOOL rendersRoundedAtlas = flags == 1 || flags == 6;
    SEL layeredGetter =
        NSSelectorFromString(@"layeredBackgroundRoundRectRadius");
    SEL layeredSetter =
        NSSelectorFromString(@"setLayeredBackgroundRoundRectRadius:");
    BOOL canOverrideLayeredBackground = lgHostEnabled(@"Keyboard") &&
        actionKey && geometry &&
        [geometry respondsToSelector:layeredGetter] &&
        [geometry respondsToSelector:layeredSetter];
    CGFloat stockLayeredBackgroundRadius = 0.0;
    if (canOverrideLayeredBackground) {
        stockLayeredBackgroundRadius =
            ((CGFloat (*)(id, SEL))objc_msgSend)(geometry, layeredGetter);
        CGFloat targetRadius = gLGKeyboardKeycapRadius > 0.0
            ? gLGKeyboardKeycapRadius : 10.0;
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(geometry, layeredSetter,
                                                   targetRadius);
        if (gLGKeyboardActionLogCount++ < 160) {
            LGLog(@"[keyboard] action layered-background name=%@ flags=%lu geometry=%p radius=%.2f->%.2f",
                  displayString ?: @"(nil)", (unsigned long)flags, geometry,
                  stockLayeredBackgroundRadius, targetRadius);
        }
    }
    NSUInteger previousFlags = gLGKeyboardAtlasRenderFlags;
    BOOL previousAction = gLGKeyboardRenderingActionKey;
    NSString *previousActionName = gLGKeyboardRenderingActionName;
    BOOL appliesRoundedAtlas = lgHostEnabled(@"Keyboard") && rendersRoundedAtlas;
    if (appliesRoundedAtlas) gLGKeyboardAtlasRenderFlags = flags;
    gLGKeyboardRenderingActionKey = actionKey;
    gLGKeyboardRenderingActionName = displayString;
    @try {
        %orig(contents, traits);
    } @finally {
        if (canOverrideLayeredBackground) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(
                geometry, layeredSetter, stockLayeredBackgroundRadius);
        }
        gLGKeyboardRenderingActionKey = previousAction;
        gLGKeyboardRenderingActionName = previousActionName;
        if (appliesRoundedAtlas) {
            gLGKeyboardAtlasRenderFlags = previousFlags;
        }
    }
}

%end

%hook UIKBRenderGeometry

- (CGFloat)roundRectRadius {
    CGFloat radius = %orig;
    if (gLGKeyboardAtlasRenderFlags == 1) {
        NSNumber *originalRadius =
            objc_getAssociatedObject(self, kLGKeyboardGeometryKeycapRadiusKey);
        if (!originalRadius) {
            originalRadius = @(radius);
            objc_setAssociatedObject(self, kLGKeyboardGeometryKeycapRadiusKey,
                                     originalRadius,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGFloat keycapRadius = originalRadius.doubleValue * 2.0;
        gLGKeyboardKeycapRadius = keycapRadius;
        return keycapRadius;
    }
    if (gLGKeyboardAtlasRenderFlags == 6 && gLGKeyboardKeycapRadius > 0.0) {

        return gLGKeyboardKeycapRadius;
    }
    return radius;
}

%end

%hook UIKBKeyView

- (void)setKey:(id)key {
    %orig(key);
    NSString *name = LGKeyboardValue(key, @"name");
    NSString *display = LGKeyboardValue(key, @"displayString");
    if ((name.length > 0 || display.length != 1 ||
         CGRectGetWidth(self.bounds) > 48.0) &&
        gLGKeyboardActionLogCount++ < 160) {
        LGLog(@"[keyboard] action assign view=%p class=%@ bounds=%@ state=%@ name=%@ display=%@ represented=%@ type=%@ style=%@ rendering=%@ geometry=%@",
              self, NSStringFromClass(self.class), NSStringFromCGRect(self.bounds),
              LGKeyboardValue(self, @"state"), name ?: @"(nil)",
              display ?: @"(nil)", LGKeyboardValue(key, @"representedString"),
              LGKeyboardValue(key, @"type"),
              LGKeyboardValue(key, @"visualStyle"),
              LGKeyboardValue(key, @"rendering"),
              LGKeyboardValue(key, @"geometry"));
    }
    LGUpdateKeyboardKeyCorner(self);
}

- (void)didMoveToWindow {
    %orig;
    LGUpdateKeyboardKeyCorner(self);
    if (self.window) {
        LGRegenerateKeyboardKeyplaneIfNeeded([self keyplane]);
        LGKeyboardScheduleKeyplaneRefresh();
    }
}

- (void)layoutSubviews {
    %orig;
    LGUpdateKeyboardKeyCorner(self);
}

- (void)setBounds:(CGRect)bounds {
    %orig(bounds);
    LGUpdateKeyboardKeyCorner(self);
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);
    LGUpdateKeyboardKeyCorner(self);
}

%end

%hook UIKeyboard

- (void)layoutSubviews {
    %orig;
    LGKeyboardScheduleKeyplaneRefresh();
}

+ (CGSize)sizeForInterfaceOrientation:(NSInteger)orientation
                      ignoreInputView:(BOOL)ignoreInputView {
    BOOL outermost = gLGKeyboardSizingDepth++ == 0;

    CGSize size = %orig(orientation, ignoreInputView);

    gLGKeyboardSizingDepth--;

    if (outermost) {
        size = LGKeyboardReserveSize(size);
    }

    return size;
}

- (CGSize)intrinsicContentSize {
    BOOL outermost = gLGKeyboardSizingDepth++ == 0;

    CGSize size = %orig;

    gLGKeyboardSizingDepth--;

    if (outermost) {
        size = LGKeyboardReserveSize(size);
    }

    return size;
}

%end

%hook UIKBSplitImageView

- (void)setFrame:(CGRect)frame {
    if (LGKeyboardNeedsTopReserve() &&
        LGKeyboardIsDirectKeyplaneAtlas(self)) {
        CGFloat parentBoundsY = self.superview.bounds.origin.y;
        if (fabs(parentBoundsY) > 0.01 &&
            fabs(frame.origin.y - parentBoundsY) < 0.51) {
            frame.origin.y -= parentBoundsY;
        }
    }
    %orig(frame);
}

- (void)setCenter:(CGPoint)center {
    if (LGKeyboardNeedsTopReserve() &&
        LGKeyboardIsDirectKeyplaneAtlas(self)) {
        CGFloat parentBoundsY = self.superview.bounds.origin.y;
        CGFloat stockCenterY = CGRectGetHeight(self.bounds) * 0.5;
        CGFloat mirroredCenterY = stockCenterY + parentBoundsY;
        if (fabs(parentBoundsY) > 0.01 &&
            fabs(center.y - mirroredCenterY) < 0.51) {
            center.y -= parentBoundsY;
        }
    }
    %orig(center);
}

%end

%hook UIKeyboardLayoutStar

- (void)layoutSubviews {
    %orig;

    LGKeyboardRefreshCurrentKeyplane();
    LGKeyboardNormalizeKeyplaneAtlasFrames(LGKeyboardCurrentKeyplaneView());
    LGKeyboardScheduleKeyplaneRefresh();
}

%end

%hook UIKBTextStyle

- (NSString *)fontName {
    NSString *stockName = %orig;
    if (!lgHostEnabled(@"Keyboard") ||
        [stockName rangeOfString:@"Keycaps"
                         options:NSCaseInsensitiveSearch].location ==
            NSNotFound) {
        return stockName;
    }

    return LGKeyboardCompactFontName() ?: stockName;
}

%end

%ctor {
    gLGKeyboardBackdrops = [NSHashTable weakObjectsHashTable];
    gLGKeyboardVisualEffects = [NSHashTable weakObjectsHashTable];
    gLGKeyboardRegeneratedKeyplanes = [NSHashTable weakObjectsHashTable];
    gLGKeyboardScheduledKeyplanes = [NSHashTable weakObjectsHashTable];
    gLGKeyboardHookedKeyplaneClasses = [NSMutableSet set];
    LGLog(@"[keyboard] ctor process=%@ bundle=%@ renderer=%d geometry=%d keyView=%d backdrop=%d visualEffect=%d",
          NSProcessInfo.processInfo.processName,
          NSBundle.mainBundle.bundleIdentifier ?: @"(nil)",
          NSClassFromString(@"UIKBRenderer") != Nil,
          NSClassFromString(@"UIKBRenderGeometry") != Nil,
          NSClassFromString(@"UIKBKeyView") != Nil,
          NSClassFromString(@"UIKBBackdropView") != Nil,
          NSClassFromString(@"UIKBVisualEffectView") != Nil);
    lgObservePreferenceReload(^{

        [gLGKeyboardRegeneratedKeyplanes removeAllObjects];
        [gLGKeyboardScheduledKeyplanes removeAllObjects];
        gLGKeyboardKeycapRadius = 0.0;
        LGKeyboardSendVoid(NSClassFromString(@"UIKBRenderer"),
                           NSSelectorFromString(@"clearInternalCaches"));

        LGKeyboardRefreshReportedGeometry(UIScreen.mainScreen);
        for (UIView *stock in gLGKeyboardBackdrops.allObjects) {
            LGUpdateKeyboardGlass(stock);
        }
        for (UIView *effectView in gLGKeyboardVisualEffects.allObjects) {
            LGUpdateKeyboardVisualEffect(effectView);
        }
        LGRegenerateKeyboardKeyplaneIfNeeded(LGKeyboardCurrentKeyplaneView());
        LGKeyboardScheduleKeyplaneRefresh();
    });
}
