.PHONY: build app run test clean

APP := HarpyDock.app
IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
ifeq ($(IDENTITY),)
IDENTITY := -
endif

VERSION := 1.0.0
RELEASE_BIN := .build/out/Products/Release/HarpyDock

build:
	swift build -c release

app: build
	rm -rf $(APP) dist
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/HarpyDock $(APP)/Contents/MacOS/HarpyDock
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/HarpyDock.icns $(APP)/Contents/Resources/HarpyDock.icns
	codesign --force --sign "$(IDENTITY)" $(APP)

run: app
	open $(APP)

universal:
	swift build -c release --arch arm64 --arch x86_64

release: universal
	rm -rf dist
	mkdir -p dist/HarpyDock.app/Contents/MacOS dist/HarpyDock.app/Contents/Resources
	cp $(RELEASE_BIN) dist/HarpyDock.app/Contents/MacOS/HarpyDock
	cp Resources/Info.plist dist/HarpyDock.app/Contents/Info.plist
	cp Resources/HarpyDock.icns dist/HarpyDock.app/Contents/Resources/HarpyDock.icns
	codesign --force --sign - dist/HarpyDock.app
	ditto -c -k --keepParent dist/HarpyDock.app dist/HarpyDock-$(VERSION)-macOS-universal.zip

test:
	swift test

clean:
	swift package clean
	rm -rf $(APP) dist
