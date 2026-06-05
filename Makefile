FLUTTER ?= flutter
DART ?= dart
DEVICE ?= macos
HAS_XCODEBUILD := $(shell xcodebuild -version >/dev/null 2>&1 && echo yes)
UNIT_TEST_TARGETS ?= test/core/article_queries_test.dart test/core/reading_metrics_test.dart test/core/source_health_test.dart test/data/api/api_client_test.dart test/data/local/local_store_test.dart test/data/repositories/rss_repository_login_test.dart test/data/repositories/rss_repository_pending_actions_test.dart test/data/repositories/rss_repository_smoke_test.dart
WIDGET_TEST_TARGETS ?= test/state/app_controller_bulk_read_test.dart test/state/app_controller_offline_queue_test.dart test/widgets/ai_settings_form_test.dart test/widgets/article_detail_view_test.dart test/widgets/responsive_home_shell_test.dart test/widgets/app_bootstrap_test.dart test/widgets/login_page_test.dart test/widgets/home_shortcuts_test.dart
WEB_TEST_TARGETS ?= test/data/local/local_store_web_test.dart
SMOKE_TEST_TARGETS ?= test/data/repositories/rss_repository_smoke_test.dart
TEST_ARGS ?= $(ARGS)
DART_DEFINES ?=

.PHONY: deps build build-android build-macos build-web test smoke lint deploy dev run run-web unit-test widget-test web-test require-xcodebuild require-android-sdk

deps:
	@if [ -f .dart_tool/package_config.json ] && [ -f pubspec.lock ]; then \
		$(FLUTTER) pub get --offline || $(FLUTTER) pub get; \
	else \
		$(FLUTTER) pub get || $(FLUTTER) pub get --offline; \
	fi

build: deps
ifeq ($(HAS_XCODEBUILD),yes)
	$(FLUTTER) build macos
else
	@echo "full Xcode is not available; building Web preview instead. Install full Xcode and run 'make build-macos' for a macOS app bundle."
	$(FLUTTER) build web --no-web-resources-cdn
endif

require-xcodebuild:
	@xcodebuild -version >/dev/null 2>&1 || { \
		echo "full Xcode is not available. Install full Xcode and run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer', or use 'make build-web' for a local preview."; \
		exit 2; \
	}

require-android-sdk:
	@if [ -d "$${ANDROID_HOME:-}" ] || [ -d "$${ANDROID_SDK_ROOT:-}" ] || [ -d "$$HOME/Library/Android/sdk" ] || [ -d "$$HOME/Android/Sdk" ]; then \
		exit 0; \
	fi; \
	echo "Android SDK not found. Install Android Studio / Android SDK and set ANDROID_HOME or ANDROID_SDK_ROOT, or use 'make build-web' for a local preview."; \
	exit 2

build-macos: deps require-xcodebuild
	$(FLUTTER) build macos

build-android: deps require-android-sdk
	$(FLUTTER) build apk

build-web: deps
	$(FLUTTER) build web --no-web-resources-cdn

unit-test: deps
	$(DART) test $(UNIT_TEST_TARGETS) $(TEST_ARGS)

widget-test: deps
	$(FLUTTER) test $(WIDGET_TEST_TARGETS) $(TEST_ARGS)

web-test: deps
	$(FLUTTER) test --platform chrome $(WEB_TEST_TARGETS) $(TEST_ARGS)

smoke: deps
	$(DART) test $(SMOKE_TEST_TARGETS) $(TEST_ARGS)

test: unit-test widget-test

lint: deps
	$(FLUTTER) analyze

deploy:
	@echo "No deploy target is configured for rss-copilot-client yet."

dev: run

run: deps
	$(FLUTTER) run -d $(DEVICE) $(DART_DEFINES)

run-web: deps
	$(FLUTTER) run -d chrome $(DART_DEFINES)
