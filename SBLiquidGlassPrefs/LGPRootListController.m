#import "LGPRootListController.h"
#import "LGPSurfaceController.h"
#import "LGPrefsSurfaceCatalog.h"
#import "LGPrefsDataSupport.h"
#import "LGPrefsUIHelpers.h"
#import "LGPrefsTabBar.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void *kLGSliderRefKey = &kLGSliderRefKey;
static void *kLGValueLabelRefKey = &kLGValueLabelRefKey;
static void *kLGColorWellRefKey = &kLGColorWellRefKey;

typedef NS_ENUM(NSUInteger, LGTabIndex) {
    LGTabOverview = 0,
    LGTabGlass,
    LGTabSettings,
};

@interface LGPRootListController () <UIScrollViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *lg_pageContainer;
@property (nonatomic, strong) UIScrollView *lg_overviewScroll;
@property (nonatomic, strong) UIStackView *lg_overviewStack;
@property (nonatomic, strong) UIScrollView *lg_glassScroll;
@property (nonatomic, strong) UIStackView *lg_glassStack;
@property (nonatomic, strong) UIScrollView *lg_settingsScroll;
@property (nonatomic, strong) UIStackView *lg_settingsStack;
@property (nonatomic, strong) LGPrefsTabBar *lg_tabBar;
@property (nonatomic, strong) NSLayoutConstraint *lg_tabBarBottomConstraint;
@property (nonatomic, strong) UIView *lg_respringBar;
@property (nonatomic, strong) UISwitch *lg_globalToggle;
@property (nonatomic, strong) UIView *lg_overviewTogglesCard;
@property (nonatomic, assign) LGTabIndex lg_currentTab;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *lg_glassControls;
@property (nonatomic, assign) CFTimeInterval lg_lastFloatingGlassScrollRefreshTime;
@end

static NSString * const kLGRuntimeCacheUsageBytesKey = @"__runtime_cache_usage_bytes";

@implementation LGPRootListController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LGPrefsAppName();
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    if ([self respondsToSelector:@selector(table)] && self.table) self.table.hidden = YES;
    self.navigationItem.rightBarButtonItem = LGMakeCircularMenuItem(self, @selector(handleApplyPressed),
                                                                      @selector(handleResetPressed),
                                                                      LGLocalized(@"prefs.button.reset"));
    LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
    [self applyNavigationBarStyle];

    self.lg_currentTab = LGTabOverview;
    self.lg_glassControls = [NSMutableArray array];

    [self setupPageContainer];
    [self buildOverviewPage];
    [self buildGlassPage];
    [self buildSettingsPage];
    [self buildTabBar];
    [self buildRespringBar];

    LGObservePrefsNotifications(self);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLanguageChanged:)
                                                 name:kLGPrefsLanguageChangedNotification
                                               object:nil];
    [self switchToTab:LGTabOverview animated:NO];
    [self updateOverviewAvailabilityAnimated:NO];
    [self updateRespringBarAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyNavigationBarStyle];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.lg_globalToggle setOn:[self isGlobalEnabled] animated:NO];
    [self updateOverviewAvailabilityAnimated:NO];
    [self updateRespringBarAnimated:NO];
    LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
    LGScheduleRespringBarGlassRefresh(self.lg_respringBar);
    [self.lg_tabBar refreshGlassBackdrop];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyNavigationBarStyle {
    LGApplyNavigationBarAppearance(self.navigationItem);
}

- (NSArray *)specifiers {
    return @[];
}

#pragma mark - Layout scaffolding

- (void)setupPageContainer {
    self.lg_pageContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.lg_pageContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.lg_pageContainer.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.lg_pageContainer];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.lg_pageContainer.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.lg_pageContainer.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.lg_pageContainer.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];
    // bottom pinned to tab bar top later (see buildTabBar)
}

- (void)installPage:(UIScrollView *__strong *)scrollOut stack:(UIStackView *__strong *)stackOut {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.hidden = YES;
    scrollView.delegate = self;
    [self.lg_pageContainer addSubview:scrollView];

    UIStackView *stackView = [[UIStackView alloc] initWithFrame:CGRectZero];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 14.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.lg_pageContainer.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.lg_pageContainer.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.lg_pageContainer.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.lg_pageContainer.bottomAnchor],
        [stackView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:18.0],
        [stackView.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],
        [stackView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],
    ]];
    if (scrollOut) *scrollOut = scrollView;
    if (stackOut) *stackOut = stackView;
}

