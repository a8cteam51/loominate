.PHONY: build release run clean probe devices dmg dist

build:
	Scripts/bundle.sh debug

release:
	Scripts/bundle.sh release

run: build
	open build/Loominate.app

clean:
	rm -rf .build build

# make probe FILE=path/to/recording.mp4
probe:
	build/Loominate.app/Contents/MacOS/Loominate --probe "$(FILE)"

devices:
	build/Loominate.app/Contents/MacOS/Loominate --devices

# Drag-to-Applications disk image from the current build (dev-signed; for local testing).
dmg: release
	Scripts/make-dmg.sh

# Developer ID build, notarized and stapled, plus the disk image. See Scripts/release.sh.
dist:
	Scripts/release.sh
