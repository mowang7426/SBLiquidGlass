// SBLiquidGlass Test30
// Native Dynamic Island parent/sibling probe.
// NO UI changes. We found Test29's SBSystemApertureContainerView is 0x0.
// Test30 therefore inspects the FULL ancestor subtree, especially siblings
// of the container inside SBFTouchPassThroughView.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

static NSString * const kLog=@"/var/mobile/Documents/SBLiquidGlass_DI_Test30.log";

static void W(NSString *s){
    NSLog(@"[SBLiquidGlass-DI-Test30] %@",s);
    @try{
        if(![[NSFileManager defaultManager] fileExistsAtPath:kLog])
            [[NSFileManager defaultManager] createFileAtPath:kLog contents:nil attributes:nil];
        NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:kLog];
        if(h){ [h seekToEndOfFile]; [h writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];}
    }@catch(__unused NSException *e){}
}

static void Dump(UIView *v, NSInteger d, NSInteger max){
    if(!v||d>max)return;
    NSString *ind=@""; for(NSInteger i=0;i<d;i++) ind=[ind stringByAppendingString:@"  "];
    CALayer *l=v.layer;
    W([NSString stringWithFormat:@"%@%@ frame=%@ bounds=%@ hidden=%d alpha=%.2f bg=%@ sub=%lu | layer=%@ opacity=%.2f bg=%@ sub=%lu",
       ind,NSStringFromClass(v.class),NSStringFromCGRect(v.frame),NSStringFromCGRect(v.bounds),
       v.hidden,v.alpha,v.backgroundColor?(id)v.backgroundColor:@"nil",(unsigned long)v.subviews.count,
       NSStringFromClass(l.class),l.opacity,l.backgroundColor?(id)l.backgroundColor:@"nil",(unsigned long)l.sublayers.count]);
    for(UIView *s in v.subviews) Dump(s,d+1,max);
}

static void DumpLayer(CALayer *l, NSInteger d, NSInteger max){
    if(!l||d>max)return;
    NSString *ind=@""; for(NSInteger i=0;i<d;i++) ind=[ind stringByAppendingString:@"  "];
    W([NSString stringWithFormat:@"%@%@ frame=%@ bounds=%@ opacity=%.2f hidden=%d bg=%@ mask=%@ filters=%@ sub=%lu",
       ind,NSStringFromClass(l.class),NSStringFromCGRect(l.frame),NSStringFromCGRect(l.bounds),l.opacity,l.hidden,
       l.backgroundColor?(id)l.backgroundColor:@"nil",l.mask?NSStringFromClass(l.mask.class):@"nil",
       l.filters,(unsigned long)l.sublayers.count]);
    for(CALayer *s in l.sublayers) DumpLayer(s,d+1,max);
}

%hook SBSystemApertureContainerView
- (void)didMoveToWindow{
    %orig;
    @try{
        if(!self.window) return;
        static BOOL once=NO; if(once)return; once=YES;
        [[NSFileManager defaultManager] removeItemAtPath:kLog error:nil];
        W(@"========== TEST30 BEGIN ==========");
        W([NSString stringWithFormat:@"TARGET %@ frame=%@ bounds=%@",NSStringFromClass(self.class),NSStringFromCGRect(self.frame),NSStringFromCGRect(self.bounds)]);

        UIView *v=self;
        for(NSInteger level=0;v&&level<5;level++){
            W([NSString stringWithFormat:@"--- ANCESTOR LEVEL %ld %@ frame=%@ bounds=%@ subviews=%lu ---",
               (long)level,NSStringFromClass(v.class),NSStringFromCGRect(v.frame),NSStringFromCGRect(v.bounds),(unsigned long)v.subviews.count]);
            for(UIView *s in v.subviews){
                W([NSString stringWithFormat:@"SIBLING/PARENT-CHILD %@ frame=%@ bounds=%@ hidden=%d alpha=%.2f bg=%@ sub=%lu layer=%@ lbg=%@ filters=%@",
                   NSStringFromClass(s.class),NSStringFromCGRect(s.frame),NSStringFromCGRect(s.bounds),s.hidden,s.alpha,
                   s.backgroundColor?(id)s.backgroundColor:@"nil",(unsigned long)s.subviews.count,
                   NSStringFromClass(s.layer.class),s.layer.backgroundColor?(id)s.layer.backgroundColor:@"nil",s.layer.filters]);
            }
            if(level==0) Dump(self,0,3);
            v=v.superview;
        }

        UIView *p=self.superview;
        if(p){
            W(@"--- FULL SUBTREE OF IMMEDIATE PARENT depth 4 ---");
            Dump(p,0,4);
            W(@"--- FULL LAYER TREE OF IMMEDIATE PARENT depth 5 ---");
            DumpLayer(p.layer,0,5);
        }
        W(@"--- WINDOW / ROOT ---");
        UIWindow *w=self.window;
        W([NSString stringWithFormat:@"window=%@ frame=%@ bounds=%@ root=%@",
           NSStringFromClass(w.class),NSStringFromCGRect(w.frame),NSStringFromCGRect(w.bounds),
           w.rootViewController?NSStringFromClass(w.rootViewController.class):@"nil"]);
        W(@"========== TEST30 END ==========");
    }@catch(NSException *e){W([NSString stringWithFormat:@"EXCEPTION %@",e]);}
}
%end

%ctor{ NSLog(@"[SBLiquidGlass-DI-Test30] parent/sibling probe loaded; UI unchanged"); }
