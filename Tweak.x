

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef NS_OPTIONS(NSUInteger, SBSRelaunchActionOptions) {
    SBSRelaunchActionOptionsNone                   = 0,
    SBSRelaunchActionOptionsRestartRenderServer    = 1 << 0,
    SBSRelaunchActionOptionsSnapshotTransition     = 1 << 1,
    SBSRelaunchActionOptionsFadeToBlackTransition  = 1 << 2,
};

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(SBSRelaunchActionOptions)options targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

static NSString * const kLGRespringNote = @"dylv.sbliquidglassprefs/Respring";

static void LG_requestRespring(void) {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);

    Class actionClass  = objc_getClass("SBSRelaunchAction");
    Class serviceClass = objc_getClass("FBSSystemService");
    if (!actionClass || !serviceClass) return;

    SBSRelaunchAction *restart =
        [actionClass actionWithReason:@"SBLiquidGlass"
                              options:(SBSRelaunchActionOptionsRestartRenderServer |
                                       SBSRelaunchActionOptionsFadeToBlackTransition)
                            targetURL:nil];
    if (!restart) return;
    [[serviceClass sharedService] sendActions:[NSSet setWithObject:restart] withResult:nil];
}

static void LG_respringRequested(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ LG_requestRespring(); });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    LG_respringRequested, (__bridge CFStringRef)kLGRespringNote,
                                    NULL, CFNotificationSuspensionBehaviorCoalesce);
}
