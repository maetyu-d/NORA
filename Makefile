CC := clang
CFLAGS := -std=c11 -O2 -Wall -Wextra -Wpedantic
LDFLAGS := -framework AudioToolbox -framework CoreFoundation -lm -lpthread
GUI_LDFLAGS := -framework Cocoa -framework AudioToolbox -framework CoreFoundation -lm -lpthread
TARGET := bytebeat_synth
GUI_TARGET := bytebeat_synth_gui
APP_BUNDLE := NORA.app
APP_EXECUTABLE := NORA
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_PLIST := $(APP_CONTENTS)/Info.plist

all: $(TARGET) $(GUI_TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

$(GUI_TARGET): gui_main.m main.c
	$(CC) $(CFLAGS) -fobjc-arc $< -o $@ $(GUI_LDFLAGS)

app: $(GUI_TARGET)
	mkdir -p "$(APP_MACOS)" "$(APP_RESOURCES)"
	cp "$(GUI_TARGET)" "$(APP_MACOS)/$(APP_EXECUTABLE)"
	cp "Info.plist" "$(APP_PLIST)"

clean:
	rm -f $(TARGET) $(GUI_TARGET)
	rm -rf "$(APP_BUNDLE)"

.PHONY: all app clean