- (void)buildTabBar {
    NSArray<NSDictionary *> *tabs = @[
        @{ @"title": LGLocalized(@"prefs.tab.overview"), @"symbol": @"square.grid.2x2.fill" },
        @{ @"title": LGLocalized(@"prefs.tab.glass"), @"symbol": @"drop.fill" },
        @{ @"title": LGLocalized(@"prefs.tab.settings"), @"symbol": @"gearshape.fill" },
    ];
    self.lg_tabBar = [[LGPrefsTabBar alloc] initWithTabs:tabs selectedIndex:(NSUInteger)self.lg_currentTab];
    [self.view addSubview:self.lg_tabBar];
    __weak typeof(self) weakSelf = self;
    self.lg_tabBar.selectionHandler = ^(NSUInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf switchToTab:(LGTabIndex)index animated:YES];
    };

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.lg_tabBarBottomConstraint = [self.lg_tabBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-12.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.lg_tabBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [self.lg_tabBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        self.lg_tabBarBottomConstraint,
        [self.lg_pageContainer.bottomAnchor constraintEqualToAnchor:self.lg_tabBar.topAnchor constant:-8.0],
    ]];
}

- (void)buildRespringBar {
    LGInstallBottomRespringBarAboveView(self, self.lg_tabBar, &_lg_respringBar);
}

- (void)switchToTab:(LGTabIndex)index animated:(BOOL)animated {
    (void)animated;
    self.lg_currentTab = index;
    self.lg_overviewScroll.hidden = (index != LGTabOverview);
    self.lg_glassScroll.hidden = (index != LGTabGlass);
    self.lg_settingsScroll.hidden = (index != LGTabSettings);
    [self.lg_tabBar setSelectedIndex:(NSUInteger)index animated:animated];
    [self.lg_tabBar refreshGlassBackdrop];
    LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
}

#pragma mark - Shared row builders

- (UILabel *)lgControlTitleLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    return label;
}

- (UILabel *)lgControlSubtitleLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    return label;
}

- (UIView *)lgHeaderRowWithTitle:(UILabel *)titleLabel accessoryViews:(NSArray<UIView *> *)accessoryViews spacing:(CGFloat)spacing {
    UIView *headerRow = [[UIView alloc] initWithFrame:CGRectZero];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:titleLabel];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor].active = YES;
    [titleLabel.topAnchor constraintEqualToAnchor:headerRow.topAnchor].active = YES;
    [titleLabel.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor].active = YES;

    UIView *rightmostView = nil;
    for (UIView *accessoryView in accessoryViews) {
        [headerRow addSubview:accessoryView];
        accessoryView.translatesAutoresizingMaskIntoConstraints = NO;
        [accessoryView.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor].active = YES;
        if (!rightmostView) {
            [accessoryView.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor].active = YES;
        } else {
            [accessoryView.trailingAnchor constraintEqualToAnchor:rightmostView.leadingAnchor constant:-spacing].active = YES;
        }
        rightmostView = accessoryView;
    }
    if (rightmostView) {
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:rightmostView.leadingAnchor constant:-spacing].active = YES;
    } else {
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor].active = YES;
    }
    return headerRow;
}

- (UIView *)lgGroupedCardForItems:(NSArray<NSDictionary *> *)items {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = LGSubpageCardBackgroundColor();
    card.layer.cornerRadius = 23.25;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];

    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *body = [self lgBodyForItem:items[i]];
        [stack addArrangedSubview:body];
        if (i + 1 < items.count) {
            UIView *dividerRow = [[UIView alloc] initWithFrame:CGRectZero];
            dividerRow.translatesAutoresizingMaskIntoConstraints = NO;
            UIView *divider = LGMakeSectionDivider();
            [dividerRow addSubview:divider];
            [NSLayoutConstraint activateConstraints:@[
                [divider.leadingAnchor constraintEqualToAnchor:dividerRow.leadingAnchor constant:14.0],
                [divider.trailingAnchor constraintEqualToAnchor:dividerRow.trailingAnchor constant:-14.0],
                [divider.centerYAnchor constraintEqualToAnchor:dividerRow.centerYAnchor],
            ]];
            [stack addArrangedSubview:dividerRow];
        }
    }
    return card;
}

- (UIView *)lgSectionViewWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIView *sectionView = [[UIView alloc] initWithFrame:CGRectZero];
    sectionView.backgroundColor = UIColor.clearColor;
    UIStackView *sectionStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    sectionStack.axis = UILayoutConstraintAxisVertical;
    sectionStack.spacing = 3.0;
    sectionStack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    [sectionStack addArrangedSubview:titleLabel];
    if (subtitle.length) {
        UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        subtitleLabel.text = subtitle;
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textColor = [UIColor secondaryLabelColor];
        subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        [sectionStack addArrangedSubview:subtitleLabel];
    }
    [sectionView addSubview:sectionStack];
    [NSLayoutConstraint activateConstraints:@[
        [sectionStack.topAnchor constraintEqualToAnchor:sectionView.topAnchor constant:4.0],
        [sectionStack.leadingAnchor constraintEqualToAnchor:sectionView.leadingAnchor constant:2.0],
        [sectionStack.trailingAnchor constraintEqualToAnchor:sectionView.trailingAnchor constant:-2.0],
        [sectionStack.bottomAnchor constraintEqualToAnchor:sectionView.bottomAnchor constant:-1.0],
    ]];
    return sectionView;
}

