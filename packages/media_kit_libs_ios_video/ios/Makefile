SHELL := /bin/bash

MPV_XCFRAMEWORKS_VERSION := v0.7.2
MPV_XCFRAMEWORKS_SHA256SUM := a0dbcddc0eaefa5534eb2bdc797e5386b1e0cd4057ed8f73aa2dd6105503dffb
MPV_ARCHIVE := .cache/xcframeworks/libmpv-xcframeworks-$(MPV_XCFRAMEWORKS_VERSION)-ios-universal.tar.gz
MPV_URL := https://github.com/media-kit/libmpv-darwin-build/releases/download/$(MPV_XCFRAMEWORKS_VERSION)/libmpv-xcframeworks_$(MPV_XCFRAMEWORKS_VERSION)_ios-universal-video-default.tar.gz

all: Frameworks/.prepared Frameworks/.symlinks

$(MPV_ARCHIVE):
	@set -euo pipefail; \
	mkdir -p .cache/xcframeworks; \
	rm -f .cache/xcframeworks/*.tmp; \
	echo "Downloading VoiceOver-friendly libmpv $(MPV_XCFRAMEWORKS_VERSION)..."; \
	curl --fail --location --retry 3 --retry-delay 2 "$(MPV_URL)" -o "$@.tmp"; \
	printf '%s  %s\n' "$(MPV_XCFRAMEWORKS_SHA256SUM)" "$@.tmp" | shasum -a 256 -c -; \
	mv "$@.tmp" "$@"

Frameworks/.prepared: $(MPV_ARCHIVE)
	@set -euo pipefail; \
	rm -rf Frameworks; \
	mkdir -p Frameworks; \
	tar -xzf "$(MPV_ARCHIVE)" --strip-components 1 -C Frameworks; \
	if [ ! -d Frameworks/Mpv.xcframework ]; then \
		echo "error: patched libmpv archive did not produce Frameworks/Mpv.xcframework" >&2; \
		find Frameworks -maxdepth 2 -print >&2 || true; \
		exit 1; \
	fi; \
	touch Frameworks/.prepared

Frameworks/.symlinks: Frameworks/.prepared create_framework_symlinks.sh
	@set -euo pipefail; \
	rm -rf Frameworks/.symlinks; \
	mkdir -p Frameworks/.symlinks/mpv; \
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv; \
	touch Frameworks/.symlinks

.PHONY: clean
clean:
	rm -rf .cache Frameworks
