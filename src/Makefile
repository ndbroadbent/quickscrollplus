iPhonePrivateFrameworksPath=../../iphone-private-frameworks
networkpxPath=../../networkpx-read-only

iPhoneDevPath=/Developer/Platforms/iPhoneOS.platform/Developer
iPhoneSDKPath=$(iPhoneDevPath)/SDKs/iPhoneOS3.2.sdk
iPhoneSimDevPath=/Developer/Platforms/iPhoneSimulator.platform/Developer
iPhoneSimSDKPath=$(iPhoneSimDevPath)/SDKs/iPhoneSimulator3.2.sdk
MobileSubstratePath=../deb/Library/MobileSubstrate/DynamicLibraries
SharedSrcPath=$(networkpxPath)/src
PrefsBundlePath=../deb/System/Library/PreferenceBundles

Compiler=$(iPhoneDevPath)/usr/bin/gcc-4.2
CodeSign=ldid -S

Options=-arch armv6 \
	-std=gnu99 \
	-isysroot $(iPhoneSDKPath) \
	-F$(iPhoneSDKPath)/System/Library/PrivateFrameworks \
	-I$(iPhoneDevPath)/usr/include/gcc/darwin/default \
	-I$(iPhoneSDKPath)/usr/lib/gcc/arm-apple-darwin9/4.2.1/include \
	-I$(networkpxPath)/include \
	-I$(iPhonePrivateFrameworksPath) \
	-L/usr/local/lib \
	-Wall \
	-L/usr/lib/ \
	-mcpu=arm1176jzf-s \
	-O2

DontThumbSources=QSP.o

AllTargets=QuickScrollPlus Prefs

QuickScrollPlus_Sources=QSP.o
QuickScrollPlus_Target=$(MobileSubstratePath)/QuickScrollPlus.dylib
QuickScrollPlus_Options=-dynamiclib -framework CoreFoundation -framework Foundation -framework UIKit -framework CoreGraphics

Prefs_Sources=Pref.o $(networkpxPath)/hk.kennytm.grip/src/GPGetSmallAppIcon.o
Prefs_Target=$(PrefsBundlePath)/QuickScrollPlus.bundle/QuickScrollPlus
Prefs_Options=-bundle -framework CoreFoundation -framework Foundation -framework UIKit -framework CoreGraphics -framework SpringBoardServices -framework Preferences

#-----------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------
#------------------------------                                                     ------------------------------
#------------------------------   Don't touch anything after this line, thank you   ------------------------------
#------------------------------                                                     ------------------------------
#-----------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------

define CompileRule
	@case $(2) in \
		$(DontThumbSources)) \
			$(Compiler) -c $(3) -o $(1) $(2); \
			;; \
		*) \
			$(Compiler) -c $(3) -mthumb -o $(1) $(2); \
			;; \
	esac;
endef

define MakeTemplate
$$($(1)_Target):	$$($(1)_Sources)
	@$(Compiler) $(Options) $$($(1)_Options) -o $$@ $$^;
#	@strip -x $$@;
	$(CodeSign) $$@

endef

all:	$(foreach target,$(AllTargets),$($(target)_Target))

$(foreach target,$(AllTargets),$(eval $(call MakeTemplate,$(target))))


%.o::	%.m
	$(call CompileRule,$@,$^,$(Options))

%.o::	%.c
	$(call CompileRule,$@,$^,$(Options))

clean:
	rm -f *.o