- (UISwitch *)lgConfiguredToggleForItem:(NSDictionary *)item {
    UISwitch *toggle = [[LGPrefsSwitchClass() alloc] initWithFrame:CGRectZero];
    toggle.onTintColor = [UIColor systemBlueColor];
    toggle.on = [LGReadPreference(item[@"key"], item[@"default"]) boolValue];
    objc_setAssociatedObject(toggle, kLGDefaultValueKey, item[@"default"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(toggle, kLGPreferenceKeyKey, item[@"key"], OBJC_ASSOCIATION_COPY_NONATOMIC);

    __weak typeof(self) weakSelf = self;
    __weak UISwitch *weakToggle = toggle;
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UISwitch *sender = (UISwitch *)action.sender;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *key = item[@"key"];
        if ([key isEqualToString:@"AppIcons.Enabled"] && sender.isOn) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:LGLocalized(@"prefs.app_icons_warning.title")
                                 message:LGLocalized(@"prefs.app_icons_warning.body")
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LGLocalized(@"prefs.button.cancel")
                                                      style:UIAlertActionStyleCancel
                                                    handler:^(__unused UIAlertAction *alertAction) {
                [weakToggle setOn:NO animated:YES];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:LGLocalized(@"prefs.app_icons_warning.confirm")
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *alertAction) {
                [weakToggle setOn:YES animated:YES];
                LGWritePreferenceAndMaybeRequireRespring(key, @YES);
                [strongSelf handleRespringStateChanged:nil];
            }]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        LGWritePreferenceAndMaybeRequireRespring(key, @(sender.isOn));
        [strongSelf handleRespringStateChanged:nil];
    }] forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (UIView *)lgSwitchBodyForItem:(NSDictionary *)item {
    UIView *body = [[UIView alloc] initWithFrame:CGRectZero];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:stack];

    UILabel *titleLabel = [self lgControlTitleLabel:item[@"title"]];
    [stack addArrangedSubview:[self lgHeaderRowWithTitle:titleLabel
                                          accessoryViews:@[[self lgConfiguredToggleForItem:item]]
                                                 spacing:12.0]];
    [stack addArrangedSubview:[self lgControlSubtitleLabel:item[@"subtitle"]]];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:body.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-13.0],
    ]];
    return body;
}

- (void)lgHandleSliderValueLabelTapped:(UITapGestureRecognizer *)gesture {
    LGPresentSliderValuePrompt(self, (UILabel *)gesture.view);
}

- (UIView *)lgSliderBodyForItem:(NSDictionary *)item {
    UIView *body = [[UIView alloc] initWithFrame:CGRectZero];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:stack];

    NSNumber *stored = LGReadPreference(item[@"key"], item[@"default"]);
    CGFloat minValue = [item[@"min"] doubleValue];
    CGFloat maxValue = [item[@"max"] doubleValue];
    NSInteger decimals = [item[@"decimals"] integerValue];

    UISlider *slider = [[LGPrefsSliderClass() alloc] initWithFrame:CGRectZero];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = [stored doubleValue];
    slider.minimumTrackTintColor = [UIColor systemBlueColor];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    valueLabel.text = LGFormatSliderValue([stored doubleValue], decimals);
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
    valueLabel.textColor = [UIColor systemBlueColor];
    valueLabel.userInteractionEnabled = YES;

    objc_setAssociatedObject(slider, kLGDefaultValueKey, item[@"default"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kLGValueLabelKey, valueLabel, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(slider, kLGDecimalsKey, @(decimals), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGSliderKey, slider, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(valueLabel, kLGPreferenceKeyKey, item[@"key"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGMinValueKey, @(minValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGMaxValueKey, @(maxValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGDecimalsKey, @(decimals), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGControlTitleKey, item[@"title"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(valueLabel, kLGControlSubtitleKey, item[@"subtitle"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [valueLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lgHandleSliderValueLabelTapped:)]];

    UILabel *titleLabel = [self lgControlTitleLabel:item[@"title"]];
    [stack addArrangedSubview:[self lgHeaderRowWithTitle:titleLabel accessoryViews:@[valueLabel] spacing:12.0]];
    [stack addArrangedSubview:[self lgControlSubtitleLabel:item[@"subtitle"]]];
    [stack addArrangedSubview:slider];

    NSString *preferenceKey = item[@"key"];
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UISlider *sender = (UISlider *)action.sender;
        valueLabel.text = LGFormatSliderValue(sender.value, decimals);
    }] forControlEvents:UIControlEventValueChanged];
    UIControlEvents commitEvents = UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel;
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UISlider *sender = (UISlider *)action.sender;
        valueLabel.text = LGFormatSliderValue(sender.value, decimals);
        LGWritePreference(preferenceKey, @(sender.value));
    }] forControlEvents:commitEvents];

    [self.lg_glassControls addObject:@{
        @"slider": slider,
        @"valueLabel": valueLabel,
        @"default": item[@"default"],
        @"decimals": @(decimals),
    }];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:body.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-13.0],
    ]];
    return body;
}

