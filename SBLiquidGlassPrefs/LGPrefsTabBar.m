#import "LGPrefsTabBar.h"
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGSharedSupport.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kLGPrefsTabBarHeight = 58.0;
static const CGFloat kLGPrefsTabBarCornerRadius = 29.0;

@interface LGPrefsTabBar ()
@property (nonatomic, strong) NSArray<NSDictionary *> *tabs;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) NSMutableArray<UILabel *> *tabLabels;
@property (nonatomic, strong) UIView *selectionPill;
@property (nonatomic, strong) LGLiveBackdropView *glassView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, assign) NSUInteger currentIndex;
@end

@implementation LGPrefsTabBar

- (instancetype)initWithTabs:(NSArray<NSDictionary *> *)tabs selectedIndex:(NSUInteger)selectedIndex {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _tabs = [tabs copy];
    _tabButtons = [NSMutableArray array];
    _tabLabels = [NSMutableArray array];
    _currentIndex = MIN(selectedIndex, (NSUInteger)(tabs.count > 0 ? tabs.count - 1 : 0));
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = UIColor.clearColor;
    [self setupBackdrop];
    [self setupButtons];
    [self setupSelectionPill];
    [self setSelectedIndex:_currentIndex animated:NO];
    return self;
}

- (void)setupBackdrop {
    _glassView = [[LGLiveBackdropView alloc] initWithFrame:CGRectZero
                                                  groupName:nil
                                                filterType:LGFilterTypeForHostPrefix(@"PrefsButton")];
    _glassView.translatesAutoresizingMaskIntoConstraints = NO;
    _glassView.userInteractionEnabled = NO;
    _glassView.layer.cornerRadius = kLGPrefsTabBarCornerRadius;
    _glassView.layer.cornerCurve = kCACornerCurveContinuous;
    _glassView.layer.masksToBounds = YES;
    [self addSubview:_glassView];

    _tintView = [[UIView alloc] initWithFrame:CGRectZero];
    _tintView.translatesAutoresizingMaskIntoConstraints = NO;
    _tintView.userInteractionEnabled = NO;
    _tintView.layer.cornerRadius = kLGPrefsTabBarCornerRadius;
    _tintView.layer.cornerCurve = kCACornerCurveContinuous;
    _tintView.layer.borderWidth = 0.75;
    _tintView.layer.borderColor = [[UIColor separatorColor] colorWithAlphaComponent:0.16].CGColor;
    _tintView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.07] : [UIColor colorWithWhite:1.0 alpha:0.55];
    }];
    [self addSubview:_tintView];

    [NSLayoutConstraint activateConstraints:@[
        [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_tintView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_tintView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_tintView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_tintView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.heightAnchor constraintEqualToConstant:kLGPrefsTabBarHeight],
    ]];
}

- (void)setupButtons {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    for (NSUInteger i = 0; i < _tabs.count; i++) {
        NSDictionary *tab = _tabs[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = (NSInteger)i;

        UIImageSymbolConfiguration *symbolConfig =
            [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightSemibold];
        UIImage *symbol = [UIImage systemImageNamed:tab[@"symbol"] withConfiguration:symbolConfig];

        UIStackView *vStack = [[UIStackView alloc] initWithArrangedSubviews:@[
            [[UIImageView alloc] initWithImage:symbol],
        ]];
        vStack.translatesAutoresizingMaskIntoConstraints = NO;
        vStack.axis = UILayoutConstraintAxisVertical;
        vStack.spacing = 2.0;
        vStack.alignment = UIStackViewAlignmentCenter;
        vStack.userInteractionEnabled = NO;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = tab[@"title"];
        label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        [vStack addArrangedSubview:label];
        [vStack setCustomSpacing:4.0 afterView:[vStack arrangedSubviews].firstObject];
        [_tabLabels addObject:label];

        [button addSubview:vStack];
        [NSLayoutConstraint activateConstraints:@[
            [vStack.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
            [vStack.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        ]];

        [button addTarget:self action:@selector(tabPressed:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
        [_tabButtons addObject:button];
    }
}

- (void)setupSelectionPill {
    _selectionPill = [[UIView alloc] initWithFrame:CGRectZero];
    _selectionPill.userInteractionEnabled = NO;
    _selectionPill.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.14];
        }
        return [UIColor colorWithWhite:1.0 alpha:0.55];
    }];
    _selectionPill.layer.cornerRadius = 20.0;
    _selectionPill.layer.cornerCurve = kCACornerCurveContinuous;
    [self insertSubview:_selectionPill aboveSubview:_tintView];
}

- (void)tabPressed:(UIButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    [self setSelectedIndex:index animated:YES];
    if (self.selectionHandler) {
        self.selectionHandler(index);
    }
}

- (void)setSelectedIndex:(NSUInteger)index animated:(BOOL)animated {
    NSUInteger count = _tabButtons.count;
    if (count == 0) return;
    _currentIndex = MIN(index, count - 1);

    for (NSUInteger i = 0; i < count; i++) {
        UIButton *button = _tabButtons[i];
        BOOL selected = (i == _currentIndex);
        UIColor *tint = selected ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        button.tintColor = tint;
        [button setTitleColor:tint forState:UIControlStateNormal];
        for (UIView *subview in button.subviews) {
            if ([subview isKindOfClass:[UIStackView class]]) {
                for (UIView *arranged in ((UIStackView *)subview).arrangedSubviews) {
                    if ([arranged isKindOfClass:[UIImageView class]]) {
                        ((UIImageView *)arranged).tintColor = tint;
                    } else if ([arranged isKindOfClass:[UILabel class]]) {
                        ((UILabel *)arranged).textColor = tint;
                    }
                }
            }
        }
    }

    CGRect targetFrame = CGRectInset([_tabButtons[_currentIndex] frame], 4.0, 5.0);
    if (animated && self.window) {
        [UIView animateWithDuration:0.30
                              delay:0.0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self->_selectionPill.frame = targetFrame;
        } completion:nil];
    } else {
        _selectionPill.frame = targetFrame;
    }
}

- (NSUInteger)selectedIndex {
    return _currentIndex;
}

- (void)updateTabTitles:(NSArray<NSString *> *)titles {
    NSUInteger count = MIN(_tabLabels.count, titles.count);
    for (NSUInteger i = 0; i < count; i++) {
        _tabLabels[i].text = titles[i];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glassView.frame = self.bounds;
    _tintView.frame = self.bounds;
    if (_tabButtons.count > 0 && _currentIndex < _tabButtons.count) {
        _selectionPill.frame = CGRectInset([_tabButtons[_currentIndex] frame], 4.0, 5.0);
    }
}

- (void)refreshGlassBackdrop {
    [_glassView applyFilters];
}

@end
