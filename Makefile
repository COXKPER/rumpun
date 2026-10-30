# rumpun — build and dev tasks.
# FLUTTER picks the SDK; override if yours lives elsewhere.
FLUTTER ?= flutter
BUNDLE := build/linux/x64/release/bundle

.PHONY: all build debug run apk test analyze clean

all: build

build:
	$(FLUTTER) build linux --release

apk:
	$(FLUTTER) build apk --release

debug:
	$(FLUTTER) build linux --debug

run: build
	$(BUNDLE)/rumpun

test:
	$(FLUTTER) test

analyze:
	$(FLUTTER) analyze

clean:
	$(FLUTTER) clean