- (UIView *)lgColorBodyForItem:(NSDictionary *)item {
    UIView *body = [[UIView alloc] initWithFrame:CGRectZero];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:stack];

    NSString *key = item[@"key"];
    NSString *fallback = item[@"default"] ?: @"#00000000";
    id stored = LGReadPreferenceObject(key, fallback);
    UIColorWell *well = [[UIColorWell alloc] initWithFrame:CGRectZero];
    well.selectedColor = LGColorFromRGBAHex([stored isKindOfClass:[NSString class]] ? stored : fallback);
    well.supportsAlpha = YES;
    [well.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [well.heightAnchor constraintEqualToConstant:32.0].active = YES;
    objc_setAssociatedObject(well, kLGColorWellRefKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [well addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UIColorWell *sender = (UIColorWell *)action.sender;
        LGWritePreferenceObject(key, LGRGBAHexFromColor(sender.selectedColor));
    }] forControlEvents:UIControlEventValueChanged];

    UILabel *titleLabel = [self lgControlTitleLabel:item[@"title"]];
    [stack addArrangedSubview:[self lgHeaderRowWithTitle:titleLabel accessoryViews:@[well] spacing:12.0]];
    [stack addArrangedSubview:[self lgControlSubtitleLabel:item[@"subtitle"]]];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:body.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-13.0],
    ]];
    return body;
}

- (NSString *)lgMenuSelectionTitleForItem:(NSDictionary *)item {
    NSString *key = item[@"key"];
    NSString *currentValue = nil;
    if ([key isEqualToString:@"LGPrefsLanguage"]) {
        currentValue = LGCurrentPrefsLanguageCode();
    } else {
        id storedValue = LGReadPreferenceObject(key, item[@"default"]);
        if ([storedValue isKindOfClass:[NSString class]]) {
            currentValue = storedValue;
        } else if ([storedValue respondsToSelector:@selector(stringValue)]) {
            currentValue = [storedValue stringValue];
        } else {
            currentValue = [[storedValue description] copy];
        }
    }
    for (NSDictionary *choice in item[@"choices"]) {
        if ([choice[@"value"] isEqualToString:currentValue]) {
            return choice[@"title"];
        }
    }
    for (NSDictionary *choice in item[@"choices"]) {
        if ([choice[@"value"] isEqualToString:item[@"default"]]) {
            return choice[@"title"];
        }
    }
    return @"";
}

- (UIView *)lgMenuBodyForItem:(NSDictionary *)item {
    UIView *body = [[UIView alloc] initWithFrame:CGRectZero];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:stack];

    UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    menuButton.translatesAutoresizingMaskIntoConstraints = NO;
    menuButton.showsMenuAsPrimaryAction = YES;
    menuButton.tintColor = [UIColor systemBlueColor];

    NSString *menuKey = item[@"key"];
    BOOL isLanguageMenu = [menuKey isEqualToString:@"LGPrefsLanguage"];
    __block NSString *selectedValue = isLanguageMenu
        ? [LGCurrentPrefsLanguageCode() copy]
        : ([menuKey isKindOfClass:[NSString class]]
            ? [[LGReadPreferenceObject(menuKey, item[@"default"]) description] copy]
            : [item[@"default"] copy]);

    void (^applyMenuSelectionTitle)(NSString *) = ^(NSString *newTitle) {
        if (!newTitle.length) return;
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *config = menuButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
            config.title = newTitle;
            config.image = [UIImage systemImageNamed:@"chevron.down"];
            config.imagePlacement = NSDirectionalRectEdgeTrailing;
            config.imagePadding = 6.0;
            config.baseForegroundColor = [UIColor systemBlueColor];
            config.background.backgroundColor = UIColor.clearColor;
            config.contentInsets = NSDirectionalEdgeInsetsMake(4.0, 8.0, 4.0, 8.0);
            menuButton.configuration = config;
        } else {
            [menuButton setTitle:newTitle forState:UIControlStateNormal];
        }
    };

    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    for (NSDictionary *choice in item[@"choices"]) {
        NSString *value = choice[@"value"];
        NSString *title = choice[@"title"];
        if (!value.length || !title.length) continue;
        UIAction *action = [UIAction actionWithTitle:title
                                               image:nil
                                          identifier:nil
                                             handler:^(__kindof UIAction * _Nonnull actionObj) {
            (void)actionObj;
            if (isLanguageMenu) {
                LGSetCurrentPrefsLanguageCode(value);
            } else {
                LGWritePreferenceObject(menuKey, value);
            }
            selectedValue = [value copy];
            applyMenuSelectionTitle(title);
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf updateRespringBarAnimated:YES];
            }
        }];
        if ([action respondsToSelector:@selector(setState:)]) {
            action.state = [value isEqualToString:selectedValue] ? UIMenuElementStateOn : UIMenuElementStateOff;
        }
        [actions addObject:action];
    }
    menuButton.menu = [UIMenu menuWithTitle:@"" children:actions];

    UILabel *titleLabel = [self lgControlTitleLabel:item[@"title"]];
    [stack addArrangedSubview:[self lgHeaderRowWithTitle:titleLabel accessoryViews:@[menuButton] spacing:12.0]];
    NSString *subtitle = item[@"subtitle"];
    if (subtitle.length) {
        [stack addArrangedSubview:[self lgControlSubtitleLabel:subtitle]];
    }
    applyMenuSelectionTitle([self lgMenuSelectionTitleForItem:item]);

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:body.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-13.0],
    ]];
    return body;
}

