#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 悬浮在设置页底部的液态玻璃 Tab 栏（总览 / 玻璃效果 / 设置）。
@interface LGPrefsTabBar : UIView

- (instancetype)initWithTabs:(NSArray<NSDictionary *> *)tabs
               selectedIndex:(NSUInteger)selectedIndex;

/// 每个 tab：@{ @"title": NSString, @"symbol": NSString }
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSUInteger index);

- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated;
- (NSUInteger)selectedIndex;
- (void)updateTabTitles:(NSArray<NSString *> *)titles;

/// 滚动时刷新玻璃材质（与其它液态按钮保持一致）。
- (void)refreshGlassBackdrop;

@end

NS_ASSUME_NONNULL_END
