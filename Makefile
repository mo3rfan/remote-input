APP := remote-inputd

SHELL=bash -o pipefail

all: $(APP)

OUT = out
DEPDIR := $(OUT)/deps
GENDIR := $(OUT)/gen

DIRECTORIES = $(OUT) $(DEPDIR) $(GENDIR)
$(DIRECTORIES):
	mkdir -p $@

CC := gcc
CFLAGS = -std=c11 -Wall -O0 -g
CFLAGS += -Werror=format-security -Wshadow -Wformat
CPPFLAGS = -D_XOPEN_SOURCE=700

SRCS = remote-inputd.c logging.c input_device.c server.c

ifeq ($(TARGET), ANDROID)

ifndef ANDROID_NDK
$(error $$ANDROID_NDK not set! Please install the Android ndk)
endif

GCC_VERSION := 4.9

PLATFORM_TARGET_VERSION=21
PLATFORM_TARGET_ARCH=arm

TOOLCHAIN := $(ANDROID_NDK)/toolchains/arm-linux-androideabi-$(GCC_VERSION)/prebuilt/linux-x86_64
SYSROOT := $(ANDROID_NDK)/platforms/android-$(PLATFORM_TARGET_VERSION)/arch-$(PLATFORM_TARGET_ARCH)

CC := $(TOOLCHAIN)/bin/arm-linux-androideabi-gcc

CFLAGS += -I$(SYSROOT)/usr/include
CFLAGS += -fdiagnostics-color=auto
CFLAGS += -fpic -ffunction-sections -funwind-tables
CFLAGS += -fstack-protector -no-canonical-prefixes -march=armv7-a
CFLAGS += -mfpu=vfpv3-d16 -mfloat-abi=softfp -mthumb
CFLAGS += -fomit-frame-pointer -fno-strict-aliasing -finline-limit=64
CFLAGS += -Wa,--noexecstack
CFLAGS += -fPIE -ffunction-sections
CFLAGS += -funwind-tables -fstack-protector

CPPFLAGS += -DANDROID

LDFLAGS = -march=armv7-a -fPIE -pie -mthumb
LDFLAGS += --sysroot=$(SYSROOT) -L$(SYSROOT)/usr/lib
LDFLAGS += -Wl,-rpath-link=$(SYSROOT)/usr/lib -Wl,-rpath-link=$(OUT)
LDFLAGS += -Wl,--gc-sections -Wl,-z,nocopyreloc -no-canonical-prefixes
LDFLAGS += -Wl,--fix-cortex-a8 -Wl,--no-undefined -Wl,-z,noexecstack
LDFLAGS += -Wl,-z,relro -Wl,-z,now
endif  # TARGET == ANDROID

DEPS = $(patsubst %, $(DEPDIR)/%.d, $(basename $(SRCS)))

$(DEPDIR)/%.d: %.c | $(DEPDIR)
	$(CC) $(CFLAGS) -MG -MM -MP -MT $@ -MT $(OUT)/$(<:.c=.o) -MF $@ $<

-include $(DEPS)

$(OUT)/gen/keymap.h: device_key_mapping.h generate_keymap.awk | $(GENDIR)
	cpp $(CPPFLAGS) -P -imacros linux/input.h $< | sort -n | ./generate_keymap.awk > $@

$(OUT)/%.o: %.c | $(OUT)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

$(APP): $(patsubst %,$(OUT)/%.o, $(basename $(SRCS)))
	$(CC) $(LDFLAGS) -o $@ $^

forward_input: forward_input.c keysym_to_linux_code.c
	gcc $^ -L/usr/X11R6/lib -lX11 -g -Og -Wall -D_XOPEN_SOURCE=700 -std=c11 -o $@

clean:
	@rm -rf $(APP) $(OUT)