- (UIView *)lgNavBodyForItem:(NSDictionary *)item {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    button.contentEdgeInsets = UIEdgeInsetsZero;
    #pragma clang diagnostic pop

    NSString *actionName = item[@"action"];
    if (actionName.length) {
        SEL action = NSSelectorFromString(actionName);
        if ([self respondsToSelector:action]) {
            [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        }
    }

    UIView *body = [[UIView alloc] initWithFrame:CGRectZero];
    body.userInteractionEnabled = NO;
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:stack];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = [UIColor tertiaryLabelColor];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [chevron.widthAnchor constraintEqualToConstant:12.0].active = YES;
    [chevron.heightAnchor constraintEqualToConstant:20.0].active = YES;

    UILabel *titleLabel = [self lgControlTitleLabel:item[@"title"]];
    [stack addArrangedSubview:[self lgHeaderRowWithTitle:titleLabel accessoryViews:@[chevron] spacing:12.0]];
    NSString *subtitle = item[@"subtitle"];
    if (subtitle.length) {
        [stack addArrangedSubview:[self lgControlSubtitleLabel:subtitle]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:body.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-13.0],
    ]];

    [button addSubview:body];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [body.topAnchor constraintEqualToAnchor:button.topAnchor],
        [body.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
    ]];
    return button;
}

- (UIView *)lgBodyForItem:(NSDictionary *)item {
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"switch"]) {
        return [self lgSwitchBodyForItem:item];
    }
    if ([type isEqualToString:@"slider"]) {
        return [self lgSliderBodyForItem:item];
    }
    if ([type isEqualToString:@"color"]) {
        return [self lgColorBodyForItem:item];
    }
    if ([type isEqualToString:@"menu"]) {
        return [self lgMenuBodyForItem:item];
    }
    return [self lgNavBodyForItem:item];
}

#pragma mark - Overview page

- (void)buildOverviewPage {
    [self installPage:&_lg_overviewScroll stack:&_lg_overviewStack];

    // Hero
    [_lg_overviewStack addArrangedSubview:[self heroCard]];

    // 总开关
    [_lg_overviewStack addArrangedSubview:[self globalToggleCard]];

    // 系统界面
    [_lg_overviewStack addArrangedSubview:[self lgSectionViewWithTitle:LGLocalized(@"prefs.overview.system.title")
                                                              subtitle:LGLocalized(@"prefs.overview.system.subtitle")]];
    UIView *togglesCard = [self lgGroupedCardForItems:LGOverviewToggleItems()];
    self.lg_overviewTogglesCard = togglesCard;
    [_lg_overviewStack addArrangedSubview:togglesCard];

    [_lg_overviewStack addArrangedSubview:[self overviewFooterView]];
}

- (UIView *)heroCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = UIColor.clearColor;

    UILabel *eyebrow = [[UILabel alloc] initWithFrame:CGRectZero];
    eyebrow.text = LGLocalized(@"prefs.hero.eyebrow");
    eyebrow.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    eyebrow.textColor = [UIColor secondaryLabelColor];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = LGPrefsAppName();
    titleLabel.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightBlack];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitleLabel.text = LGLocalized(@"prefs.hero.subtitle");
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *highlightStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    highlightStack.axis = UILayoutConstraintAxisHorizontal;
    highlightStack.spacing = 8.0;
    highlightStack.alignment = UIStackViewAlignmentLeading;
    highlightStack.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray<NSString *> *highlights = @[
        LGLocalized(@"prefs.hero.highlight.1"),
        LGLocalized(@"prefs.hero.highlight.2"),
        LGLocalized(@"prefs.hero.highlight.3"),
    ];
    for (NSString *text in highlights) {
        UILabel *chipLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        chipLabel.text = text;
        chipLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        chipLabel.textColor = [UIColor systemBlueColor];

        UIView *chip = [[UIView alloc] initWithFrame:CGRectZero];
        chip.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
        chip.layer.cornerRadius = 13.0;
        chip.layer.cornerCurve = kCACornerCurveContinuous;
        chip.layer.masksToBounds = YES;
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [chip addSubview:chipLabel];
        chipLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [chipLabel.topAnchor constraintEqualToAnchor:chip.topAnchor constant:4.0],
            [chipLabel.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:11.0],
            [chipLabel.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-11.0],
            [chipLabel.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor constant:-4.0],
        ]];
        [highlightStack addArrangedSubview:chip];
    }

    [card addSubview:eyebrow];
    [card addSubview:titleLabel];
    [card addSubview:subtitleLabel];
    [card addSubview:highlightStack];
    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.topAnchor constraintEqualToAnchor:card.topAnchor constant:22.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [eyebrow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [titleLabel.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:10.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [highlightStack.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:16.0],
        [highlightStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [highlightStack.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-20.0],
        [highlightStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22.0],
    ]];
    return card;
}

