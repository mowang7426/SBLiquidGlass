export TARGET ?= iphone:clang:16.5:14.0
export ARCHS ?= arm64 arm64e
SBLIQUIDGLASS_DEBUG ?= 0
export SBLIQUIDGLASS_DEBUG

INSTALL_TARGET_PROCESSES = backboardd SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = sbliquidglass

sbliquidglass_FILES     = Tweak.x Hooks/Dock.x Hooks/Folder.x Hooks/AppIcons.x Hooks/Banner.x Hooks/ControlCenter.x \
                      Hooks/AppLibrary.x Hooks/SearchPill.x Hooks/Spotlight.x Hooks/Widgets.x Hooks/ContextMenu.x \
                      Hooks/QuickActions.x Hooks/Passcode.x Hooks/Clock.x Hooks/Alerts.x \
                      Hooks/PreferencesControls.x Hooks/CoverSheet.x Hooks/TabBar.x \
                      Hooks/Keyboard.x \
                      SBLiquidGlassPrefs/LGPrefsLiquidSlider.m \
                      SBLiquidGlassPrefs/LGPrefsLiquidSwitch.m \
                      Shared/LGGlassKit.x Shared/LGLiveBackdropView.m \
                      Shared/LGSharedSupport.m
sbliquidglass_CFLAGS    = -fobjc-arc -DSBLIQUIDGLASS_DEBUG=$(SBLIQUIDGLASS_DEBUG)
sbliquidglass_FRAMEWORKS = UIKit QuartzCore CoreText CoreGraphics CoreMotion

include $(THEOS)/makefiles/tweak.mk
SUBPROJECTS += SBLiquidGlassBackboardd
SUBPROJECTS += SBLiquidGlassRWB
SUBPROJECTS += SBLiquidGlassPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# originally i tried to add `release::` here but apparently that keeps breaking for whatever fucking reason so i decided to create `release.sh`
