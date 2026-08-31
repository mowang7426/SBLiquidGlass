include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SBLiquidGlassPrefs

LG_PACKAGE_VERSION := $(shell sed -n 's/^Version: //p' ../control | head -n 1)

PREF_LOCAL_FILES := LGPRootListController.m LGPSurfaceController.m LGPrefsSurfaceCatalog.m LGPrefsDataSupport.m \
                    LGPrefsUIHelpers.m LGPrefsLiquidSlider.m LGPrefsLiquidSwitch.m LGPrefsTabBar.m
PREF_SHARED_FILES := ../Shared/LGSharedSupport.m ../Shared/LGLiveBackdropView.m
SBLiquidGlassPrefs_FILES = $(PREF_LOCAL_FILES) $(PREF_SHARED_FILES)
SBLiquidGlassPrefs_FRAMEWORKS = UIKit QuartzCore CoreText CoreGraphics CoreMotion
SBLiquidGlassPrefs_INSTALL_PATH = /Library/PreferenceBundles
SBLiquidGlassPrefs_CFLAGS = -fobjc-arc -I../Shared -DLG_PACKAGE_VERSION=@\"$(LG_PACKAGE_VERSION)\" -DSBLIQUIDGLASS_DEBUG=$(SBLIQUIDGLASS_DEBUG)
SBLiquidGlassPrefs_LDFLAGS += -Wl,-undefined,dynamic_lookup

SBLiquidGlassPrefs_RESOURCE_FILES = ../changelogs

include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	cp Resources/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/SBLiquidGlassPrefs.plist
	ldid -S $(THEOS_STAGING_DIR)/Library/PreferenceBundles/SBLiquidGlassPrefs.bundle/SBLiquidGlassPrefs