- (UIView *)globalToggleCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = LGSubpageCardBackgroundColor();
    card.layer.cornerRadius = 23.25;
    card.layer.cornerCurve = kCACornerCurveContinuous;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = LGLocalized(@"prefs.overview.global.title");
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitleLabel.text = LGLocalized(@"prefs.overview.global.subtitle");
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];

    UISwitch *toggle = [[LGPrefsSwitchClass() alloc] initWithFrame:CGRectZero];
    toggle.onTintColor = [UIColor systemBlueColor];
    toggle.on = [self isGlobalEnabled];
    self.lg_globalToggle = toggle;
    __weak typeof(self) weakSelf = self;
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        UISwitch *sender = (UISwitch *)action.sender;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        LGWritePreferenceAndMaybeRequireRespring(@"Global.Enabled", @(sender.isOn));
        [strongSelf updateOverviewAvailabilityAnimated:YES];
        [strongSelf updateRespringBarAnimated:YES];
    }] forControlEvents:UIControlEventValueChanged];

    UIView *headerRow = [[UIView alloc] initWithFrame:CGRectZero];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:titleLabel];
    [headerRow addSubview:toggle];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-12.0],
        [toggle.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [toggle.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [toggle.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:12.0],
    ]];
    [stack addArrangedSubview:headerRow];
    [stack addArrangedSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:13.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-13.0],
    ]];
    return card;
}

- (UIView *)overviewFooterView {
    unsigned long long bytes = 0;
    id storedValue = LGReadPreferenceObject(kLGRuntimeCacheUsageBytesKey, @(0));
    if ([storedValue isKindOfClass:[NSNumber class]]) {
        bytes = [(NSNumber *)storedValue unsignedLongLongValue];
    }
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleMemory;
    formatter.allowedUnits = NSByteCountFormatterUseMB | NSByteCountFormatterUseGB | NSByteCountFormatterUseKB;
    formatter.includesUnit = YES;
    formatter.includesCount = YES;
    NSString *usage = [formatter stringFromByteCount:(long long)bytes];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor tertiaryLabelColor];
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    label.text = [NSString stringWithFormat:LGLocalized(@"prefs.root.runtime_cache_footer"), usage];
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    [container addSubview:label];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:2.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
    ]];
    return container;
}

- (void)updateOverviewAvailabilityAnimated:(BOOL)animated {
    BOOL enabled = [self isGlobalEnabled];
    void (^changes)(void) = ^{
        self.lg_overviewTogglesCard.alpha = enabled ? 1.0 : 0.42;
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:changes];
    } else {
        changes();
    }
    self.lg_overviewTogglesCard.userInteractionEnabled = enabled;
}

#pragma mark - Glass page

- (void)buildGlassPage {
    [self installPage:&_lg_glassScroll stack:&_lg_glassStack];

    // Header with reset
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = UIColor.clearColor;
    UIStackView *headerStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    headerStack.axis = UILayoutConstraintAxisVertical;
    headerStack.spacing = 3.0;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:headerStack];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = LGLocalized(@"prefs.glass.title");
    titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitleLabel.text = LGLocalized(@"prefs.glass.subtitle");
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton setTitle:LGLocalized(@"prefs.glass.reset") forState:UIControlStateNormal];
    [resetButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    resetButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
    resetButton.layer.cornerRadius = 15.0;
    resetButton.layer.cornerCurve = kCACornerCurveContinuous;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    resetButton.contentEdgeInsets = UIEdgeInsetsMake(5.0, 14.0, 5.0, 14.0);
    #pragma clang diagnostic pop
    [resetButton addTarget:self action:@selector(handleGlassResetPressed) forControlEvents:UIControlEventTouchUpInside];

    UIView *headerRow = [[UIView alloc] initWithFrame:CGRectZero];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:titleLabel];
    [headerRow addSubview:resetButton];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:resetButton.leadingAnchor constant:-12.0],
        [resetButton.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [resetButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
    ]];

    [headerStack addArrangedSubview:headerRow];
    [headerStack addArrangedSubview:subtitleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [headerStack.topAnchor constraintEqualToAnchor:header.topAnchor constant:4.0],
        [headerStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:2.0],
        [headerStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-2.0],
        [headerStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-1.0],
    ]];
    [_lg_glassStack addArrangedSubview:header];

    // 全局玻璃参数
    [_lg_glassStack addArrangedSubview:[self lgGroupedCardForItems:LGGlobalGlassTuningItems()]];

    // 颜色调节
    [_lg_glassStack addArrangedSubview:[self lgSectionViewWithTitle:LGLocalized(@"prefs.glass.colors.title")
                                                           subtitle:LGLocalized(@"prefs.glass.colors.subtitle")]];
    [_lg_glassStack addArrangedSubview:[self lgGroupedCardForItems:LGGlobalColorTuningItems()]];
}

