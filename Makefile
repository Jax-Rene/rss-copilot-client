FLUTTER ?= flutter
DART ?= dart

.PHONY: deps build test lint deploy dev run unit-test widget-test

deps:
	$(FLUTTER) pub get

build: deps
	$(FLUTTER) build web

unit-test: deps
	$(DART) test test/core/article_queries_test.dart test/data/local/local_store_test.dart

widget-test: deps
	$(FLUTTER) test --platform chrome test/widgets/responsive_home_shell_test.dart

test: unit-test widget-test

lint: deps
	$(FLUTTER) analyze

deploy:
	@echo "No deploy target is configured for rss-copilot-client yet."

dev: run

run: deps
	$(FLUTTER) run -d chrome
