SHELL=bash -o pipefail

deps = $(patsubst %, $(DEPDIR)/%.d, $(basename $(1)))
objs = $(patsubst %, $(OUT)/%.o, $(basename $(1)))

.DEFAULT_GOAL = remote-inputd
.PHONY: all clean test

OUT = out
DEPDIR = $(OUT)/deps
GENDIR = $(OUT)/gen

CFLAGS += -std=gnu11
CFLAGS += \
	-Wall \
	-Wextra \
	-Wno-unused-parameter \
	-Wformat-security \
	-Wformat-nonliteral \
	-Wold-style-definition \
	-Wshadow \
	-Wstrict-prototypes
CFLAGS += -fstack-protector -fno-strict-aliasing
CFLAGS += -Wa,--noexecstack

CPPFLAGS += -D_XOPEN_SOURCE=700

CC_TARGETS = remote-inputd forward_input $(OUT)/test_runner
FWD_INPUT_SRCS = forward_input.c keysym_to_linux_code.c
REMOTE_INPUTD_SRCS = remote-inputd.c logging.c input_device.c server.c
TEST_SRCS = \
	test/server_test.c \
	test/shared_test.c \
	test/socket_mock.c \
	test/test_runner.c
TEST_DEPS = $(call objs, logging.c)
TEST_UNITS = $(call objs, server.c)

ifeq ($(TARGET), ANDROID)

ifndef ANDROID_NDK
$(error $$ANDROID_NDK not set! Please install the Android ndk)
endif

GCC_VERSION = 4.9

PLATFORM_TARGET_VERSION=27
PLATFORM_TARGET_ARCH=arm64

TOOLCHAIN = $(ANDROID_NDK)/toolchains/aarch64-linux-android-$(GCC_VERSION)
TARGET_PLATFORM = $(ANDROID_NDK)/platforms/android-$(PLATFORM_TARGET_VERSION)
SYSROOT_LD = $(TARGET_PLATFORM)/arch-$(PLATFORM_TARGET_ARCH)
SYSROOT = $(ANDROID_NDK)/sysroot

CC = $(TOOLCHAIN)/prebuilt/linux-x86_64/bin/aarch64-linux-android-gcc
TRIPLE = aarch64-linux-android
CFLAGS += -isystem $(SYSROOT)/usr/include/$(TRIPLE)
CFLAGS += -D__ANDROID_API__=$(PLATFORM_TARGET_VERSION)
CFLAGS += -fdiagnostics-color=auto
CFLAGS += -fpic -fPIE
CFLAGS += -no-canonical-prefixes

CPPFLAGS += -I$(SYSROOT)/usr/include
CPPFLAGS += -I$(SYSROOT)/usr/include/$(TRIPLE)
CPPFLAGS += -DANDROID

LDFLAGS += -fPIE -pie
LDFLAGS += --sysroot=$(SYSROOT_LD) -L$(SYSROOT_LD)/usr/lib
LDFLAGS += -Wl,-rpath-link=$(SYSROOT_LD)/usr/lib -Wl,-rpath-link=$(OUT)
LDFLAGS += -Wl,--gc-sections -Wl,-z,nocopyreloc -no-canonical-prefixes
LDFLAGS += -Wl,--no-undefined -Wl,-z,noexecstack
LDFLAGS += -Wl,-z,relro -Wl,-z,now
endif  # TARGET == ANDROID

$(DEPDIR)/%.d: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -MG -MM -MP -MT $@ -MT $(OUT)/$(<:.c=.o) -MF $@ $<

$(OUT)/gen/keymap.h: device_key_mapping.h generate_keymap.awk
	@mkdir -p $(dir $@)
	$(CPP) $(CPPFLAGS) -P -imacros linux/input.h $< | sort -n | \
		./generate_keymap.awk > $@

$(OUT)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(CC_TARGETS):
	$(CC) $(LDFLAGS) -o $@ $^

remote-inputd: $(call objs, $(REMOTE_INPUTD_SRCS))

$(call objs, $(TEST_SRCS)): CPPFLAGS += -I.
$(call objs, $(TEST_SRCS)): CFLAGS += $(shell pkg-config --cflags check)
$(OUT)/test_runner: $(call objs, $(TEST_SRCS)) $(TEST_UNITS) $(TEST_DEPS)
$(OUT)/test_runner: LDFLAGS += $(shell pkg-config --libs check)

forward_input: $(call objs, $(FWD_INPUT_SRCS))
forward_input: LDFLAGS += $(shell pkg-config --libs x11)

all: remote-inputd forward_input

clean:
	rm -rf $(CC_TARGETS) $(OUT)

test: $(OUT)/test_runner
	$<

ifneq ($(MAKECMDGOALS), clean)
-include $(call deps, $(REMOTE_INPUTD_SRCS) $(FWD_INPUT_SRCS) $(TEST_SRCS))
endif