- (void)handleGlassResetPressed {
    LGPresentResetConfirmationWithBody(self,
        [NSString stringWithFormat:LGLocalized(@"prefs.reset_confirm.surface_body_format"), LGLocalized(@"prefs.glass.title")],
        @selector(performAnimatedGlassReset));
}

- (void)performAnimatedGlassReset {
    for (NSDictionary *control in self.lg_glassControls) {
        UISlider *slider = control[@"slider"];
        UILabel *valueLabel = control[@"valueLabel"];
        NSNumber *defaultValue = control[@"default"];
        NSNumber *decimals = control[@"decimals"];
        if (slider && defaultValue) {
            LGAnimateSliderToDefault(slider, [defaultValue doubleValue], valueLabel, decimals ? [decimals integerValue] : 0);
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.67 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LGResetPreferencesForKeys(LGGlobalGlassResetKeys());
        [self rebuildGlassPage];
    });
}

- (void)rebuildGlassPage {
    for (UIView *subview in [self.lg_glassStack.arrangedSubviews copy]) {
        [self.lg_glassStack removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    [self.lg_glassControls removeAllObjects];
    [self buildGlassPage];
}

#pragma mark - Settings page

- (void)buildSettingsPage {
    [self installPage:&_lg_settingsScroll stack:&_lg_settingsStack];

    [_lg_settingsStack addArrangedSubview:[self lgSectionViewWithTitle:LGLocalized(@"prefs.settings.appearance.title") subtitle:nil]];
    [_lg_settingsStack addArrangedSubview:[self lgGroupedCardForItems:LGAppearanceSettingsItems()]];

    [_lg_settingsStack addArrangedSubview:[self lgSectionViewWithTitle:LGLocalized(@"prefs.settings.performance.title") subtitle:nil]];
    [_lg_settingsStack addArrangedSubview:[self lgGroupedCardForItems:LGPerformanceSettingsItems()]];

    [_lg_settingsStack addArrangedSubview:[self lgSectionViewWithTitle:LGLocalized(@"prefs.settings.data.title") subtitle:nil]];
    [_lg_settingsStack addArrangedSubview:[self lgGroupedCardForItems:LGDataSettingsItems()]];
}

#pragma mark - Preferences helpers

- (BOOL)isGlobalEnabled {
    return [LGReadPreference(@"Global.Enabled", @NO) boolValue];
}

- (void)handleApplyPressed {
    LGApplyGlobalGlassDefaults();
    LGForceSynchronizePreferences();
}

- (void)handleResetPressed {
    LGPresentResetConfirmation(self);
}

- (void)handleResetAllPressed {
    LGPresentResetConfirmation(self);
}

- (void)handleRespringPressed {
    LGSetRespringBarDismissed(YES);
    [self updateRespringBarAnimated:YES];
    LGPresentRespringConfirmation(self);
}

- (void)handleLaterPressed {
    LGSetRespringBarDismissed(YES);
    [self updateRespringBarAnimated:YES];
}

- (void)handlePrefsUIRefresh:(NSNotification *)notification {
    (void)notification;
    if (!self.isViewLoaded) return;
    [self.lg_globalToggle setOn:[self isGlobalEnabled] animated:YES];
    [self updateOverviewAvailabilityAnimated:YES];
    [self rebuildGlassPage];
    [self rebuildSettingsPage];
    [self updateRespringBarAnimated:YES];
}

- (void)handleRespringStateChanged:(NSNotification *)notification {
    (void)notification;
    [self updateRespringBarAnimated:YES];
}

- (void)handleLanguageChanged:(NSNotification *)notification {
    (void)notification;
    if (!self.isViewLoaded) return;
    self.title = LGPrefsAppName();
    [self.lg_tabBar updateTabTitles:@[
        LGLocalized(@"prefs.tab.overview"),
        LGLocalized(@"prefs.tab.glass"),
        LGLocalized(@"prefs.tab.settings"),
    ]];
    [self rebuildOverviewPage];
    [self rebuildGlassPage];
    [self rebuildSettingsPage];
    [self updateRespringBarAnimated:NO];
}

- (void)rebuildOverviewPage {
    for (UIView *subview in [self.lg_overviewStack.arrangedSubviews copy]) {
        [self.lg_overviewStack removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    [self buildOverviewPage];
    [self.lg_globalToggle setOn:[self isGlobalEnabled] animated:NO];
    [self updateOverviewAvailabilityAnimated:NO];
}

- (void)rebuildSettingsPage {
    for (UIView *subview in [self.lg_settingsStack.arrangedSubviews copy]) {
        [self.lg_settingsStack removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    [self buildSettingsPage];
}

- (void)updateRespringBarAnimated:(BOOL)animated {
    BOOL shouldShow = LGNeedsRespring() && !LGRespringBarDismissed();
    if (!self.lg_respringBar) return;
    LGRefreshRespringBarGlass(self.lg_respringBar);
    if (shouldShow == !self.lg_respringBar.hidden) {
        if (shouldShow) {
            LGScheduleRespringBarGlassRefresh(self.lg_respringBar);
        }
        return;
    }
    if (shouldShow) {
        self.lg_respringBar.hidden = NO;
        LGRefreshRespringBarGlass(self.lg_respringBar);
        if (animated) {
            [UIView animateWithDuration:0.22 animations:^{
                self.lg_respringBar.alpha = 1.0;
                self.lg_respringBar.transform = CGAffineTransformIdentity;
            } completion:^(__unused BOOL finished) {
                LGRefreshRespringBarGlass(self.lg_respringBar);
            }];
        } else {
            self.lg_respringBar.alpha = 1.0;
            self.lg_respringBar.transform = CGAffineTransformIdentity;
            LGRefreshRespringBarGlass(self.lg_respringBar);
        }
        LGScheduleRespringBarGlassRefresh(self.lg_respringBar);
    } else {
        void (^hideBlock)(void) = ^{
            self.lg_respringBar.alpha = 0.0;
            self.lg_respringBar.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
        };
        void (^completion)(BOOL) = ^(BOOL finished) {
            (void)finished;
            self.lg_respringBar.hidden = YES;
        };
        if (animated) {
            [UIView animateWithDuration:0.18 animations:hideBlock completion:completion];
        } else {
            hideBlock();
            completion(YES);
        }
    }
}

#pragma mark - Import / export

- (void)exportPreferences {
    LGPresentPreferencesExport(self);
}

- (void)importPreferences {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!LGImportPreferencesFromURL(self, url)) return;
    [self handlePrefsUIRefresh:nil];
    [self updateRespringBarAnimated:NO];
    LGPresentInfoSheet(self,
                       LGLocalized(@"prefs.misc.import_prefs.title"),
                       LGLocalized(@"prefs.import_prefs.success"));
}

#pragma mark - Surface navigation (kept for compatibility)

- (void)pushSurfaceWithIdentifier:(NSString *)identifier {
    LGPSurfaceController *controller = [[LGPSurfaceController alloc] initWithTitle:LGPrefsSurfaceTitle(identifier)
                                                                          subtitle:LGPrefsSurfaceSubtitle(identifier)
                                                                         tintColor:LGPrefsSurfaceTintColor(identifier)
                                                                        identifier:identifier
                                                                             items:LGPrefsSurfaceItems(identifier)];
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)openHomescreen { [self pushSurfaceWithIdentifier:LGPrefsSurfaceHomescreen]; }
- (void)openLockscreen { [self pushSurfaceWithIdentifier:LGPrefsSurfaceLockscreen]; }
- (void)openAppLibrary { [self pushSurfaceWithIdentifier:LGPrefsSurfaceAppLibrary]; }
- (void)openSurfaces { [self pushSurfaceWithIdentifier:LGPrefsSurfaceSurfaces]; }
- (void)openMoreOptions { [self pushSurfaceWithIdentifier:LGPrefsSurfaceMoreOptions]; }
- (void)openPrefsSettings { [self pushSurfaceWithIdentifier:LGPrefsSurfaceSettings]; }

#pragma mark - Scroll / glass refresh

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lg_lastFloatingGlassScrollRefreshTime < (1.0 / 30.0)) return;
    self.lg_lastFloatingGlassScrollRefreshTime = now;
    LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
    LGRefreshRespringBarGlass(self.lg_respringBar);
    [self.lg_tabBar refreshGlassBackdrop];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
        LGRefreshRespringBarGlass(self.lg_respringBar);
        [self.lg_tabBar refreshGlassBackdrop];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    LGRefreshCircularBackItem(self.navigationItem.rightBarButtonItem);
    LGRefreshRespringBarGlass(self.lg_respringBar);
    [self.lg_tabBar refreshGlassBackdrop];
}

@end
