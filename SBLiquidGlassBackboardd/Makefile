include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SBLiquidGlassBackboardd

SBLiquidGlassBackboardd_FILES     = Tweak.mm LGSymbolResolver.mm
SBLiquidGlassBackboardd_CFLAGS    = -fobjc-arc -std=c++17 -fno-objc-arc-exceptions -DSBLIQUIDGLASS_DEBUG=$(SBLIQUIDGLASS_DEBUG)
SBLiquidGlassBackboardd_FRAMEWORKS = Metal QuartzCore CoreFoundation
SBLiquidGlassBackboardd_LDFLAGS   = -lc++

include $(THEOS_MAKE_PATH)/tweak.mk
