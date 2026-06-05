import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/data/api/api_client.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/app_section.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/entry_page_cursor.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/feed_source.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/models/snapshot.dart';
import 'package:rss_copilot_client/src/models/translation_segment.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:rss_copilot_client/src/state/app_controller.dart';
import 'package:rss_copilot_client/src/state/providers.dart';
import 'package:rss_copilot_client/src/ui/home/home_page.dart';

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  testWidgets('desktop shortcuts drive reader actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(find.text('2 篇当前列表'), findsOneWidget);
    expect(find.text('2 未读'), findsOneWidget);
    expect(find.text('未读剩余约 2 分钟'), findsOneWidget);
    expect(find.text('1 分钟'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    expect(controller.state.selectedEntryId, 2);
    expect(repository.openedEntryIds, [2]);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[2]!.isSaved, isTrue);
    expect(find.text('已加入稍后读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[2]!.isSaved, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[2]!.isRead, isFalse);
    expect(find.text('已标记未读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(repository.markReadEntryIds, [2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();

    expect(controller.state.selectedEntryId, 1);
    expect(repository.openedEntryIds, [2, 1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'analysis');
    await tester.pump();

    expect(controller.state.searchQuery, 'analysis');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.state.searchQuery, isEmpty);
  });

  testWidgets('home and end shortcuts jump across the reading queue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeOlderFeedUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.visibleEntries.map((entry) => entry.id), [1, 2, 5]);
    expect(controller.state.selectedEntryId, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 5);
    expect(repository.openedEntryIds, [5]);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(repository.openedEntryIds, [5, 1]);
  });

  testWidgets('shift navigation shortcuts skip read entries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeOlderFeedUnread: true,
      includeReadBetweenUnread: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.visibleEntries.map((entry) => entry.id), [1, 2, 5]);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(controller.state.selectedEntryId, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 5);
    expect(repository.openedEntryIds, [5]);

    await controller.markEntriesUnread([1]);
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(repository.openedEntryIds, [5, 1]);

    await controller.markEntriesUnread([1, 5]);
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 5);
    expect(repository.openedEntryIds, [5, 1, 5]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(repository.openedEntryIds, [5, 1, 5, 1]);
  });

  testWidgets('number shortcuts switch primary app sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.saved);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.noise);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.sources);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.settings);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.account);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await _pumpFrame(tester);
    expect(controller.state.section, AppSection.feed);
  });

  testWidgets(
    'desktop shortcut help is discoverable from keyboard and sidebar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await _pumpRouteFrame(tester);

      final dialog = find.byKey(const ValueKey<String>('shortcut-help-dialog'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('导航与搜索')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('阅读处理')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('复制与 AI')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('排版')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('订阅与同步')),
        findsOneWidget,
      );
      expect(find.text('J / ↓'), findsOneWidget);
      expect(find.text('Shift+J / K'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('跳到下一篇 / 上一篇未读')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('读完下一篇')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('跳到首尾')),
        findsOneWidget,
      );
      expect(find.text('Shift+H / L'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('跳到首篇 / 末篇未读')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('切换主要入口')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('添加订阅源')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('导入 OPML')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('导出 OPML')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('继续阅读')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('调整字号')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('调整行距')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('切换正文宽度')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('当前列表已读')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('重试 AI')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('复制文章引用')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('复制 AI 总结')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('复制阅读笔记')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('复制双语译文')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('切换队列排序')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('切换列表密度')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('折叠当前日期')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('刷新当前范围 / 全部')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('同步待处理动作 / 拉取最新变化')),
        findsOneWidget,
      );

      await tester.tap(find.text('关闭'));
      await _pumpRouteFrame(tester);

      expect(
        find.byKey(const ValueKey<String>('shortcut-help-dialog')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-shortcut-help-button')),
      );
      await _pumpRouteFrame(tester);

      expect(dialog, findsOneWidget);
      expect(find.text('快捷键帮助'), findsOneWidget);
    },
  );

  testWidgets('copy shortcut writes selected original link to clipboard', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await _pumpFrame(tester);

    expect(clipboard.text, 'https://example.com/1');
    expect(find.text('已复制原文链接'), findsOneWidget);
  });

  testWidgets('summary shortcut writes selected AI summary to clipboard', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(clipboard.text, 'First\n\nSummary 1');
    expect(find.text('已复制 AI 总结'), findsOneWidget);
  });

  testWidgets('citation shortcut writes a markdown article reference', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await _pumpFrame(tester);

    expect(clipboard.text, '[First](https://example.com/1)');
    expect(find.text('已复制文章引用'), findsOneWidget);
  });

  testWidgets('bilingual shortcut writes selected translations to clipboard', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeTranslatedEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final initialShowTranslations = controller.state.showTranslations;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(
      clipboard.text,
      'First\n\nHello world.\n\n你好，世界。\n\nSecond paragraph.\n\n第二段。',
    );
    expect(find.text('已复制双语译文'), findsOneWidget);
    expect(controller.state.showTranslations, initialShowTranslations);
  });

  testWidgets('note shortcut writes a markdown reading note', (tester) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeTranslatedEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(
      clipboard.text,
      '# First\n\n'
      '[打开原文](https://example.com/1)\n\n'
      '## 元信息\n\n'
      '- 来源：Example\n'
      '- 发布时间：2026-04-10 09:00 UTC\n\n'
      '## AI 总结\n\n'
      'Summary 1\n\n'
      '## 双语摘录\n\n'
      'Hello world.\n\n'
      '你好，世界。\n\n'
      'Second paragraph.\n\n'
      '第二段。',
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets('note shortcut includes article body as markdown', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeArticleBody: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(
      clipboard.text,
      '# First\n\n'
      '[打开原文](https://example.com/1)\n\n'
      '## 元信息\n\n'
      '- 来源：Example\n'
      '- 发布时间：2026-04-10 09:00 UTC\n\n'
      '## AI 总结\n\n'
      'Summary 1\n\n'
      '## 正文\n\n'
      '## Body title\n\n'
      'Readable **article** body.',
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets('note shortcut keeps the cover image for visual articles', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeCoverImage: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(
      clipboard.text,
      contains(
        '## 元信息\n\n'
        '- 来源：Example\n'
        '- 发布时间：2026-04-10 09:00 UTC\n\n'
        '![封面图](https://images.example.com/first.jpg)\n\n'
        '## AI 总结',
      ),
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets('note shortcut includes author and reading progress metadata', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeInProgressFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _pumpFrame(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(
      clipboard.text,
      contains(
        '## 元信息\n\n'
        '- 来源：Example\n'
        '- 作者：Reader Bot\n'
        '- 发布时间：2026-04-10 08:30 UTC\n'
        '- 阅读进度：42%\n'
        '- 剩余 1 分钟',
      ),
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets('open original shortcut launches selected link externally', (
    tester,
  ) async {
    final launcher = _installMockUrlLauncher();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await _pumpFrame(tester);

    final launchCall = launcher.launchCall;
    expect(launchCall, isNotNull);
    expect(launchCall!.method, 'launch');
    final arguments = Map<String, Object?>.from(launchCall.arguments as Map);
    expect(arguments['url'], 'https://example.com/1');
    expect(arguments['useWebView'], isFalse);
  });

  testWidgets('translation shortcut toggles bilingual reading preference', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.showTranslations, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _pumpFrame(tester);

    expect(controller.state.showTranslations, isFalse);
    expect(repository._readerPreferences.showTranslations, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _pumpFrame(tester);

    expect(controller.state.showTranslations, isTrue);
    expect(repository._readerPreferences.showTranslations, isTrue);
  });

  testWidgets('reader typography shortcuts update local preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        collapsedEntryDateSections: ['2026-04-10'],
        collapsedSourceFolders: ['Engineering'],
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.fontSize, 18);
    expect(repository._readerPreferences.fontSize, 18);

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.fontSize, 17);
    expect(repository._readerPreferences.fontSize, 17);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.lineHeight, closeTo(1.8, 0.001));
    expect(repository._readerPreferences.lineHeight, closeTo(1.8, 0.001));

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.lineHeight, closeTo(1.7, 0.001));
    expect(repository._readerPreferences.lineHeight, closeTo(1.7, 0.001));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.width, ReaderWidth.wide);
    expect(repository._readerPreferences.width, ReaderWidth.wide);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await _pumpFrame(tester);

    expect(controller.state.readerPreferences.width, ReaderWidth.narrow);
    expect(repository._readerPreferences.width, ReaderWidth.narrow);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await _pumpFrame(tester);

    expect(
      controller.state.readerPreferences.fontSize,
      ReaderPreferences.defaultPreferences.fontSize,
    );
    expect(
      controller.state.readerPreferences.lineHeight,
      ReaderPreferences.defaultPreferences.lineHeight,
    );
    expect(
      controller.state.readerPreferences.width,
      ReaderPreferences.defaultPreferences.width,
    );
    expect(repository._readerPreferences.width, ReaderWidth.comfortable);
    expect(repository._readerPreferences.collapsedEntryDateSections, [
      '2026-04-10',
    ]);
    expect(repository._readerPreferences.collapsedSourceFolders, [
      'Engineering',
    ]);
  });

  testWidgets(
    'processed-through-current shortcut marks the scanned range read',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(
        store,
        readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
          lastSection: AppSection.feed.name,
          lastSelectedEntryId: 2,
        ),
      );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.selectedEntryId, 2);
      expect(controller.visibleUnreadEntryIdsThroughSelection, [1, 2]);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await _pumpFrame(tester);

      expect(repository.markEntriesReadBatches, [
        [1, 2],
      ]);
      expect(controller.visibleUnreadEntryIdsThroughSelection, isEmpty);
      expect(find.text('未读清空'), findsOneWidget);
      expect(find.text('已将 2 篇标记为已读'), findsOneWidget);

      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(repository.markUnreadEntryIds, [1, 2]);
      expect(controller.visibleUnreadCount, 2);
    },
  );

  testWidgets('mark visible read shortcut clears the current queue with undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.visibleUnreadCount, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await _pumpFrame(tester);

    expect(find.text('当前可见的 2 篇未读文章会标记为已读。'), findsNothing);
    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(controller.visibleUnreadCount, 0);
    expect(find.text('已将当前 2 篇标记为已读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1, 2]);
    expect(controller.visibleUnreadCount, 2);
  });

  testWidgets(
    'offline mark visible read undo stays queued after network recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      await tester.pump();

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await _pumpFrame(tester);

      expect(repository.markEntriesReadBatches, [
        [1, 2],
      ]);
      expect(controller.visibleUnreadCount, 0);

      repository.syncFailuresRemaining = 0;
      await controller.syncNow();
      await _pumpFrame(tester);

      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isTrue);
      expect(repository.markUnreadEntryIds, isEmpty);
      expect(repository.queuedReadStates, ['1:false', '2:false']);
      expect(controller.visibleUnreadCount, 2);
    },
  );

  testWidgets('noise shortcut moves selected entry aside and opens next', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await _pumpFrame(tester);

    expect(repository.noiseEntryUpdates, ['1:true']);
    expect(repository.openedEntryIds, [2]);
    expect(controller.state.selectedEntryId, 2);
    expect(controller.state.snapshot.entries[1]!.isNoise, isTrue);
    expect(controller.visibleEntries.map((entry) => entry.id), [2]);
    expect(find.text('已移入噪音箱'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.noiseEntryUpdates, ['1:true', '1:false']);
    expect(controller.state.snapshot.entries[1]!.isNoise, isFalse);
    expect(controller.state.selectedEntryId, 2);
    expect(controller.visibleEntries.map((entry) => entry.id), [1, 2]);
  });

  testWidgets('later shortcut saves selected entry and opens next', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await _pumpFrame(tester);

    expect(repository.markReadEntryIds, [1]);
    expect(repository.openedEntryIds, [2]);
    expect(controller.state.selectedEntryId, 2);
    expect(controller.state.snapshot.entries[1]!.isSaved, isTrue);
    expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(find.text('已加入稍后读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1]);
    expect(controller.state.snapshot.entries[1]!.isSaved, isFalse);
    expect(controller.state.snapshot.entries[1]!.isRead, isFalse);
    expect(controller.state.selectedEntryId, 2);
  });

  testWidgets('next shortcut loads the following page at queue end', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includePagedFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await _pumpFrame(tester);
    expect(controller.state.selectedEntryId, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await _pumpFrame(tester);

    expect(repository.loadedMoreListKeys, [ListKey.feed]);
    expect(controller.state.selectedEntryId, 9);
    expect(repository.openedEntryIds, [2, 9]);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Next Page',
    ]);
    expect(find.text('Next Page'), findsWidgets);
  });

  testWidgets('load more hides stale cursor after server rejects it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includePagedFeed: true,
      loadMoreException: const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'invalid pagination cursor',
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.widgetWithText(FilledButton, '加载更多'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('queue-workload-load-more')),
      findsOneWidget,
    );
    final loadMoreSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('entry-load-more-semantics')),
    );
    expect(loadMoreSemantics.properties.label, '历史文章分页，已加载 2 篇，点击加载更多');
    expect(loadMoreSemantics.properties.button, isTrue);
    expect(loadMoreSemantics.properties.enabled, isTrue);
    expect(find.byTooltip('已加载 2 篇，继续加载历史文章'), findsOneWidget);

    final workloadLoadMore = find.byKey(
      const ValueKey<String>('queue-workload-load-more'),
    );
    await tester.ensureVisible(workloadLoadMore);
    await _pumpFrame(tester);
    await tester.tap(workloadLoadMore);
    await _pumpFrame(tester);

    expect(repository.loadedMoreListKeys, [ListKey.feed]);
    expect(controller.canLoadMoreEntries, isFalse);
    expect(find.widgetWithText(FilledButton, '加载更多'), findsNothing);
    expect(find.text('历史分页已失效，已隐藏加载更多，请刷新当前列表后再试'), findsOneWidget);
    expect(find.text('invalid pagination cursor'), findsNothing);
  });

  testWidgets(
    'load more explains stale source filter without raw failure prefix',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(
        store,
        includeSecondSourceFeed: true,
        includeSourceCatalog: true,
        loadMoreException: const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'feed source not found',
        ),
      );
      final sourceFilterKey = ListKey.sourceInView('feed', 2);
      repository._snapshot = repository._snapshot.copyWith(
        listHasMore: {sourceFilterKey.value: true},
        listCursors: {
          sourceFilterKey.value: EntryPageCursor(
            publishedAt: DateTime.utc(2026, 4, 10, 7),
            id: 6,
          ),
        },
      );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('source-filter-2')),
      );
      await _pumpFrame(tester);
      await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
      await _pumpFrame(tester);

      expect(controller.canLoadMoreEntries, isTrue);

      final workloadLoadMore = find.byKey(
        const ValueKey<String>('queue-workload-load-more'),
      );
      await tester.ensureVisible(workloadLoadMore);
      await _pumpFrame(tester);
      await tester.tap(workloadLoadMore);
      await _pumpFrame(tester);

      expect(repository.loadedMoreListKeys, [sourceFilterKey]);
      expect(controller.state.entrySourceFilterId, isNull);
      expect(find.text('订阅源已在服务端删除，已清除来源筛选。'), findsWidgets);
      expect(find.textContaining('加载历史文章失败'), findsNothing);
      expect(find.text('feed source not found'), findsNothing);
    },
  );

  testWidgets('load more reports offline history loading without throwing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includePagedFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await tester.pump();

    repository.syncFailuresRemaining = 1;
    await controller.syncNow();
    controller.clearError();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);
    expect(
      find.byKey(const ValueKey<String>('queue-workload-load-more')),
      findsOneWidget,
    );

    final loadMoreChip = tester.widget<ActionChip>(
      find.byKey(const ValueKey<String>('queue-workload-load-more')),
    );
    loadMoreChip.onPressed!();
    await _pumpFrame(tester);

    expect(repository.loadedMoreListKeys, isEmpty);
    expect(find.text('离线状态下无法加载历史文章'), findsOneWidget);
    expect(find.text('离线状态下不支持写操作'), findsNothing);
  });

  testWidgets(
    'load more reports timeout while keeping history retry available',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(
        store,
        includePagedFeed: true,
        loadMoreException: TimeoutException('slow history load'),
      );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      final workloadLoadMore = find.byKey(
        const ValueKey<String>('queue-workload-load-more'),
      );
      await tester.ensureVisible(workloadLoadMore);
      await _pumpFrame(tester);
      await tester.tap(workloadLoadMore);
      await _pumpFrame(tester);

      expect(repository.loadedMoreListKeys, [ListKey.feed]);
      expect(controller.canLoadMoreEntries, isTrue);
      expect(find.widgetWithText(FilledButton, '加载更多'), findsOneWidget);
      expect(find.text('加载历史文章超时，请稍后重试。'), findsOneWidget);
      expect(find.text('请求超时，请稍后重试。'), findsNothing);
    },
  );

  testWidgets('finish action continues onto the next loaded page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includePagedFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await controller.openEntry(2);
    await _pumpFrame(tester);
    await controller.finishSelectedAndOpenNext();
    await _pumpFrame(tester);

    expect(repository.loadedMoreListKeys, [ListKey.feed]);
    expect(controller.state.selectedEntryId, 9);
    expect(repository.openedEntryIds, [2, 9]);
    expect(controller.state.snapshot.entries[9]?.isRead, isTrue);
  });

  testWidgets('toolbar marks the current visible list as read', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.visibleUnreadCount, 2);

    await tester.tap(find.text('标记当前已读'));
    await _pumpRouteFrame(tester);
    expect(find.text('当前可见的 2 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(repository.markReadEntryIds, isEmpty);
    expect(controller.visibleUnreadCount, 0);
    expect(
      controller.state.snapshot.entries.values.every((entry) => entry.isRead),
      isTrue,
    );
    expect(find.text('已将 2 篇标记为已读'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await _pumpRouteFrame(tester);

    expect(repository.markUnreadEntryIds, [1, 2]);
    expect(controller.visibleUnreadCount, 2);
    expect(
      controller.state.snapshot.entries.values.every((entry) => !entry.isRead),
      isTrue,
    );
  });

  testWidgets('toolbar surfaces pending sync work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 3,
      pendingSyncDescription: '标记已读 2、阅读进度 1',
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('待同步 3 · 标记已读 2、阅读进度 1'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('desktop-sync-button')),
          )
          .tooltip,
      '同步待处理动作',
    );
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(syncPill.properties.label, '同步状态，待同步 3，标记已读 2、阅读进度 1，点击同步待处理动作');
    expect(syncPill.properties.button, isTrue);
    expect(syncPill.properties.enabled, isTrue);
    final syncAttemptsBeforeTap = repository.syncAttempts;

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
    expect(find.text('已同步 3 个待处理动作：标记已读 2、阅读进度 1'), findsOneWidget);
  });

  testWidgets('sync status redacts sensitive pending work details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 2,
      pendingSyncDescription:
          '重试 Authorization: Bearer pending.jwt api_key=pending-key '
          'https://pending-user:pending-pass@reader.example/sync',
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.textContaining('pending.jwt'), findsNothing);
    expect(find.textContaining('pending-key'), findsNothing);
    expect(find.textContaining('pending-user'), findsNothing);
    expect(find.textContaining('pending-pass'), findsNothing);
    expect(
      find.textContaining(
        '待同步 2 · 重试 Authorization: Bearer [redacted] [redacted] '
        'https://redacted@reader.example/sync',
      ),
      findsOneWidget,
    );
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(
      syncPill.properties.label,
      contains(
        '同步状态，待同步 2，重试 Authorization: Bearer [redacted] [redacted] '
        'https://redacted@reader.example/sync，点击同步待处理动作',
      ),
    );
    expect(syncPill.properties.label, isNot(contains('pending.jwt')));
    expect(syncPill.properties.label, isNot(contains('pending-key')));
    expect(syncPill.properties.label, isNot(contains('pending-user')));
    expect(syncPill.properties.label, isNot(contains('pending-pass')));

    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sync-status-pill')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(
      tooltip.message,
      contains(
        '同步待处理动作：重试 Authorization: Bearer [redacted] [redacted] '
        'https://redacted@reader.example/sync',
      ),
    );
    expect(tooltip.message, isNot(contains('pending.jwt')));
    expect(tooltip.message, isNot(contains('pending-key')));
    expect(tooltip.message, isNot(contains('pending-user')));
    expect(tooltip.message, isNot(contains('pending-pass')));

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await _pumpFrame(tester);

    expect(find.textContaining('pending.jwt'), findsNothing);
    expect(find.textContaining('pending-key'), findsNothing);
    expect(find.textContaining('pending-user'), findsNothing);
    expect(find.textContaining('pending-pass'), findsNothing);
    expect(
      find.textContaining(
        '已同步 2 个待处理动作：重试 Authorization: Bearer [redacted] [redacted] '
        'https://redacted@reader.example/sync',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sync shortcut flushes pending work from the keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, pendingSyncCount: 3);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final syncAttemptsBeforeShortcut = repository.syncAttempts;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeShortcut + 1);
    expect(find.text('已同步 3 个待处理动作'), findsOneWidget);
  });

  testWidgets('desktop sidebar sync button reports completion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final syncAttemptsBeforeTap = repository.syncAttempts;
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('desktop-sync-button')),
          )
          .tooltip,
      '拉取最新变化',
    );

    await tester.tap(find.byKey(const ValueKey<String>('desktop-sync-button')));
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
    expect(find.text('已同步最新变化'), findsOneWidget);
  });

  testWidgets('sync status pill keeps pending work visible while syncing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final syncCompleter = Completer<void>();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 2,
      pendingSyncDescription: '标记已读 1、阅读进度 1',
      syncCompleter: syncCompleter,
      syncCompleterAttempt: 2,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final syncAttemptsBeforeTap = repository.syncAttempts;

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await tester.pump();

    expect(controller.state.busy, isTrue);
    expect(find.text('同步中 · 2 · 标记已读 1、阅读进度 1'), findsOneWidget);
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(syncPill.properties.label, '同步状态，同步中，待同步 2，标记已读 1、阅读进度 1');
    expect(syncPill.properties.button, isNull);
    expect(syncPill.properties.enabled, isNull);

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await tester.pump();

    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
    expect(find.text('已同步最新变化'), findsNothing);

    syncCompleter.complete();
    await _pumpFrame(tester);

    expect(controller.state.busy, isFalse);
    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
    expect(find.text('已同步 2 个待处理动作：标记已读 1、阅读进度 1'), findsOneWidget);
  });

  testWidgets('startup restore surfaces sync status as syncing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final syncCompleter = Completer<void>();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 2,
      pendingSyncDescription: '标记已读 1、阅读进度 1',
      syncCompleter: syncCompleter,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      if (!syncCompleter.isCompleted) {
        syncCompleter.complete();
      }
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(repository.syncAttempts, 1);
    expect(controller.state.busy, isTrue);
    expect(find.text('同步中 · 2 · 标记已读 1、阅读进度 1'), findsOneWidget);
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(syncPill.properties.label, '同步状态，同步中，待同步 2，标记已读 1、阅读进度 1');
    expect(syncPill.properties.button, isNull);

    syncCompleter.complete();
    await _pumpFrame(tester);

    expect(controller.state.busy, isFalse);
    expect(find.text('待同步 2 · 标记已读 1、阅读进度 1'), findsOneWidget);
  });

  testWidgets('mobile toolbar surfaces pending sync work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, pendingSyncCount: 2);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('待同步 2'), findsOneWidget);
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(syncPill.properties.label, '同步状态，待同步 2，点击同步待处理动作');
    expect(syncPill.properties.button, isTrue);
    expect(syncPill.properties.enabled, isTrue);
    final syncAttemptsBeforeTap = repository.syncAttempts;

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
  });

  testWidgets('mobile search explains full content search scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('搜索标题、来源、摘要或正文，最多 8 个关键词'), findsOneWidget);
  });

  testWidgets('toolbar shows last successful sync time when clean', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      lastServerTime: DateTime(2026, 4, 10, 9, 12),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('已同步 04-10 09:12'), findsOneWidget);
  });

  testWidgets('clean sync status pill can pull latest changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      lastServerTime: DateTime(2026, 4, 10, 9, 12),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('已同步 04-10 09:12'), findsOneWidget);
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(syncPill.properties.label, '同步状态，已同步 04-10 09:12，点击拉取最新变化');
    final syncAttemptsBeforeTap = repository.syncAttempts;

    await tester.tap(find.byKey(const ValueKey<String>('sync-status-pill')));
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeTap + 1);
    expect(find.text('已同步最新变化'), findsOneWidget);
  });

  testWidgets('offline banner can retry sync after network recovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await tester.pump();

    repository.syncFailuresRemaining = 1;
    await controller.syncNow();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('当前网络不可用，已切换为离线阅读模式。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('retry-sync-banner-action')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('retry-sync-banner-action')),
    );
    await _pumpFrame(tester);

    expect(repository.syncAttempts, greaterThanOrEqualTo(2));
    expect(controller.state.isOnline, isTrue);
    expect(find.text('当前网络不可用，已切换为离线阅读模式。'), findsNothing);
    expect(find.text('已同步最新变化'), findsOneWidget);
  });

  testWidgets('offline banner explains pending sync work is retained', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 3,
      pendingSyncDescription: '标记已读 2、阅读进度 1',
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await tester.pump();
    repository.syncFailuresRemaining = 1;
    await controller.syncNow();

    expect(
      controller.state.errorMessage,
      '当前网络不可用，已切换为离线阅读模式。待同步 3 个动作（标记已读 2、阅读进度 1）已保留在本机，恢复在线后可重试。',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.textContaining('待同步 3 个动作'), findsOneWidget);
    expect(find.textContaining('标记已读 2、阅读进度 1'), findsWidgets);
    expect(find.textContaining('已保留在本机，恢复在线后可重试'), findsOneWidget);
    expect(find.text('待同步 3 · 标记已读 2、阅读进度 1'), findsOneWidget);
    final syncPill = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('sync-status-pill')),
    );
    expect(
      syncPill.properties.label,
      '同步状态，待同步 3，标记已读 2、阅读进度 1，已保留在本机，恢复在线后可重试',
    );
    expect(syncPill.properties.button, isNull);
    expect(syncPill.properties.enabled, isNull);
    final syncAttemptsBeforeRetry = repository.syncAttempts;

    await tester.tap(
      find.byKey(const ValueKey<String>('retry-sync-banner-action')),
    );
    await _pumpFrame(tester);

    expect(repository.syncAttempts, syncAttemptsBeforeRetry + 1);
    expect(controller.state.isOnline, isTrue);
    expect(find.text('已同步 3 个待处理动作：标记已读 2、阅读进度 1'), findsOneWidget);
  });

  testWidgets('server sync failure explains pending work is retained', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository =
        _ShortcutRepository(
            store,
            pendingSyncCount: 2,
            pendingSyncDescription: '加入稍后读 1、阅读进度 1',
          )
          ..syncException = const ApiException(
            statusCode: 503,
            code: 'INTERNAL_SERVER_ERROR',
            message: 'service unavailable',
          );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await tester.pump();

    await controller.syncNow();

    expect(
      controller.state.errorMessage,
      '服务端暂时不可用，请稍后重试。待同步 2 个动作（加入稍后读 1、阅读进度 1）已保留在本机，恢复在线后可重试。',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.textContaining('待同步 2 个动作'), findsOneWidget);
    expect(find.textContaining('加入稍后读 1、阅读进度 1'), findsWidgets);
    expect(find.text('待同步 2 · 加入稍后读 1、阅读进度 1'), findsOneWidget);
  });

  testWidgets(
    'mobile pull-to-refresh reports offline refresh without throwing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      await tester.pump();

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isFalse);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isFalse);
      expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试刷新订阅源'), findsOneWidget);
    },
  );

  testWidgets('mobile pull-to-refresh reports accepted source count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)..refreshAllAcceptedCount = 4;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 4 个订阅源'), findsOneWidget);
  });

  testWidgets('desktop feed refresh action reports accepted source count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)..refreshAllAcceptedCount = 2;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 2 个订阅源'), findsOneWidget);
  });

  testWidgets('desktop feed refresh action explains network loss', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..refreshAllException = const NetworkException('offline refresh all');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(controller.state.isOnline, isFalse);
    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试刷新订阅源'), findsOneWidget);
    expect(find.text('离线状态下不支持写操作'), findsNothing);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  testWidgets('mobile sources refresh action reports offline writes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshAllException = const NetworkException('offline');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试刷新订阅源'), findsOneWidget);
    expect(find.text('离线状态下不支持写操作'), findsNothing);
    expect(controller.state.busy, isFalse);
  });

  testWidgets('mobile sources pull-to-refresh reports timeout writes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshAllException = TimeoutException('slow refresh');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await _pumpFrame(tester);

    expect(find.text('刷新订阅源请求超时，请稍后重试'), findsOneWidget);
    expect(controller.state.busy, isFalse);
  });

  testWidgets('desktop sources page exposes refresh all action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshAllAcceptedCount = 3;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 3 个订阅源'), findsOneWidget);
    expect(controller.state.busy, isFalse);
  });

  testWidgets('desktop sources refresh reports skipped sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshAllAcceptedCount = 2
      ..refreshAllSkippedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 2 个订阅源，跳过 1 个不可用源'), findsOneWidget);
  });

  testWidgets('add source shortcut opens the subscription dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await _pumpRouteFrame(tester);

    expect(controller.state.section, AppSection.sources);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('添加订阅源')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      findsOneWidget,
    );
  });

  testWidgets('import OPML shortcut opens the migration dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await _pumpRouteFrame(tester);

    expect(controller.state.section, AppSection.sources);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('导入 OPML')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      findsOneWidget,
    );
  });

  testWidgets('export OPML shortcut copies subscriptions to the clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.sources);
    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, '<opml version="2.0"><body></body></opml>');
    expect(find.text('OPML 已复制，可粘贴到其他阅读器'), findsOneWidget);
  });

  testWidgets('source empty state offers add and import actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('还没有订阅源'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('source-empty-add-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-empty-import-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-empty-add-button')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      findsOneWidget,
    );
  });

  testWidgets('mobile source empty state opens OPML import dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('还没有订阅源'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-empty-import-button')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      findsOneWidget,
    );
  });

  testWidgets(
    'feed empty state opens source management when no sources exist',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(
        store,
        includeInitialEntries: false,
      );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.section, AppSection.feed);
      expect(find.text('还没有订阅源'), findsOneWidget);
      expect(find.text('管理订阅源'), findsOneWidget);

      await tester.tap(find.text('管理订阅源'));
      await _pumpFrame(tester);

      expect(controller.state.section, AppSection.sources);
      expect(
        find.byKey(const ValueKey<String>('source-empty-add-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('saved empty state returns to feed when sources exist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.saved);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('还没有稍后读文章'), findsOneWidget);
    expect(find.text('回到 Feed'), findsOneWidget);

    await tester.tap(find.text('回到 Feed'));
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);
    expect(find.text('First'), findsWidgets);
  });

  testWidgets('noise empty state returns to feed when sources exist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.noise);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('噪音箱是空的'), findsOneWidget);
    expect(find.text('回到 Feed'), findsOneWidget);

    await tester.tap(find.text('回到 Feed'));
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('source entry empty state refreshes only that source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      includeInitialEntries: false,
    )..refreshSourceAcceptedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.sourceEntries);
    expect(find.text('这个订阅源还没有文章'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '刷新此源'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '刷新此源'));
    await _pumpFrame(tester);

    expect(repository.refreshedSourceIds, [1]);
    expect(find.text('已请求刷新 1 个订阅源：Example Daily'), findsOneWidget);
  });

  testWidgets('mobile source entry page can return to source list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      includeInitialEntries: false,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.sourceEntries);
    expect(
      find.byKey(const ValueKey<String>('mobile-source-back-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-source-back-button')),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.sources);
    expect(controller.state.selectedSourceId, isNull);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('订阅源')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mobile-source-back-button')),
      findsNothing,
    );
  });

  testWidgets('source filter empty state can refresh current source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      includeInitialEntries: false,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntrySourceFilter(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('这个来源当前没有文章'), findsOneWidget);
    expect(find.text('查看全部来源'), findsOneWidget);
    expect(find.text('刷新当前范围'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '刷新当前范围'));
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 0);
    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前来源'), findsOneWidget);
  });

  testWidgets('folder filter empty state can refresh current folder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      includeInitialEntries: false,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntryFolderFilter('Engineering');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('这个文件夹当前没有文章'), findsOneWidget);
    expect(find.text('查看全部文件夹'), findsOneWidget);
    expect(find.text('刷新当前范围'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '刷新当前范围'));
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 0);
    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前文件夹订阅源'), findsOneWidget);
  });

  testWidgets('mobile detail source title follows the next opened article', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('Second'));
    await _pumpRouteFrame(tester);

    expect(controller.state.selectedEntryId, 2);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Example')),
      findsOneWidget,
    );

    await tester.tap(find.text('读完下一篇'));
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 6);
    expect(find.text('Tech Unread'), findsWidgets);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Tech')),
      findsOneWidget,
    );
  });

  testWidgets('navigation badges show unread counts for reader queues', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSecondaryUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(_badgeText('desktop-feed-unread-badge', '2'), findsOneWidget);
    expect(_badgeText('desktop-saved-unread-badge', '1'), findsOneWidget);
    expect(_badgeText('desktop-noise-unread-badge', '1'), findsOneWidget);

    await tester.tap(find.text('标记当前已读'));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('desktop-feed-unread-badge')),
      findsNothing,
    );
    expect(_badgeText('desktop-saved-unread-badge', '1'), findsOneWidget);
    expect(_badgeText('desktop-noise-unread-badge', '1'), findsOneWidget);
  });

  testWidgets('date section headers can mark one reading group as read', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeOlderFeedUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('4月10日'), findsOneWidget);
    expect(find.text('4月9日'), findsOneWidget);
    expect(find.text('2 篇 · 2 未读'), findsOneWidget);
    expect(find.text('1 篇 · 1 未读'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>('date-section-2026-04-10-semantics'),
            ),
          )
          .properties
          .label,
      '日期分组，4月10日，2 篇文章，2 篇未读，已展开',
    );
    expect(find.byTooltip('将 4月10日 的 2 篇未读文章标记已读'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('date-section-2026-04-10-mark-read')),
    );
    await _pumpRouteFrame(tester);
    expect(find.text('4月10日 的 2 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[5]!.isRead, isFalse);
    expect(find.text('2 篇 · 0 未读'), findsOneWidget);
    expect(find.text('1 篇 · 1 未读'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>('date-section-2026-04-10-semantics'),
            ),
          )
          .properties
          .label,
      '日期分组，4月10日，2 篇文章，0 篇未读，已展开',
    );
    expect(find.byTooltip('4月10日 没有未读文章'), findsOneWidget);
  });

  testWidgets('shift d collapses the selected date group from keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeOlderFeedUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(find.text('3 篇当前列表'), findsOneWidget);
    expect(find.text('2 已折叠'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('entry-card-1-semantics')),
      findsOneWidget,
    );
    expect(
      controller.state.readerPreferences.entryListDensity,
      EntryListDensity.comfortable,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(find.text('已折叠 4月10日'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('entry-card-1-semantics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-5-semantics')),
      findsOneWidget,
    );
    expect(controller.state.selectedEntryId, 5);
    expect(controller.visibleUnreadEntryIds, [5]);
    expect(find.text('2 已折叠'), findsOneWidget);
    expect(repository._readerPreferences.collapsedEntryDateSections, [
      '2026-04-10',
    ]);
    expect(
      controller.state.readerPreferences.entryListDensity,
      EntryListDensity.comfortable,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    expect(find.text('已折叠 4月9日'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('entry-card-1-semantics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-5-semantics')),
      findsNothing,
    );
    expect(controller.state.selectedEntryId, isNull);
    expect(find.text('3 已折叠'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('queue-expand-collapsed-dates')),
      findsOneWidget,
    );
    expect(repository._readerPreferences.collapsedEntryDateSections, [
      '2026-04-09',
      '2026-04-10',
    ]);

    await tester.pump(const Duration(seconds: 4));
    await _pumpFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('queue-expand-collapsed-dates')),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('entry-card-1-semantics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-5-semantics')),
      findsOneWidget,
    );
    expect(controller.state.selectedEntryId, 1);
    expect(find.text('3 已折叠'), findsNothing);
    expect(repository._readerPreferences.collapsedEntryDateSections, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('date-section-2026-04-10-toggle')),
    );
    await _pumpFrame(tester);

    expect(find.text('已展开 4月10日'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('entry-card-1-semantics')),
      findsOneWidget,
    );
    expect(controller.state.selectedEntryId, 5);
    expect(find.text('1 已折叠'), findsNothing);
    expect(repository._readerPreferences.collapsedEntryDateSections, isEmpty);
  });

  testWidgets('date section headers collapse reading groups and restore', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeOlderFeedUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final dateToggle = find.byKey(
      const ValueKey<String>('date-section-2026-04-10-toggle'),
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-2-semantics')),
      findsOneWidget,
    );

    await tester.tap(dateToggle);
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('entry-card-2-semantics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-5-semantics')),
      findsOneWidget,
    );
    expect(controller.state.selectedEntryId, 5);
    expect(controller.visibleUnreadEntryIds, [5]);
    expect(repository._readerPreferences.collapsedEntryDateSections, [
      '2026-04-10',
    ]);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>('date-section-2026-04-10-semantics'),
            ),
          )
          .properties
          .label,
      '日期分组，4月10日，2 篇文章，2 篇未读，已折叠',
    );

    controller.dispose();
    final restoredController = AppController(repository: repository);
    await restoredController.initialize();
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('restored-date-section-scope'),
        overrides: [
          appControllerProvider.overrideWith((ref) => restoredController),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('entry-card-2-semantics')),
      findsNothing,
    );
    expect(
      restoredController.state.readerPreferences.collapsedEntryDateSections,
      ['2026-04-10'],
    );

    await tester.tap(dateToggle);
    await _pumpFrame(tester);

    expect(
      restoredController.state.readerPreferences.collapsedEntryDateSections,
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey<String>('entry-card-2-semantics')),
      findsOneWidget,
    );
    restoredController.dispose();
  });

  testWidgets(
    'offline date section mark-read undo stays queued after network recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(
        store,
        includeOlderFeedUnread: true,
      );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      await tester.pump();

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('date-section-2026-04-10-mark-read')),
      );
      await _pumpRouteFrame(tester);
      await tester.tap(find.text('确认'));
      await _pumpRouteFrame(tester);

      expect(repository.markEntriesReadBatches, [
        [1, 2],
      ]);
      expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
      expect(controller.state.snapshot.entries[2]!.isRead, isTrue);

      repository.syncFailuresRemaining = 0;
      await controller.syncNow();
      await _pumpFrame(tester);

      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isTrue);
      expect(repository.markUnreadEntryIds, isEmpty);
      expect(repository.queuedReadStates, ['1:false', '2:false']);
      expect(controller.state.snapshot.entries[1]!.isRead, isFalse);
      expect(controller.state.snapshot.entries[2]!.isRead, isFalse);
      expect(controller.state.snapshot.entries[5]!.isRead, isFalse);
    },
  );

  testWidgets('source quick filters narrow the current reading queue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
      includeDisabledEngineeringSource: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(store.close);
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-filter-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-filter-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-filter-icon-2')),
      findsOneWidget,
    );
    final techSourceFilterIcon = tester.widget<Image>(
      find.byKey(const ValueKey<String>('source-filter-icon-2')),
    );
    expect(
      (techSourceFilterIcon.image as NetworkImage).url,
      'https://tech.example.com/favicon.ico',
    );
    final allSourceFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('source-filter-all')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      allSourceFilterSemantics.properties.label,
      '阅读队列全部筛选，全部来源，4 篇文章，3 篇未读，当前筛选',
    );
    expect(allSourceFilterSemantics.properties.button, isTrue);
    expect(allSourceFilterSemantics.properties.enabled, isTrue);
    final techSourceFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('source-filter-2')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      techSourceFilterSemantics.properties.label,
      '阅读队列来源筛选，Tech，2 篇文章，1 篇未读，点击筛选',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Tech Unread',
      'Tech Read',
    ]);
    expect(
      find.byKey(const ValueKey<String>('entry-source-icon-1')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-2')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, 2);
    expect(repository.loadedListKeys.last, ListKey.sourceInView('feed', 2));
    final selectedTechSourceFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('source-filter-2')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      selectedTechSourceFilterSemantics.properties.label,
      '阅读队列来源筛选，Tech，2 篇文章，1 篇未读，当前筛选',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);
    expect(controller.visibleUnreadEntryIds, [6]);
    expect(
      find.byKey(const ValueKey<String>('entry-source-icon-6')),
      findsOneWidget,
    );

    await tester.tap(find.text('标记当前已读'));
    await _pumpRouteFrame(tester);
    expect(find.text('当前可见的 1 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markEntriesReadBatches.last, [6]);
    expect(controller.state.snapshot.entries[6]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[1]!.isRead, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-all')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-all')));
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, isNull);
    final restoredAllSourceFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('source-filter-all')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      restoredAllSourceFilterSemantics.properties.label,
      '阅读队列全部筛选，全部来源，4 篇文章，2 篇未读，当前筛选',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('source filter chips redact sensitive source and folder labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveSourceName =
        'Tech token=source-token sk-source123456 '
        'https://source-user:source-pass@tech.example.com/private';
    const sensitiveFolder = 'Engineering api_key=folder-secret';
    const redactedSourceName =
        'Tech [redacted] [redacted] '
        'https://redacted@tech.example.com/private';
    const redactedFolder = 'Engineering [redacted]';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2
              ? source.copyWith(
                  name: sensitiveSourceName,
                  folder: sensitiveFolder,
                )
              : source,
      ],
      entries: {
        for (final entry in repository._snapshot.entries.values)
          entry.id: entry.sourceId == 2
              ? entry.copyWith(sourceName: sensitiveSourceName)
              : entry,
      },
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('$redactedFolder · 1/2'), findsOneWidget);
    expect(find.text('$redactedSourceName · 1/2'), findsOneWidget);
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source123456'), findsNothing);
    expect(find.textContaining('source-user:source-pass'), findsNothing);
    expect(find.textContaining('folder-secret'), findsNothing);

    final folderFilter = find.byKey(
      const ValueKey<String>('folder-filter-$sensitiveFolder'),
    );
    final folderSemantics = tester.widget<Semantics>(
      find.descendant(of: folderFilter, matching: find.byType(Semantics)).first,
    );
    expect(
      folderSemantics.properties.label,
      '阅读队列文件夹筛选，$redactedFolder，2 篇文章，1 篇未读，点击筛选',
    );
    expect(folderSemantics.properties.label, isNot(contains('folder-secret')));

    final sourceSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('source-filter-2')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      sourceSemantics.properties.label,
      '阅读队列来源筛选，$redactedSourceName，2 篇文章，1 篇未读，点击筛选',
    );
    expect(sourceSemantics.properties.label, isNot(contains('source-token')));
    expect(
      sourceSemantics.properties.label,
      isNot(contains('source-user:source-pass')),
    );

    await tester.ensureVisible(folderFilter);
    await _pumpFrame(tester);
    await tester.tap(folderFilter);
    await _pumpFrame(tester);

    expect(controller.state.entryFolderFilter, sensitiveFolder);
    expect(
      repository.loadedListKeys.last,
      ListKey.folderInView('feed', sensitiveFolder),
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);

    await tester.tap(folderFilter);
    await _pumpFrame(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-2')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, 2);
    expect(repository.loadedListKeys.last, ListKey.sourceInView('feed', 2));
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('refresh shortcut prefers the current source scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, isEmpty);
    expect(find.text('已请求刷新 1 个订阅源'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-2')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前来源'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-all')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-all')));
    await _pumpFrame(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('folder-filter-Engineering')),
    );
    await _pumpFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('folder-filter-Engineering')),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, [2, 2]);
    expect(find.text('已请求刷新 1 个当前文件夹订阅源'), findsOneWidget);

    await controller.openSource(2);
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, [2, 2, 2]);
    expect(find.text('已请求刷新 1 个当前来源'), findsOneWidget);
  });

  testWidgets('reader refresh button follows source and folder scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.widgetWithText(FilledButton, '刷新全部'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, isEmpty);
    expect(find.text('已请求刷新 1 个订阅源'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-2')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
    await _pumpFrame(tester);

    expect(find.widgetWithText(FilledButton, '刷新当前范围'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前来源'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-all')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-all')));
    await _pumpFrame(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('folder-filter-Engineering')),
    );
    await _pumpFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('folder-filter-Engineering')),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-refresh-all-button')),
    );
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(repository.refreshedSourceIds, [2, 2]);
    expect(find.text('已请求刷新 1 个当前文件夹订阅源'), findsOneWidget);
  });

  testWidgets('mobile pull-to-refresh follows the current source scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('source-filter-2')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-filter-2')));
    await _pumpFrame(tester);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 0);
    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前来源'), findsOneWidget);
  });

  testWidgets('refresh shortcut explains API failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..refreshAllException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss source is unreachable: HTTP 502',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _pumpFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('刷新失败：源站服务异常（HTTP 502），请稍后重试'), findsOneWidget);
    expect(find.text('rss source is unreachable: HTTP 502'), findsNothing);
  });

  testWidgets('folder quick filters narrow the current reading queue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final engineeringFolder = find.byKey(
      const ValueKey<String>('folder-filter-Engineering'),
    );
    expect(engineeringFolder, findsOneWidget);

    await tester.ensureVisible(engineeringFolder);
    await _pumpFrame(tester);
    await tester.tap(engineeringFolder);
    await _pumpFrame(tester);

    expect(controller.state.entryFolderFilter, 'Engineering');
    expect(controller.state.entrySourceFilterId, isNull);
    expect(
      repository.loadedListKeys.last,
      ListKey.folderInView('feed', 'Engineering'),
    );
    final engineeringFolderSemantics = tester.widget<Semantics>(
      find
          .descendant(of: engineeringFolder, matching: find.byType(Semantics))
          .first,
    );
    expect(
      engineeringFolderSemantics.properties.label,
      '阅读队列文件夹筛选，Engineering，2 篇文章，1 篇未读，当前筛选',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);
    expect(controller.visibleUnreadEntryIds, [6]);

    await tester.tap(engineeringFolder);
    await _pumpFrame(tester);

    expect(controller.state.entryFolderFilter, isNull);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('escape clears active reading filters from the entry list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    controller.setEntrySourceFilter(2);
    controller.toggleUnreadOnly(true);
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, 2);
    expect(controller.state.unreadOnly, isTrue);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpFrame(tester);

    expect(controller.state.searchQuery, isEmpty);
    expect(controller.state.entrySourceFilterId, isNull);
    expect(controller.state.unreadOnly, isFalse);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.all,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('source list search filters subscriptions by catalog fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final searchField = find.byKey(
      const ValueKey<String>('source-search-field'),
    );
    expect(searchField, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    expect(find.text('4 个订阅源'), findsOneWidget);
    expect(find.text('4 个源 · 6 未读'), findsOneWidget);
    final exampleSourceSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('source-card-1-semantics')),
    );
    expect(exampleSourceSemantics.properties.button, isTrue);
    expect(exampleSourceSemantics.properties.enabled, isTrue);
    expect(
      exampleSourceSemantics.properties.label,
      allOf(
        contains('订阅源，Example Daily，文件夹 Newsletters，2 篇未读，健康状态 正常'),
        contains('最近刷新'),
        contains('点击打开该源文章流'),
      ),
    );

    await tester.enterText(searchField, 'tech');
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('1 个源 · 4 未读'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试待处理 1'), findsOneWidget);
    expect(
      find.textContaining('错误：timeout while fetching feed'),
      findsOneWidget,
    );
    expect(find.textContaining('建议：稍后重试；如果持续超时，检查源站是否可访问'), findsOneWidget);
    expect(find.text('Example Daily'), findsNothing);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(find.text('1 / 4 个匹配'), findsOneWidget);
    final techSourceSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('source-card-2-semantics')),
    );
    expect(
      techSourceSemantics.properties.label,
      allOf(
        contains('订阅源，Tech Radar，文件夹 Engineering，4 篇未读，健康状态 抓取异常'),
        contains('错误：timeout while fetching feed'),
        contains('建议：稍后重试；如果持续超时，检查源站是否可访问'),
        contains('点击打开该源文章流'),
      ),
    );

    await tester.enterText(searchField, 'tech timeout');
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('1 / 4 个匹配'), findsOneWidget);

    await tester.enterText(
      searchField,
      'tech radar engineering rss xml timeout fetching feed missing',
    );
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('1 / 4 个匹配'), findsOneWidget);

    await tester.enterText(searchField, 'design');
    await _pumpFrame(tester);

    expect(find.text('Design Weekly'), findsOneWidget);
    expect(find.text('Tech Radar'), findsNothing);

    await tester.enterText(searchField, 'missing');
    await _pumpFrame(tester);

    expect(find.text('没有匹配的订阅源'), findsOneWidget);
    expect(find.text('当前筛选没有订阅源。'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-1')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('source-search-empty-add')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('source-search-empty-import')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('source-search-clear')));
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    expect(find.text('4 个订阅源'), findsOneWidget);
  });

  testWidgets('source list handles long sensitive source labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2
              ? source.copyWith(
                  name:
                      'Tech token=source-token sk-source123456 https://source-user:source-pass@tech.example.com/private with an extremely long imported reader title',
                  folder: 'Engineering api_key=folder-secret',
                  lastErrorMessage:
                      'timeout while fetching https://error-user:error-pass@tech.example.com/private?api_key=error-key '
                      'Authorization: Bearer raw-error-token Cookie: session=raw-session',
                )
              : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    expect(
      find.textContaining('with an extremely long imported reader title'),
      findsOneWidget,
    );
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source'), findsNothing);
    expect(find.textContaining('source-user'), findsNothing);
    expect(find.textContaining('source-pass'), findsNothing);
    expect(find.textContaining('folder-secret'), findsNothing);
    expect(find.textContaining('error-user'), findsNothing);
    expect(find.textContaining('error-pass'), findsNothing);
    expect(find.textContaining('error-key'), findsNothing);
    expect(find.textContaining('raw-error-token'), findsNothing);
    expect(find.textContaining('raw-session'), findsNothing);
    expect(
      find.textContaining(
        '错误：timeout while fetching https://redacted@tech.example.com/private',
      ),
      findsOneWidget,
    );
    final sourceSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('source-card-2-semantics')),
    );
    expect(
      sourceSemantics.properties.label,
      contains(
        '订阅源，Tech [redacted] [redacted] https://redacted@tech.example.com/private with an extremely long imported reader title，文件夹 Engineering [redacted]',
      ),
    );
    expect(sourceSemantics.properties.label, isNot(contains('source-token')));
    expect(sourceSemantics.properties.label, isNot(contains('sk-source')));
    expect(sourceSemantics.properties.label, isNot(contains('source-user')));
    expect(sourceSemantics.properties.label, isNot(contains('source-pass')));
    expect(sourceSemantics.properties.label, isNot(contains('folder-secret')));
    expect(sourceSemantics.properties.label, isNot(contains('error-user')));
    expect(sourceSemantics.properties.label, isNot(contains('error-pass')));
    expect(sourceSemantics.properties.label, isNot(contains('error-key')));
    expect(
      sourceSemantics.properties.label,
      isNot(contains('raw-error-token')),
    );
    expect(sourceSemantics.properties.label, isNot(contains('raw-session')));
  });

  testWidgets('slash shortcut focuses source search on sources page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final searchField = find.byKey(
      const ValueKey<String>('source-search-field'),
    );
    expect(searchField, findsOneWidget);
    expect(tester.widget<TextField>(searchField).focusNode?.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await _pumpFrame(tester);

    expect(tester.widget<TextField>(searchField).focusNode?.hasFocus, isTrue);

    await tester.enterText(searchField, 'tech');
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Example Daily'), findsNothing);

    controller.setSearchQuery('analysis');
    await _pumpFrame(tester);
    expect(controller.state.searchQuery, 'analysis');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpFrame(tester);

    expect(controller.state.searchQuery, 'analysis');
    expect(tester.widget<TextField>(searchField).controller?.text, isEmpty);
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Example Daily'), findsOneWidget);
  });

  testWidgets('source search empty state opens add source dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'missing',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-search-empty-add')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      findsOneWidget,
    );
  });

  testWidgets('source search empty state opens OPML import dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'missing',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-search-empty-import')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      findsOneWidget,
    );
  });

  testWidgets('source list filters subscriptions by health and unread state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-error')),
    );
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Example Daily'), findsNothing);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(find.text('1 / 4 个匹配'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('source-search-clear-filters')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-search-clear-filters')),
    );
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    expect(find.text('4 个订阅源'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('source-search-clear-filters')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-unread')),
    );
    await _pumpFrame(tester);

    expect(find.text('Example Daily'), findsOneWidget);
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(find.text('2 / 4 个匹配'), findsOneWidget);

    final searchField = find.byKey(
      const ValueKey<String>('source-search-field'),
    );
    await tester.enterText(searchField, 'archive');
    await _pumpFrame(tester);

    expect(find.text('没有匹配的订阅源'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-search-empty-clear')),
    );
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    expect(find.text('4 个订阅源'), findsOneWidget);
  });

  testWidgets('source folder headers collapse subscription groups', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final engineeringToggle = find.byKey(
      const ValueKey<String>('source-folder-toggle-Engineering'),
    );
    await tester.ensureVisible(engineeringToggle);
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    await tester.tap(engineeringToggle);
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-2')), findsNothing);
    expect(find.byKey(const ValueKey<String>('source-card-1')), findsOneWidget);
    expect(find.text('1 已折叠源', skipOffstage: false), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('source-expand-collapsed-folders'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(repository._readerPreferences.collapsedSourceFolders, [
      'Engineering',
    ]);

    controller.dispose();
    final restoredController = AppController(repository: repository);
    addTearDown(restoredController.dispose);
    await restoredController.initialize();
    restoredController.selectSection(AppSection.sources);
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey<String>('restored-source-folder-scope'),
        overrides: [
          appControllerProvider.overrideWith((ref) => restoredController),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-2')), findsNothing);
    expect(find.text('1 已折叠源', skipOffstage: false), findsOneWidget);
    expect(restoredController.state.readerPreferences.collapsedSourceFolders, [
      'Engineering',
    ]);

    await tester.ensureVisible(
      find.byKey(
        const ValueKey<String>('source-expand-collapsed-folders'),
        skipOffstage: false,
      ),
    );
    await _pumpFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('source-expand-collapsed-folders')),
    );
    await _pumpFrame(tester);

    expect(
      restoredController.state.readerPreferences.collapsedSourceFolders,
      isEmpty,
    );
    expect(find.text('1 已折叠源', skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('source-card-2')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrame(tester);

    expect(find.byKey(const ValueKey<String>('source-card-2')), findsOneWidget);
    restoredController.dispose();
  });

  testWidgets('source list sorts subscriptions by unread health and name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-sort-unread')),
    );
    await _pumpFrame(tester);

    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('source-card-2'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('source-card-1')))
            .dy,
      ),
    );
    expect(
      repository._readerPreferences.sourceListSortOrder,
      SourceListSortOrder.unread,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-sort-health')),
    );
    await _pumpFrame(tester);

    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('source-card-2'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('source-card-4')))
            .dy,
      ),
    );
    expect(
      repository._readerPreferences.sourceListSortOrder,
      SourceListSortOrder.health,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-sort-name')),
    );
    await _pumpFrame(tester);

    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('source-card-4'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('source-card-3')))
            .dy,
      ),
    );
    expect(
      repository._readerPreferences.sourceListSortOrder,
      SourceListSortOrder.name,
    );
  });

  testWidgets('source list sort restores from local reader preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        sourceListSortOrder: SourceListSortOrder.health,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('source-list-sort-health')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('source-card-2'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('source-card-4')))
            .dy,
      ),
    );
  });

  testWidgets('source health panel follows the visible source filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-disabled')),
    );
    await _pumpFrame(tester);

    expect(find.text('Design Weekly'), findsOneWidget);
    expect(find.text('1 个源 · 0 未读'), findsOneWidget);
    expect(find.text('当前筛选内有停用订阅源，不会自动抓取。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试待处理 2'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('source-health-retry-issues')),
      findsNothing,
    );
  });

  testWidgets('source health metrics switch source filters', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.byTooltip('查看有未读的订阅源'), findsOneWidget);
    expect(find.byTooltip('查看报错订阅源'), findsOneWidget);
    expect(find.byTooltip('清空健康筛选'), findsNothing);
    final unreadMetricSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('source-health-metric-unread'),
            ),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(unreadMetricSemantics.properties.label, '订阅源健康指标，未读积压 6，点击筛选');
    expect(unreadMetricSemantics.properties.button, isTrue);
    expect(unreadMetricSemantics.properties.enabled, isTrue);
    final errorMetricSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('source-health-metric-error'),
            ),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(errorMetricSemantics.properties.label, '订阅源健康指标，报错 1，点击筛选');
    expect(errorMetricSemantics.properties.button, isTrue);
    expect(errorMetricSemantics.properties.enabled, isTrue);
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label),
      contains('订阅源健康状态，抓取异常'),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-metric-unread')),
    );
    await _pumpFrame(tester);

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey<String>('source-list-filter-unread')),
          )
          .selected,
      isTrue,
    );
    final selectedUnreadMetricSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('source-health-metric-unread'),
            ),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      selectedUnreadMetricSemantics.properties.label,
      '订阅源健康指标，未读积压 6，当前筛选',
    );
    expect(find.text('Example Daily'), findsOneWidget);
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(find.text('2 个源 · 6 未读'), findsOneWidget);
    expect(find.byTooltip('清空健康筛选'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-metric-error')),
    );
    await _pumpFrame(tester);

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey<String>('source-list-filter-error')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Example Daily'), findsNothing);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(find.text('1 个源 · 4 未读'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-clear-filter')),
    );
    await _pumpFrame(tester);

    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey<String>('source-list-filter-all')),
          )
          .selected,
      isTrue,
    );
    expect(find.byTooltip('清空健康筛选'), findsNothing);
    expect(find.text('Example Daily'), findsOneWidget);
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsOneWidget);
    expect(find.text('4 个源 · 6 未读'), findsOneWidget);
  });

  testWidgets('source health panel copies visible issue diagnostics', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('RSS Copilot Source Diagnostics Batch'));
    expect(clipboard?.text, contains('Issue sources: 3'));
    expect(clipboard?.text, contains('Name: Tech Radar'));
    expect(clipboard?.text, contains('Health: 抓取异常'));
    expect(
      clipboard?.text,
      contains('Suggested action: 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(clipboard?.text, contains('Name: Design Weekly'));
    expect(clipboard?.text, contains('Health: 已停用'));
    expect(
      clipboard?.text,
      contains('Suggested action: 如仍需接收新文章，请启用自动抓取后刷新此源'),
    );
    expect(clipboard?.text, contains('Name: Archive Planet'));
    expect(clipboard?.text, contains('Health: 待刷新'));
    expect(clipboard?.text, contains('Suggested action: 超过 24 小时未刷新；请手动刷新此源'));
    expect(clipboard?.text, isNot(contains('Name: Example Daily')));
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
    expect(find.text('已复制 3 个问题源的诊断信息'), findsOneWidget);
  });

  testWidgets('source mark-read action requires confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记已读').last);
    await _pumpRouteFrame(tester);

    expect(find.text('标记订阅源已读'), findsOneWidget);
    expect(find.text('Example Daily 的 2 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记已读').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, [1]);
    expect(find.text('已将 Example Daily 标记为已读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1, 2]);
    expect(repository.queuedReadStates, isEmpty);
  });

  testWidgets('source mark-read queues cached articles while offline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..syncFailuresRemaining = 3;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.syncNow();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记已读').last);
    await _pumpRouteFrame(tester);

    expect(
      find.text('离线时仅会将 Example Daily 已缓存的 2 篇未读文章加入待同步。'),
      findsOneWidget,
    );

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, isEmpty);
    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(find.text('已将 Example Daily 的 2 篇已缓存文章加入待同步'), findsOneWidget);
    expect(find.text('离线状态下无法批量标记已读'), findsNothing);

    repository.syncFailuresRemaining = 0;
    await controller.syncNow();
    await _pumpFrame(tester);

    await tester.tap(find.text('撤销'));
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, isEmpty);
    expect(repository.queuedReadStates, ['1:false', '2:false']);
  });

  testWidgets('source mark-read hides undo when unread cache is incomplete', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 1 ? source.copyWith(unreadCount: 3) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记已读').last);
    await _pumpRouteFrame(tester);

    expect(find.text('Example Daily 的 3 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, [1]);
    expect(find.text('已将 Example Daily 标记为已读'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '撤销'), findsNothing);
  });

  testWidgets('source menu refresh reports accepted source count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceAcceptedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [1]);
    expect(find.text('已请求刷新 1 个订阅源：Example Daily'), findsOneWidget);
  });

  testWidgets('source menu refresh explains when source is disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceAcceptedCount = 0;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-disabled')),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-menu-3')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [3]);
    expect(find.text('订阅源已停用，未发起刷新：Design Weekly'), findsOneWidget);
  });

  testWidgets('source menu refresh feedback redacts sensitive source labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveSourceName =
        'Example token=source-token sk-source123456 '
        'https://source-user:source-pass@example.com/private';
    const redactedSourceName =
        'Example [redacted] [redacted] '
        'https://redacted@example.com/private';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceAcceptedCount = 1;
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 1 ? source.copyWith(name: sensitiveSourceName) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [1]);
    expect(find.text('已请求刷新 1 个订阅源：$redactedSourceName'), findsOneWidget);
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source123456'), findsNothing);
    expect(find.textContaining('source-user:source-pass'), findsNothing);
  });

  testWidgets('source menu delete feedback redacts sensitive source labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveSourceName =
        'Example token=source-token sk-source123456 '
        'https://source-user:source-pass@example.com/private';
    const redactedSourceName =
        'Example [redacted] [redacted] '
        'https://redacted@example.com/private';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 1 ? source.copyWith(name: sensitiveSourceName) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除'));
    await _pumpRouteFrame(tester);

    expect(
      find.text('删除 $redactedSourceName 后，该源历史文章也会一并从本地清理。'),
      findsOneWidget,
    );
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('source-user:source-pass'), findsNothing);
  });

  testWidgets('source menu toggle feedback redacts sensitive source labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveSourceName =
        'Example token=source-token sk-source123456 '
        'https://source-user:source-pass@example.com/private';
    const redactedSourceName =
        'Example [redacted] [redacted] '
        'https://redacted@example.com/private';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 1 ? source.copyWith(name: sensitiveSourceName) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 1);
    expect(repository.updatedSources.last.enabled, isFalse);
    expect(find.text('已停用 $redactedSourceName'), findsOneWidget);
    expect(find.textContaining('source-token'), findsNothing);
  });

  testWidgets('source menu refresh explains API failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss refresh failed: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [1]);
    expect(find.text('刷新失败：源站服务异常（HTTP 503），请稍后重试'), findsOneWidget);
    expect(find.text('rss refresh failed: HTTP 503'), findsNothing);
  });

  testWidgets('source menu refresh explains restricted source failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss refresh failed: HTTP 403',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [1]);
    expect(
      find.text('刷新失败：源站限制抓取（HTTP 403），可在浏览器打开原站或更换 Feed 地址'),
      findsOneWidget,
    );
    expect(find.text('rss refresh failed: HTTP 403'), findsNothing);
  });

  testWidgets('source menu copies Feed URL', (tester) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('复制 Feed URL'));
    await _pumpRouteFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://example.com/feed.xml');
    expect(find.text('已复制 Example Daily 的 Feed URL'), findsOneWidget);
  });

  testWidgets('source menu copies diagnostics for a broken feed', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final brokenSourceMenu = find.byKey(
      const ValueKey<String>('source-menu-2'),
    );
    await tester.scrollUntilVisible(
      brokenSourceMenu,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrame(tester);

    await tester.tap(brokenSourceMenu);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('复制诊断信息'));
    await _pumpRouteFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('RSS Copilot Source Diagnostics'));
    expect(clipboard?.text, contains('Name: Tech Radar'));
    expect(clipboard?.text, contains('Folder: Engineering'));
    expect(
      clipboard?.text,
      contains(
        'Feed URL: https://redacted@tech.example.com/rss.xml?redacted=%5Bredacted%5D&topic=ai',
      ),
    );
    expect(
      clipboard?.text,
      contains(
        'Site URL: https://redacted@tech.example.com?redacted=%5Bredacted%5D&view=home',
      ),
    );
    expect(clipboard?.text, contains('Health: 抓取异常'));
    expect(clipboard?.text, contains('Unread: 4'));
    expect(
      clipboard?.text,
      contains('Last error: timeout while fetching feed'),
    );
    expect(
      clipboard?.text,
      contains('https://redacted@tech.example.com/private'),
    );
    expect(clipboard?.text, contains('Authorization: Bearer [redacted]'));
    expect(clipboard?.text, contains('Bearer [redacted]'));
    expect(clipboard?.text, contains('Basic [redacted]'));
    expect(clipboard?.text, contains('Cookie: [redacted]'));
    expect(clipboard?.text, contains('Set-Cookie: [redacted]'));
    expect(
      clipboard?.text,
      contains('Suggested action: 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
    expect(clipboard?.text, isNot(contains('source-user')));
    expect(clipboard?.text, isNot(contains('source-pass')));
    expect(clipboard?.text, isNot(contains('site-user')));
    expect(clipboard?.text, isNot(contains('site-pass')));
    expect(clipboard?.text, isNot(contains('error-user')));
    expect(clipboard?.text, isNot(contains('error-pass')));
    expect(clipboard?.text, isNot(contains('header.jwt')));
    expect(clipboard?.text, isNot(contains('header-key')));
    expect(clipboard?.text, isNot(contains('header-pass')));
    expect(clipboard?.text, isNot(contains('YmFzaWMtc2VjcmV0')));
    expect(clipboard?.text, isNot(contains('session=raw-session')));
    expect(clipboard?.text, isNot(contains('refresh=raw-refresh')));
    expect(find.text('已复制 Tech Radar 的诊断信息'), findsOneWidget);
  });

  testWidgets('source diagnostics snackbar redacts sensitive source names', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2
              ? source.copyWith(
                  name:
                      'Tech token=source-token sk-source123456 https://source-user:source-pass@tech.example/private',
                )
              : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final brokenSourceMenu = find.byKey(
      const ValueKey<String>('source-menu-2'),
    );
    await tester.scrollUntilVisible(
      brokenSourceMenu,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFrame(tester);

    await tester.tap(brokenSourceMenu);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('复制诊断信息'));
    await _pumpRouteFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains(
        'Name: Tech [redacted] [redacted] https://redacted@tech.example/private',
      ),
    );
    expect(
      find.text(
        '已复制 Tech [redacted] [redacted] https://redacted@tech.example/private 的诊断信息',
      ),
      findsOneWidget,
    );
    expect(clipboard?.text, isNot(contains('source-token')));
    expect(clipboard?.text, isNot(contains('sk-source123456')));
    expect(clipboard?.text, isNot(contains('source-user')));
    expect(clipboard?.text, isNot(contains('source-pass')));
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source123456'), findsNothing);
    expect(find.textContaining('source-user'), findsNothing);
    expect(find.textContaining('source-pass'), findsNothing);
  });

  testWidgets('source menu opens site URL externally', (tester) async {
    final launcher = _installMockUrlLauncher();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('打开站点'));
    await _pumpRouteFrame(tester);

    final launchCall = launcher.launchCall;
    expect(launchCall, isNotNull);
    expect(launchCall!.method, 'launch');
    final arguments = Map<String, Object?>.from(launchCall.arguments as Map);
    expect(arguments['url'], 'https://example.com');
    expect(arguments['useWebView'], isFalse);
  });

  testWidgets('source mark-read action is disabled when source has no unread', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-disabled')),
    );
    await _pumpFrame(tester);
    expect(find.text('Design Weekly'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-3')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记已读').last);
    await _pumpRouteFrame(tester);

    expect(find.text('标记订阅源已读'), findsNothing);
    expect(repository.markSourceReadIds, isEmpty);
  });

  testWidgets('source menu toggles automatic fetching without editing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 1);
    expect(repository.updatedSources.last.enabled, isFalse);
    expect(repository.refreshedSourceIds, isEmpty);
    expect(find.text('已停用 Example Daily'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-disabled')),
    );
    await _pumpFrame(tester);
    final disabledSourceMenu = find.byKey(
      const ValueKey<String>('source-menu-3'),
    );
    await tester.scrollUntilVisible(
      disabledSourceMenu,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await _pumpFrame(tester);
    await tester.tap(disabledSourceMenu);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('启用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 3);
    expect(repository.updatedSources.last.enabled, isTrue);
    expect(repository.refreshedSourceIds, [3]);
    expect(find.text('已启用 Design Weekly'), findsOneWidget);
  });

  testWidgets('source menu toggle enabled explains update API failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss source is unreachable: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources, isEmpty);
    expect(find.text('更新失败：源站服务异常（HTTP 503），请稍后重试'), findsOneWidget);
    expect(find.textContaining('rss source is unreachable'), findsNothing);
    expect(find.textContaining('刷新失败'), findsNothing);
  });

  testWidgets('source menu toggle enabled explains expired sessions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'invalid token',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources, isEmpty);
    expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.textContaining('invalid token'), findsNothing);
  });

  testWidgets('folder mark-read action requires confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('标记文件夹已读').first);
    await _pumpRouteFrame(tester);

    expect(find.text('标记文件夹已读'), findsOneWidget);
    expect(find.text('Newsletters 的 2 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await _pumpRouteFrame(tester);

    expect(repository.markFolderReadFolders, isEmpty);

    await tester.tap(find.byTooltip('标记文件夹已读').first);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markFolderReadFolders, ['Newsletters']);
    expect(find.text('已将 Newsletters 标记为已读'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1, 2]);
    expect(repository.queuedReadStates, isEmpty);
  });

  testWidgets('folder mark-read queues cached articles while offline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..syncFailuresRemaining = 3;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.syncNow();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('标记文件夹已读').first);
    await _pumpRouteFrame(tester);

    expect(find.text('离线时仅会将 Newsletters 已缓存的 2 篇未读文章加入待同步。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markFolderReadFolders, isEmpty);
    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(find.text('已将 Newsletters 的 2 篇已缓存文章加入待同步'), findsOneWidget);
    expect(find.text('离线状态下无法批量标记已读'), findsNothing);

    repository.syncFailuresRemaining = 0;
    await controller.syncNow();
    await _pumpFrame(tester);

    await tester.tap(find.text('撤销'));
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, isEmpty);
    expect(repository.queuedReadStates, ['1:false', '2:false']);
  });

  testWidgets('folder mark-read explains stale server scopes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..markFolderReadException = const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'folder not found',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('标记文件夹已读').first);
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markFolderReadFolders, ['Newsletters']);
    expect(find.text('批量标记失败：阅读范围已变化，请同步刷新后重试'), findsOneWidget);
    expect(find.text('folder not found'), findsNothing);
  });

  testWidgets('source add dialog validates required URL before submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);

    expect(find.text('Feed 或网站 URL'), findsOneWidget);
    expect(find.text('example.com/feed.json'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await tester.pump();

    expect(find.text('Feed 或网站 URL 不能为空'), findsOneWidget);
    expect(repository.addedSourceRequests, isEmpty);
  });

  testWidgets('source add dialog validates invalid URL before submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'not a url',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await tester.pump();

    expect(find.text('Feed 或网站 URL 请输入 http(s) URL 或域名 URL'), findsOneWidget);
    expect(repository.addedSourceRequests, isEmpty);
  });

  testWidgets('source add dialog accepts scheme-less JSON Feed URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.json',
    );
    expect(
      find.byKey(
        const ValueKey<String>('source-add-folder-suggestion-Engineering'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('source-add-folder-suggestion-Engineering'),
      ),
    );
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.addedSourceRequests, [
      (rssUrl: 'example.com/feed.json', folder: 'Engineering'),
    ]);
    expect(find.text('已添加订阅源'), findsOneWidget);
  });

  testWidgets('source add folder suggestions redact sensitive folder labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveFolder = 'Engineering api_key=folder-secret';
    const redactedFolder = 'Engineering [redacted]';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2 ? source.copyWith(folder: sensitiveFolder) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.json',
    );

    final sensitiveSuggestion = find.byKey(
      const ValueKey<String>('source-add-folder-suggestion-$sensitiveFolder'),
    );
    expect(sensitiveSuggestion, findsOneWidget);
    expect(
      find.descendant(
        of: sensitiveSuggestion,
        matching: find.text(redactedFolder),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('folder-secret'), findsNothing);

    await tester.tap(sensitiveSuggestion);
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.addedSourceRequests, [
      (rssUrl: 'example.com/feed.json', folder: sensitiveFolder),
    ]);
  });

  testWidgets('source add dialog reports timeout before submit completes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..addSourceException = TimeoutException('slow source create');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('添加请求超时，请稍后重试'), findsOneWidget);
    expect(repository.addedSourceRequests, isEmpty);
  });

  testWidgets(
    'source add dialog explains network loss before submit completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store, includeSourceCatalog: true)
        ..addSourceException = const NetworkException('offline source create');
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      controller.selectSection(AppSection.sources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
      await _pumpRouteFrame(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('source-add-url-field')),
        'example.com/feed.xml',
      );
      await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
      await _pumpRouteFrame(tester);

      expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试添加订阅源'), findsOneWidget);
      expect(find.text('离线状态下无法添加订阅源'), findsNothing);
      expect(controller.state.isOnline, isFalse);
      expect(repository.addedSourceRequests, isEmpty);
    },
  );

  testWidgets('source add dialog explains duplicate source conflicts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..addSourceException = const ApiException(
        statusCode: 409,
        code: 'CONFLICT',
        message: 'duplicate feed source',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('添加失败：这个 Feed 已经在订阅列表里'), findsOneWidget);
    expect(repository.addedSourceRequests, isEmpty);
  });

  testWidgets('source add dialog explains failed website discovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..addSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss feed could not be discovered',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('添加失败：没有在这个页面发现可用 RSS/Atom/JSON Feed'), findsOneWidget);
    expect(repository.addedSourceRequests, isEmpty);
  });

  testWidgets('source add dialog keeps saved source after refresh timeout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = TimeoutException('slow source refresh');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('已添加订阅源，但刷新请求超时，请稍后重试'), findsOneWidget);
    expect(repository.addedSourceRequests, [
      (rssUrl: 'example.com/feed.xml', folder: defaultSourceFolder),
    ]);
    expect(repository.refreshedSourceIds, [99]);
    expect(controller.state.selectedSourceId, 99);
    expect(
      controller.state.snapshot.sourceById(99)?.rssUrl,
      'example.com/feed.xml',
    );
  });

  testWidgets('source add dialog explains refresh HTTP failures after save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss refresh failed: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-add-button')));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-add-url-field')),
      'example.com/feed.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-add-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('已添加订阅源，但刷新失败：源站服务异常（HTTP 503），请稍后重试'), findsOneWidget);
    expect(repository.addedSourceRequests, [
      (rssUrl: 'example.com/feed.xml', folder: defaultSourceFolder),
    ]);
    expect(repository.refreshedSourceIds, [99]);
    expect(
      controller.state.snapshot.sourceById(99)?.rssUrl,
      'example.com/feed.xml',
    );
  });

  testWidgets('source edit dialog validates required fields before submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-name-field')),
      ' ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-rss-url-field')),
      ' ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await tester.pump();

    expect(find.text('名称 不能为空'), findsOneWidget);
    expect(find.text('Feed 或网站 URL 不能为空'), findsOneWidget);
    expect(repository.updatedSources, isEmpty);
  });

  testWidgets('source edit dialog validates URL fields before submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-rss-url-field')),
      'not a url',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-icon-url-field')),
      'favicon.ico',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await tester.pump();

    expect(find.text('Feed 或网站 URL 请输入 http(s) URL 或域名 URL'), findsOneWidget);
    expect(find.text('图标 URL 请输入 http(s) URL'), findsOneWidget);
    expect(repository.updatedSources, isEmpty);
  });

  testWidgets('source edit dialog accepts scheme-less website URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);

    expect(find.text('Feed 或网站 URL'), findsOneWidget);
    final currentIconPreview = tester.widget<Image>(
      find.byKey(const ValueKey<String>('source-edit-icon-preview-image')),
    );
    expect(
      (currentIconPreview.image as NetworkImage).url,
      'https://example.com/favicon.ico',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-rss-url-field')),
      'example.com',
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('source-edit-folder-suggestion-Engineering'),
      ),
    );
    await _pumpFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-icon-url-field')),
      '',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('source-edit-icon-preview-fallback')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.single.rssUrl, 'example.com');
    expect(repository.updatedSources.single.folder, 'Engineering');
    expect(repository.updatedSources.single.iconUrl, isNull);
    expect(find.text('已更新订阅源'), findsOneWidget);
  });

  testWidgets('source edit folder suggestions redact sensitive folder labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveFolder = 'Engineering api_key=folder-secret';
    const redactedFolder = 'Engineering [redacted]';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2 ? source.copyWith(folder: sensitiveFolder) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);

    final sensitiveSuggestion = find.byKey(
      const ValueKey<String>('source-edit-folder-suggestion-$sensitiveFolder'),
    );
    expect(sensitiveSuggestion, findsOneWidget);
    expect(
      find.descendant(
        of: sensitiveSuggestion,
        matching: find.text(redactedFolder),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('folder-secret'), findsNothing);

    await tester.tap(sensitiveSuggestion);
    await _pumpFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.single.folder, sensitiveFolder);
  });

  testWidgets('source edit dialog reports timeout before submit completes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = TimeoutException('slow source update');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('编辑请求超时，请稍后重试'), findsOneWidget);
    expect(repository.updatedSources, isEmpty);
  });

  testWidgets(
    'source edit dialog explains network loss before submit completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store, includeSourceCatalog: true)
        ..updateSourceException = const NetworkException(
          'offline source update',
        );
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      controller.selectSection(AppSection.sources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
      await _pumpRouteFrame(tester);
      await tester.tap(find.text('编辑').last);
      await _pumpRouteFrame(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('source-edit-submit')),
      );
      await _pumpRouteFrame(tester);

      expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试编辑订阅源'), findsOneWidget);
      expect(find.text('离线状态下无法编辑订阅源'), findsNothing);
      expect(controller.state.isOnline, isFalse);
      expect(repository.updatedSources, isEmpty);
    },
  );

  testWidgets('source edit dialog explains duplicate source conflicts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = const ApiException(
        statusCode: 409,
        code: 'CONFLICT',
        message: 'duplicate feed source',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('更新失败：这个 Feed 已经在订阅列表里'), findsOneWidget);
    expect(repository.updatedSources, isEmpty);
  });

  testWidgets('source edit dialog keeps saved edits after refresh timeout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = TimeoutException('slow source refresh');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-name-field')),
      'Tech Weekly',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('已更新订阅源，但刷新请求超时，请稍后重试'), findsOneWidget);
    expect(repository.updatedSources.single.name, 'Tech Weekly');
    expect(repository.refreshedSourceIds, [1]);
    expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Weekly');
  });

  testWidgets('source edit dialog explains invalid feed refresh after save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'invalid rss feed: https://example.com/feed.xml',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑').last);
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-name-field')),
      'Tech Weekly',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(find.text('已更新订阅源，但刷新失败：这个地址返回的内容不是有效 Feed'), findsOneWidget);
    expect(repository.updatedSources.single.name, 'Tech Weekly');
    expect(repository.refreshedSourceIds, [1]);
    expect(controller.state.snapshot.sourceById(1)?.name, 'Tech Weekly');
  });

  testWidgets('source import dialog validates required OPML before submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('导入后刷新文章'), findsOneWidget);
    expect(find.text('适合刚从其他阅读器迁移，服务端会异步拉取新文章。'), findsOneWidget);
    expect(find.text('重复订阅、缺少 xmlUrl 或 URL 无效的条目会被跳过并计数。'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await tester.pump();

    expect(find.text('OPML 不能为空'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
  });

  testWidgets('source import dialog submits OPML and refresh preference', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-refresh-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.importedOpmlRequests, [
      (
        opml: '<opml version="2.0"><body></body></opml>',
        refreshAfterImport: false,
      ),
    ]);
    expect(
      find.text('已导入 2 个订阅源，跳过 1 个重复、缺少 xmlUrl 或 URL 无效的条目。'),
      findsOneWidget,
    );
  });

  testWidgets('source import dialog explains when every OPML entry is skipped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      importOpmlImportedCount: 0,
      importOpmlSkippedCount: 3,
    )..importOpmlRefreshAcceptedCount = 0;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body><outline text="Duplicate" xmlUrl="https://example.com/rss" /></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.importedOpmlRequests, isNotEmpty);
    expect(
      find.text('没有导入新订阅源，跳过 3 个重复、缺少 xmlUrl 或 URL 无效的条目，没有新增订阅源需要刷新。'),
      findsOneWidget,
    );
    expect(find.textContaining('已导入 0 个订阅源'), findsNothing);
    expect(controller.state.snapshot.sourceById(88), isNull);
  });

  testWidgets('source import dialog omits zero skipped count', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      importOpmlImportedCount: 2,
      importOpmlSkippedCount: 0,
    )..importOpmlRefreshAcceptedCount = 0;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body><outline text="New" xmlUrl="https://example.com/rss" /></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('已导入 2 个订阅源，没有新增订阅源需要刷新。'), findsOneWidget);
    expect(find.textContaining('跳过 0 个'), findsNothing);
  });

  testWidgets('source import dialog explains invalid OPML documents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'invalid opml document',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<html>not opml</html>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('导入失败：OPML 格式无效，请确认文件来自其他 RSS 阅读器导出'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
    expect(controller.state.snapshot.sourceById(88), isNull);
  });

  testWidgets(
    'source import dialog explains network loss before import completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store, includeSourceCatalog: true)
        ..importOpmlException = const NetworkException('offline opml import');
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      controller.selectSection(AppSection.sources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('source-import-button')),
      );
      await _pumpRouteFrame(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('source-import-opml-field')),
        '<opml version="2.0"><body></body></opml>',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('source-import-submit')),
      );
      await _pumpRouteFrame(tester);

      expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试导入 OPML'), findsOneWidget);
      expect(find.text('离线状态下无法导入 OPML'), findsNothing);
      expect(repository.importedOpmlRequests, isEmpty);
      expect(controller.state.isOnline, isFalse);
    },
  );

  testWidgets('source import dialog explains timeout before import completes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlException = TimeoutException('slow opml import');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('导入请求超时，请稍后重试'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
    expect(controller.state.isOnline, isFalse);
  });

  testWidgets('source import dialog explains oversized OPML migrations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlException = const ApiException(
        statusCode: 413,
        code: 'PAYLOAD_TOO_LARGE',
        message: 'opml document is too large',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('导入失败：OPML 文件太大，请先在原阅读器分批导出后再导入'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
  });

  testWidgets('source import dialog explains too many OPML subscriptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'opml contains too many subscriptions',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(find.text('导入失败：一次导入的订阅源太多，请分批导入 OPML'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
  });

  testWidgets('source import dialog explains OPML without subscriptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'opml contains no rss subscriptions',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body><outline text="Empty Folder" /></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.text('导入失败：这个 OPML 里没有可导入的 RSS 订阅源，请确认导出文件包含订阅条目'),
      findsOneWidget,
    );
    expect(
      find.textContaining('opml contains no rss subscriptions'),
      findsNothing,
    );
    expect(repository.importedOpmlRequests, isEmpty);
  });

  testWidgets('source import dialog can paste OPML from clipboard', (
    tester,
  ) async {
    final clipboard = _installMockClipboard();
    clipboard.text =
        '<opml version="2.0"><body><outline text="A" /></body></opml>';

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-paste-opml')),
    );
    await tester.pump();

    expect(
      find.text('<opml version="2.0"><body><outline text="A" /></body></opml>'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.importedOpmlRequests, [
      (
        opml: '<opml version="2.0"><body><outline text="A" /></body></opml>',
        refreshAfterImport: true,
      ),
    ]);
    expect(
      find.text('已导入 2 个订阅源，跳过 1 个重复、缺少 xmlUrl 或 URL 无效的条目，已开始刷新 2 个订阅源。'),
      findsOneWidget,
    );
  });

  testWidgets('source import dialog reports empty clipboard paste', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-paste-opml')),
    );
    await tester.pump();

    expect(find.text('剪贴板没有 OPML 内容'), findsOneWidget);
    expect(repository.importedOpmlRequests, isEmpty);
  });

  testWidgets('source export copies OPML to clipboard', (tester) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-export-button')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, '<opml version="2.0"><body></body></opml>');
    expect(find.text('OPML 已复制，可粘贴到其他阅读器'), findsOneWidget);
  });

  testWidgets('source export disables migration actions while copying', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final exportCompleter = Completer<String>();
    final repository = _ShortcutRepository(
      store,
      includeSourceCatalog: true,
      exportOpmlCompleter: exportCompleter,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      if (!exportCompleter.isCompleted) {
        exportCompleter.complete('<opml version="2.0"><body></body></opml>');
      }
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-export-button')),
    );
    await tester.pump();

    expect(controller.state.busy, isTrue);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('source-export-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('source-import-button')),
          )
          .onPressed,
      isNull,
    );

    exportCompleter.complete('<opml version="2.0"><body></body></opml>');
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(controller.state.busy, isFalse);
    expect(clipboard?.text, '<opml version="2.0"><body></body></opml>');
    expect(find.text('OPML 已复制，可粘贴到其他阅读器'), findsOneWidget);
  });

  testWidgets('source export works from local cache while offline', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..syncFailuresRemaining = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-export-button')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, '<opml version="2.0"><body></body></opml>');
    expect(find.text('OPML 已复制，可粘贴到其他阅读器'), findsOneWidget);
  });

  testWidgets('source export error does not blame offline mode', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..exportOpmlException = const NetworkException('cache read failed');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-export-button')),
    );
    await _pumpFrame(tester);

    expect(find.text('OPML 导出使用本地缓存，但当前缓存读取失败'), findsOneWidget);
    expect(find.text('离线状态下无法导出 OPML'), findsNothing);
  });

  testWidgets('source export explains server failures', (tester) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..exportOpmlException = const ApiException(
        statusCode: 503,
        code: 'SERVER_ERROR',
        message: 'opml export failed',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-export-button')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, isNull);
    expect(find.text('导出失败：服务端暂时无法生成 OPML，请稍后重试'), findsOneWidget);
    expect(find.text('opml export failed'), findsNothing);
  });

  testWidgets('source import dialog keeps imported sources after sync timeout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlSyncExceptionCause = TimeoutException('sync timed out');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.text(
        '已导入 2 个订阅源，跳过 1 个重复、缺少 xmlUrl 或 URL 无效的条目，已开始刷新 2 个订阅源，但同步请求超时，请稍后刷新',
      ),
      findsOneWidget,
    );
    expect(repository.importedOpmlRequests, [
      (
        opml: '<opml version="2.0"><body></body></opml>',
        refreshAfterImport: true,
      ),
    ]);
    expect(controller.state.isOnline, isFalse);
    expect(controller.state.snapshot.sourceById(88)?.name, 'Imported OPML');
  });

  testWidgets('source import dialog explains refresh API failures after import', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..importOpmlSyncExceptionCause = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss refresh failed: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-button')),
    );
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-import-opml-field')),
      '<opml version="2.0"><body></body></opml>',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('source-import-submit')),
    );
    await _pumpRouteFrame(tester);

    expect(
      find.text(
        '已导入 2 个订阅源，跳过 1 个重复、缺少 xmlUrl 或 URL 无效的条目，已开始刷新 2 个订阅源，但刷新失败：源站服务异常（HTTP 503），请稍后重试',
      ),
      findsOneWidget,
    );
    expect(controller.state.snapshot.sourceById(88)?.name, 'Imported OPML');
    expect(controller.state.isOnline, isTrue);
  });

  testWidgets('source delete action removes the source after confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpRouteFrame(tester);

    expect(repository.deletedSourceIds, [1]);
    expect(find.text('已删除 Example Daily'), findsOneWidget);
    expect(controller.state.snapshot.sourceById(1), isNull);
    expect(find.byKey(const ValueKey<String>('source-card-1')), findsNothing);
  });

  testWidgets('source delete action reports timeout after confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..deleteSourceException = TimeoutException('slow source delete');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpRouteFrame(tester);

    expect(find.text('删除请求超时，请稍后重试'), findsOneWidget);
    expect(repository.deletedSourceIds, isEmpty);
  });

  testWidgets('source delete action explains network loss after confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..deleteSourceException = const NetworkException('offline source delete');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpRouteFrame(tester);

    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试删除订阅源'), findsOneWidget);
    expect(find.text('离线状态下无法删除订阅源'), findsNothing);
    expect(repository.deletedSourceIds, isEmpty);
    expect(controller.state.isOnline, isFalse);
  });

  testWidgets('source delete action explains already deleted sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..deleteSourceException = const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'feed source not found',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byKey(const ValueKey<String>('source-menu-1')));
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除').last);
    await _pumpRouteFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpRouteFrame(tester);

    expect(find.text('删除失败：订阅源已在服务端删除，请刷新同步本地列表'), findsOneWidget);
    expect(repository.deletedSourceIds, isEmpty);
    expect(controller.state.snapshot.sourceById(1)?.name, 'Example Daily');
  });

  testWidgets('source health panel retries retryable issue sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesAcceptedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-retry-issues')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2, 4]);
    expect(find.text('已请求刷新 1 个待处理订阅源，跳过 1 个不可用源'), findsOneWidget);
  });

  testWidgets('source health panel explains refresh API failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'invalid rss feed: https://example.com/feed.xml',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-retry-issues')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2, 4]);
    expect(find.text('刷新失败：这个地址返回的内容不是有效 Feed'), findsOneWidget);
    expect(
      find.text('invalid rss feed: https://example.com/feed.xml'),
      findsNothing,
    );
  });

  testWidgets('source health panel explains retry network failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = const NetworkException('offline');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-retry-issues')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2, 4]);
    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试待处理订阅源'), findsOneWidget);
    expect(find.text('离线状态下无法重试待处理订阅源'), findsNothing);
  });

  testWidgets('source health panel explains retry timeouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = TimeoutException('slow retry');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-retry-issues')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2, 4]);
    expect(find.text('重试待处理订阅源请求超时，请稍后重试'), findsOneWidget);
    expect(find.text('刷新请求超时，请稍后重试'), findsNothing);
  });

  testWidgets('source health panel refreshes visible enabled sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesAcceptedCount = 1
      ..refreshSourcesSkippedCount = 2;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'tech',
    );
    await _pumpFrame(tester);

    expect(find.text('Tech Radar'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个当前筛选订阅源，跳过 2 个不可用源'), findsOneWidget);
  });

  testWidgets('source health panel explains visible refresh API failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss source is unreachable: HTTP 502',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'tech',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('刷新失败：源站服务异常（HTTP 502），请稍后重试'), findsOneWidget);
    expect(find.text('rss source is unreachable: HTTP 502'), findsNothing);
  });

  testWidgets('source health panel explains visible refresh size limits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'too many feed sources to refresh',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'tech',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('刷新失败：一次最多刷新 100 个订阅源，请缩小筛选范围后重试'), findsOneWidget);
    expect(find.text('too many feed sources to refresh'), findsNothing);
  });

  testWidgets('source health panel explains visible refresh network failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = const NetworkException('offline');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'tech',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试刷新当前筛选订阅源'), findsOneWidget);
    expect(find.text('离线状态下无法刷新当前筛选订阅源'), findsNothing);
  });

  testWidgets('source health panel explains visible refresh timeouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesException = TimeoutException('slow visible refresh');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-search-field')),
      'tech',
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('刷新当前筛选订阅源请求超时，请稍后重试'), findsOneWidget);
    expect(find.text('刷新请求超时，请稍后重试'), findsNothing);
  });

  testWidgets('source health panel refreshes selected filter sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourcesAcceptedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.sources);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-list-filter-unread')),
    );
    await _pumpFrame(tester);

    expect(find.text('Example Daily'), findsOneWidget);
    expect(find.text('Tech Radar'), findsOneWidget);
    expect(find.text('Design Weekly'), findsNothing);
    expect(find.text('Archive Planet'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-health-refresh-visible')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [1, 2]);
    expect(find.text('已请求刷新 1 个当前筛选订阅源，跳过 1 个不可用源'), findsOneWidget);
  });

  testWidgets(
    'source health panel explains skipped sources when none accepted',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store, includeSourceCatalog: true)
        ..refreshSourcesAcceptedCount = 0
        ..refreshSourcesSkippedCount = 1;
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      controller.selectSection(AppSection.sources);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('source-list-filter-unread')),
      );
      await _pumpFrame(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('source-health-refresh-visible')),
      );
      await _pumpRouteFrame(tester);

      expect(repository.refreshedSourceIds, [1, 2]);
      expect(
        find.text('当前筛选没有订阅源被服务端接收，跳过 1 个不可用源，其余可能已删除或停用'),
        findsOneWidget,
      );
    },
  );

  testWidgets('sort order switches the current reading queue direction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeOlderFeedUnread: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.newestFirst);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-sort-control-semantics')),
          )
          .properties
          .label,
      '阅读队列排序，当前新到旧',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Older',
    ]);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-sort-oldest-first')),
    );
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.oldestFirst);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-sort-control-semantics')),
          )
          .properties
          .label,
      '阅读队列排序，当前旧到新',
    );
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.oldestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Older',
      'Second',
      'First',
    ]);
    expect(controller.state.selectedEntryId, 1);
    expect(find.text('4月9日'), findsOneWidget);

    final shortestSort = find.byKey(
      const ValueKey<String>('entry-sort-shortest-first'),
    );
    await tester.ensureVisible(shortestSort);
    await _pumpFrame(tester);
    await tester.tap(shortestSort);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.shortestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.shortestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Older',
    ]);

    final longestSort = find.byKey(
      const ValueKey<String>('entry-sort-longest-first'),
    );
    await tester.ensureVisible(longestSort);
    await _pumpFrame(tester);
    await tester.tap(longestSort);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.longestFirst);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-sort-control-semantics')),
          )
          .properties
          .label,
      '阅读队列排序，当前长文优先',
    );
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.longestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Older',
      'First',
      'Second',
    ]);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-sort-newest-first')),
    );
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.newestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.newestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Older',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.oldestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.oldestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Older',
      'Second',
      'First',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.shortestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.shortestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Older',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.longestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.longestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Older',
      'First',
      'Second',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.newestFirst);
    expect(
      repository._readerPreferences.entrySortOrder,
      EntrySortOrder.newestFirst,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Older',
    ]);
  });

  testWidgets('sort order restores from local reader preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeOlderFeedUnread: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        entrySortOrder: EntrySortOrder.oldestFirst,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.entrySortOrder, EntrySortOrder.oldestFirst);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Older',
      'Second',
      'First',
    ]);
  });

  testWidgets('reading context restores from local reader preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        lastSection: AppSection.feed.name,
        lastSelectedEntryId: 7,
        lastEntrySourceFilterId: 2,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.feed);
    expect(controller.state.entrySourceFilterId, 2);
    expect(controller.state.selectedEntryId, 7);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('reading context is saved while navigating the queue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    controller.setEntrySourceFilter(2);
    await _pumpFrame(tester);

    expect(repository._readerPreferences.lastSection, AppSection.feed.name);
    expect(repository._readerPreferences.lastEntrySourceFilterId, 2);
    expect(repository._readerPreferences.lastSelectedEntryId, 6);

    await controller.openEntry(7);
    await _pumpFrame(tester);

    expect(repository._readerPreferences.lastSelectedEntryId, 7);
    expect(repository._readerPreferences.lastEntrySourceFilterId, 2);
  });

  testWidgets('settings and account navigation preserves reading context', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    controller.setEntrySourceFilter(2);
    await controller.openEntry(7);
    await _pumpFrame(tester);

    controller.selectSection(AppSection.settings);
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.settings);
    expect(controller.state.entrySourceFilterId, 2);
    expect(repository._readerPreferences.lastSection, AppSection.feed.name);
    expect(repository._readerPreferences.lastEntrySourceFilterId, 2);
    expect(repository._readerPreferences.lastSelectedEntryId, 7);

    controller.selectSection(AppSection.account);
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, 2);
    expect(repository._readerPreferences.lastSection, AppSection.feed.name);
    expect(repository._readerPreferences.lastEntrySourceFilterId, 2);
    expect(repository._readerPreferences.lastSelectedEntryId, 7);

    controller.selectSection(AppSection.feed);
    await _pumpFrame(tester);

    expect(controller.state.entrySourceFilterId, 2);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('list density switches and restores from local preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: firstCard, matching: find.text('Summary 1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>('entry-density-control-semantics'),
            ),
          )
          .properties
          .label,
      '文章列表密度，当前舒适',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-density-compact')),
    );
    await _pumpFrame(tester);

    expect(
      repository._readerPreferences.entryListDensity,
      EntryListDensity.compact,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>('entry-density-control-semantics'),
            ),
          )
          .properties
          .label,
      '文章列表密度，当前紧凑',
    );
    expect(
      find.descendant(of: firstCard, matching: find.text('Summary 1')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await _pumpFrame(tester);

    expect(
      repository._readerPreferences.entryListDensity,
      EntryListDensity.comfortable,
    );
    expect(
      find.descendant(of: firstCard, matching: find.text('Summary 1')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await _pumpFrame(tester);

    expect(
      repository._readerPreferences.entryListDensity,
      EntryListDensity.compact,
    );
    expect(
      find.descendant(of: firstCard, matching: find.text('Summary 1')),
      findsNothing,
    );

    final restoredRepository = _ShortcutRepository(
      store,
      readerPreferences: repository._readerPreferences,
    );
    final restoredController = AppController(repository: restoredRepository);
    await restoredController.initialize();

    expect(
      restoredController.state.readerPreferences.entryListDensity,
      EntryListDensity.compact,
    );
    restoredController.dispose();
  });

  testWidgets('continue reading filter narrows to partial progress entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeInProgressFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('继续阅读 · 1'), findsOneWidget);
    final unreadQueueFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('queue-filter-unread')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(unreadQueueFilterSemantics.properties.label, '阅读队列过滤，未读，3 篇文章，点击筛选');
    expect(unreadQueueFilterSemantics.properties.button, isTrue);
    expect(unreadQueueFilterSemantics.properties.enabled, isTrue);
    final inProgressQueueFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('queue-filter-in-progress')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      inProgressQueueFilterSemantics.properties.label,
      '阅读队列过滤，继续阅读，1 篇文章，点击筛选',
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Half Read',
      'Second',
    ]);

    controller.toggleUnreadOnly(true);
    await _pumpFrame(tester);

    expect(controller.state.unreadOnly, isTrue);
    expect(repository.loadedListKeys.last, ListKey.unreadInView('feed'));
    final selectedUnreadQueueFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('queue-filter-unread')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      selectedUnreadQueueFilterSemantics.properties.label,
      '阅读队列过滤，未读，3 篇文章，当前筛选',
    );
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.unread,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Half Read',
      'Second',
    ]);

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-filter-in-progress')),
    );
    await _pumpFrame(tester);

    expect(controller.state.unreadOnly, isFalse);
    expect(controller.state.inProgressOnly, isTrue);
    final selectedInProgressQueueFilterSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('queue-filter-in-progress')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      selectedInProgressQueueFilterSemantics.properties.label,
      '阅读队列过滤，继续阅读，1 篇文章，当前筛选',
    );
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.inProgress,
    );
    expect(controller.state.selectedEntryId, 8);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Half Read',
    ]);
    expect(find.text('Half Read'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await _pumpFrame(tester);

    expect(controller.state.inProgressOnly, isFalse);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.all,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Half Read',
      'Second',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await _pumpFrame(tester);

    expect(controller.state.inProgressOnly, isTrue);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.inProgress,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Half Read',
    ]);
  });

  testWidgets('queue workload shows remaining time and in-progress count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeInProgressFeed: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('3 篇当前列表'), findsOneWidget);
    expect(find.text('3 未读'), findsOneWidget);
    expect(find.text('未读剩余约 3 分钟'), findsOneWidget);
    expect(find.text('1 继续读'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('queue-workload-unread')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-workload-in-progress')),
      findsOneWidget,
    );

    final halfReadCard = find.ancestor(
      of: find.text('Half Read'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: halfReadCard.first, matching: find.text('剩余 1 分钟')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-card-8-semantics')),
          )
          .properties
          .label,
      '文章，Half Read，来源 Example，未读，阅读进度 42%，剩余 1 分钟，点击打开',
    );

    final progressBar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: halfReadCard.first,
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(progressBar.semanticsLabel, 'Half Read 阅读进度，剩余 1 分钟');
    expect(progressBar.semanticsValue, '42');

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-workload-unread')),
    );
    await _pumpFrame(tester);

    expect(controller.state.unreadOnly, isTrue);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.unread,
    );

    final inProgressWorkloadChip = find.byKey(
      const ValueKey<String>('queue-workload-in-progress'),
    );
    await tester.ensureVisible(inProgressWorkloadChip);
    await _pumpFrame(tester);
    await tester.tap(inProgressWorkloadChip);
    await _pumpFrame(tester);

    expect(controller.state.unreadOnly, isFalse);
    expect(controller.state.inProgressOnly, isTrue);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.inProgress,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Half Read',
    ]);
  });

  testWidgets('queue filter restores from local reader preferences', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeInProgressFeed: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        entryQueueFilter: EntryQueueFilter.inProgress,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.unreadOnly, isFalse);
    expect(controller.state.inProgressOnly, isTrue);
    expect(controller.state.selectedEntryId, 8);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'Half Read',
    ]);
    expect(find.text('Half Read'), findsWidgets);
  });

  testWidgets('translation visibility restores from local reader preferences', (
    tester,
  ) async {
    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        showTranslations: false,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    expect(controller.state.showTranslations, isFalse);

    controller.toggleTranslations(true);
    await _pumpFrame(tester);

    expect(controller.state.showTranslations, isTrue);
    expect(repository._readerPreferences.showTranslations, isTrue);
    controller.dispose();

    final restoredController = AppController(repository: repository);
    await restoredController.initialize();

    expect(restoredController.state.showTranslations, isTrue);
    restoredController.dispose();
  });

  testWidgets('continue reading empty state can clear the queue filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-filter-in-progress')),
    );
    await _pumpFrame(tester);

    expect(controller.state.inProgressOnly, isTrue);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.inProgress,
    );
    expect(controller.visibleEntries, isEmpty);
    expect(find.text('没有读到一半的文章'), findsOneWidget);

    await tester.tap(find.text('查看全部'));
    await _pumpFrame(tester);

    expect(controller.state.inProgressOnly, isFalse);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.all,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
    ]);
  });

  testWidgets('unread empty state can refresh current range', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.markEntriesRead([1, 2]);
    controller.toggleUnreadOnly(true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.visibleEntries, isEmpty);
    expect(find.text('没有未读文章'), findsOneWidget);
    expect(find.text('刷新当前范围'), findsOneWidget);

    await tester.tap(find.text('刷新当前范围'));
    await _pumpRouteFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 1 个订阅源'), findsOneWidget);
  });

  testWidgets('empty search state can clear the query', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(find.byType(TextFormField), 'no-results');
    await _pumpFrame(tester);

    expect(controller.visibleEntries, isEmpty);
    expect(find.text('没有匹配的文章'), findsOneWidget);
    expect(find.text('刷新当前范围'), findsOneWidget);

    await tester.tap(find.text('刷新当前范围'));
    await _pumpRouteFrame(tester);

    expect(repository.refreshAllRequests, 1);
    expect(find.text('已请求刷新 1 个订阅源'), findsOneWidget);

    await tester.tap(find.text('清空搜索'));
    await _pumpFrame(tester);

    expect(controller.state.searchQuery, isEmpty);
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
    ]);
    expect(find.text('First'), findsWidgets);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('empty search state can clear stacked reading filters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntrySourceFilter(2);
    controller.toggleUnreadOnly(true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(find.byType(TextFormField), 'no-results');
    await _pumpFrame(tester);

    expect(controller.visibleEntries, isEmpty);
    expect(controller.state.searchQuery, 'no-results');
    expect(controller.state.entrySourceFilterId, 2);
    expect(controller.state.unreadOnly, isTrue);
    expect(find.text('没有匹配的文章'), findsOneWidget);
    expect(find.text('清空搜索'), findsOneWidget);
    expect(find.text('清空全部筛选'), findsOneWidget);
    expect(find.text('刷新当前范围'), findsWidgets);

    await tester.tap(find.text('清空全部筛选'));
    await _pumpFrame(tester);

    expect(controller.state.searchQuery, isEmpty);
    expect(controller.state.entrySourceFilterId, isNull);
    expect(controller.state.unreadOnly, isFalse);
    expect(
      repository._readerPreferences.entryQueueFilter,
      EntryQueueFilter.all,
    );
    expect(controller.visibleEntries.map((entry) => entry.title), [
      'First',
      'Second',
      'Tech Unread',
      'Tech Read',
    ]);
  });

  testWidgets('finish action marks current entry and opens next item', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(find.text('1/2 · 2 未读'), findsOneWidget);

    await tester.tap(find.text('读完下一篇'));
    await _pumpFrame(tester);

    expect(repository.markReadEntryIds, [1]);
    expect(repository.openedEntryIds, [2]);
    expect(controller.state.selectedEntryId, 2);
    expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(find.text('2/2 · 0 未读'), findsOneWidget);
  });

  testWidgets('finish action undo restores entries marked read by the action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('读完下一篇'));
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 2);
    expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
    expect(controller.state.snapshot.entries[2]!.isRead, isTrue);
    expect(find.text('已读完并打开下一篇'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1, 2]);
    expect(controller.state.snapshot.entries[1]!.isRead, isFalse);
    expect(controller.state.snapshot.entries[2]!.isRead, isFalse);
    expect(controller.state.selectedEntryId, 2);
  });

  testWidgets('entry quick actions update saved and read state from the list', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-card-1-semantics')),
          )
          .properties
          .label,
      '文章，First，来源 Example，未读，1 分钟，点击打开',
    );

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('稍后读')),
    );
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[1]!.isSaved, isTrue);
    expect(find.text('已加入稍后读'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-card-1-semantics')),
          )
          .properties
          .label,
      '文章，First，来源 Example，未读，稍后读，1 分钟，点击打开',
    );

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(controller.state.snapshot.entries[1]!.isSaved, isFalse);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('标记已读')),
    );
    await _pumpFrame(tester);

    expect(repository.markReadEntryIds, [1]);
    expect(controller.state.snapshot.entries[1]!.isRead, isTrue);
    expect(repository.openedEntryIds, isEmpty);
    expect(controller.state.selectedEntryId, 1);
    expect(find.text('已标记已读'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-card-1-semantics')),
          )
          .properties
          .label,
      '文章，First，来源 Example，已读，1 分钟，点击打开',
    );

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1]);
    expect(controller.state.snapshot.entries[1]!.isRead, isFalse);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('复制链接')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://example.com/1');
    expect(find.text('已复制原文链接'), findsOneWidget);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('复制笔记')),
    );
    await _pumpFrame(tester);

    final noteClipboard = await Clipboard.getData('text/plain');
    expect(
      noteClipboard?.text,
      '# First\n\n'
      '[打开原文](https://example.com/1)\n\n'
      '## 元信息\n\n'
      '- 来源：Example\n'
      '- 发布时间：2026-04-10 09:00 UTC\n\n'
      '## AI 总结\n\n'
      'Summary 1',
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('移入噪音箱')),
    );
    await _pumpFrame(tester);

    expect(repository.noiseEntryUpdates, ['1:true']);
    expect(controller.state.snapshot.entries[1]!.isNoise, isTrue);
    expect(controller.state.snapshot.listIds(ListKey.feed), [2]);
    expect(controller.state.snapshot.listIds(ListKey.noise), [1]);
    expect(find.text('已移入噪音箱'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.noiseEntryUpdates, ['1:true', '1:false']);
    expect(controller.state.snapshot.entries[1]!.isNoise, isFalse);
    expect(controller.state.snapshot.listIds(ListKey.feed), [1, 2]);
    expect(controller.state.snapshot.listIds(ListKey.noise), isEmpty);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('移入噪音箱')),
    );
    await _pumpFrame(tester);

    controller.selectSection(AppSection.noise);
    await _pumpFrame(tester);

    final noiseCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('entry-card-1-semantics')),
          )
          .properties
          .label,
      '文章，First，来源 Example，未读，噪音箱，1 分钟，点击打开',
    );
    await tester.tap(
      find.descendant(of: noiseCard, matching: find.byTooltip('恢复 Feed')),
    );
    await _pumpFrame(tester);

    expect(repository.noiseEntryUpdates, [
      '1:true',
      '1:false',
      '1:true',
      '1:false',
    ]);
    expect(controller.state.snapshot.entries[1]!.isNoise, isFalse);
    expect(controller.state.snapshot.listIds(ListKey.feed), [1, 2]);
    expect(controller.state.snapshot.listIds(ListKey.noise), isEmpty);
  });

  testWidgets('copy quick actions preserve the current undo affordance', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('标记已读')),
    );
    await _pumpFrame(tester);

    expect(find.text('已标记已读'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '撤销'), findsOneWidget);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('复制链接')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://example.com/1');
    expect(find.widgetWithText(SnackBarAction, '撤销'), findsOneWidget);

    tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
        .onPressed();
    await _pumpFrame(tester);

    expect(repository.markUnreadEntryIds, [1]);
    expect(controller.state.snapshot.entries[1]!.isRead, isFalse);

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('复制链接')),
    );
    await _pumpFrame(tester);

    expect(find.text('已复制原文链接'), findsOneWidget);
  });

  testWidgets('compact entry actions keep secondary commands in a menu', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(960, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        entryListDensity: EntryListDensity.compact,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );

    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('复制笔记')),
      findsNothing,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('更多操作')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('更多操作')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制笔记'));
    await tester.pumpAndSettle();

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('# First'));
    expect(clipboard?.text, contains('[打开原文](https://example.com/1)'));
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets(
    'offline entry quick action undo stays queued after network recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      await tester.pump();

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isFalse);

      Finder firstCard() =>
          find.ancestor(of: find.text('First'), matching: find.byType(Card));

      await tester.tap(
        find.descendant(of: firstCard(), matching: find.byTooltip('稍后读')),
      );
      await _pumpFrame(tester);
      expect(repository.queuedSavedStates, ['1:true']);
      expect(controller.state.snapshot.entries[1]!.isSaved, isTrue);

      await controller.syncNow();
      await _pumpFrame(tester);
      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isTrue);
      expect(repository.savedEntryUpdates, isEmpty);
      expect(repository.queuedSavedStates, ['1:true', '1:false']);
      expect(controller.state.snapshot.entries[1]!.isSaved, isFalse);

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();
      await _pumpFrame(tester);

      await tester.tap(
        find.descendant(of: firstCard(), matching: find.byTooltip('标记已读')),
      );
      await _pumpFrame(tester);
      expect(repository.queuedReadStates, ['1:true']);
      expect(controller.state.snapshot.entries[1]!.isRead, isTrue);

      await controller.syncNow();
      await _pumpFrame(tester);
      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isTrue);
      expect(repository.markUnreadEntryIds, isEmpty);
      expect(repository.queuedReadStates, ['1:true', '1:false']);
      expect(controller.state.snapshot.entries[1]!.isRead, isFalse);

      repository.syncFailuresRemaining = 1;
      await controller.syncNow();
      controller.clearError();
      await _pumpFrame(tester);

      await tester.tap(
        find.descendant(of: firstCard(), matching: find.byTooltip('移入噪音箱')),
      );
      await _pumpFrame(tester);
      expect(repository.queuedNoiseStates, ['1:true']);
      expect(controller.state.snapshot.entries[1]!.isNoise, isTrue);

      await controller.syncNow();
      await _pumpFrame(tester);
      tester
          .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '撤销'))
          .onPressed();
      await _pumpFrame(tester);

      expect(controller.state.isOnline, isTrue);
      expect(repository.noiseEntryUpdates, isEmpty);
      expect(repository.queuedNoiseStates, ['1:true', '1:false']);
      expect(controller.state.snapshot.entries[1]!.isNoise, isFalse);
      expect(controller.state.snapshot.listIds(ListKey.feed), [1, 2]);
      expect(controller.state.snapshot.listIds(ListKey.noise), isEmpty);
    },
  );

  testWidgets('AI retry shortcut reprocesses the selected failed article', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.selectedEntryId, 1);
    expect(
      controller.state.snapshot.entries[1]!.aiProcessingState,
      EntryAiProcessingState.failed,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, [1]);
    expect(
      controller.state.snapshot.entries[1]!.aiProcessingState,
      EntryAiProcessingState.pending,
    );
    expect(find.text('AI 已重新加入处理队列'), findsOneWidget);
  });

  testWidgets('entry quick action retries failed AI from the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );

    expect(
      find.descendant(of: firstCard, matching: find.text('AI 失败')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('重试 AI')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('重试 AI')),
    );
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, [1]);
    expect(
      controller.state.snapshot.entries[1]!.aiProcessingState,
      EntryAiProcessingState.pending,
    );
    expect(find.text('AI 已重新加入处理队列'), findsOneWidget);
    expect(
      find.descendant(of: firstCard, matching: find.text('AI 处理中')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('重试 AI')),
      findsNothing,
    );
  });

  testWidgets('entry quick action explains server entry conflicts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true)
      ..reprocessEntryAiException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'entry state is invalid',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final firstCard = find.ancestor(
      of: find.text('First'),
      matching: find.byType(Card),
    );

    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('重试 AI')),
    );
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, isEmpty);
    expect(find.text('操作失败：当前文章状态已变化，请刷新后重试'), findsOneWidget);
    expect(find.text('entry state is invalid'), findsNothing);
  });

  testWidgets('detail AI retry reports network write errors without throwing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    repository.reprocessFailuresRemaining = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isTrue);
    expect(find.text('AI 失败'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '重试 AI'), findsOneWidget);

    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '重试 AI'),
    );
    expect(retryButton.onPressed, isNotNull);

    retryButton.onPressed!();
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, isEmpty);
    expect(find.text('离线状态下不支持写操作'), findsOneWidget);
  });

  testWidgets('detail AI retry explains server entry conflicts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true)
      ..reprocessEntryAiException = const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'entry not found',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.widgetWithText(FilledButton, '重试 AI'));
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, isEmpty);
    expect(find.text('操作失败：文章已在服务端删除，请同步后重试'), findsOneWidget);
    expect(find.text('entry not found'), findsNothing);
  });

  testWidgets('detail AI retry explains expired sessions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeFailedAiEntry: true)
      ..reprocessEntryAiException = const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'invalid session',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.widgetWithText(FilledButton, '重试 AI'));
    await _pumpFrame(tester);

    expect(repository.reprocessedEntryIds, isEmpty);
    expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.text('invalid session'), findsNothing);
  });

  testWidgets('detail copy action writes the original link to clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('复制链接'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://example.com/1');
    expect(find.text('已复制原文链接'), findsOneWidget);
  });

  testWidgets('detail body sync reports fetched content result', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..fetchedEntryContentHtml = '<p>Full body</p>';
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('正文暂未同步完成'), findsOneWidget);

    await tester.ensureVisible(find.text('同步正文'));
    await _pumpFrame(tester);
    await tester.tap(find.text('同步正文'));
    await _pumpFrame(tester);

    expect(repository.openedEntryIds, contains(1));
    expect(find.text('正文已同步最新内容'), findsOneWidget);
    expect(find.text('正文暂未同步完成'), findsNothing);
    expect(find.text('Full body'), findsOneWidget);
  });

  testWidgets('detail body sync explains when content is still missing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.ensureVisible(find.text('同步正文'));
    await _pumpFrame(tester);
    await tester.tap(find.text('同步正文'));
    await _pumpFrame(tester);

    expect(repository.openedEntryIds, contains(1));
    expect(find.text('正文仍未同步，可稍后重试或打开原文'), findsOneWidget);
    expect(find.text('正文暂未同步完成'), findsOneWidget);
  });

  testWidgets('detail citation action writes markdown to clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('复制引用'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, '[First](https://example.com/1)');
    expect(find.text('已复制文章引用'), findsOneWidget);
  });

  testWidgets('detail summary action writes the AI summary to clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('复制总结'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'First\n\nSummary 1');
    expect(find.text('已复制 AI 总结'), findsOneWidget);
  });

  testWidgets('detail translation action writes bilingual text to clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeTranslatedEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('复制双语'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      'First\n\nHello world.\n\n你好，世界。\n\nSecond paragraph.\n\n第二段。',
    );
    expect(find.text('已复制双语译文'), findsOneWidget);
  });

  testWidgets('detail note action writes markdown reading note to clipboard', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeTranslatedEntry: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('复制笔记'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      '# First\n\n'
      '[打开原文](https://example.com/1)\n\n'
      '## 元信息\n\n'
      '- 来源：Example\n'
      '- 发布时间：2026-04-10 09:00 UTC\n\n'
      '## AI 总结\n\n'
      'Summary 1\n\n'
      '## 双语摘录\n\n'
      'Hello world.\n\n'
      '你好，世界。\n\n'
      'Second paragraph.\n\n'
      '第二段。',
    );
    expect(find.text('已复制阅读笔记'), findsOneWidget);
  });

  testWidgets('mobile settings exposes account management', (tester) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(390, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('设置'));
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('mobile-settings-account')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mobile-settings-section-ai')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-settings-account')),
    );
    await _pumpFrame(tester);

    expect(controller.state.section, AppSection.account);
    expect(find.text('账号'), findsWidgets);
    expect(find.text('demo@rsscopilot.local'), findsOneWidget);

    await tester.tap(find.byTooltip('复制服务端地址'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://reader.example');
    expect(find.text('已复制服务端地址'), findsOneWidget);
  });

  testWidgets('account diagnostics copy reader state without secrets', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      pendingSyncCount: 2,
      pendingSyncDescription: '标记已读 1、加入稍后读 1',
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        fontSize: 20,
        lineHeight: 1.9,
        width: ReaderWidth.wide,
        entrySortOrder: EntrySortOrder.oldestFirst,
        entryQueueFilter: EntryQueueFilter.inProgress,
        entryListDensity: EntryListDensity.compact,
        collapsedEntryDateSections: ['2026-04-10'],
        collapsedSourceFolders: ['Engineering'],
        showTranslations: false,
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntrySourceFilter(2);
    controller.setSearchQuery(
      ' Jane jane Analyst unread feed item source summary extra ignored ',
    );
    controller.selectSection(AppSection.account);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('account-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('RSS Copilot Diagnostics'));
    expect(clipboard?.text, contains('Account: demo@rsscopilot.local'));
    expect(clipboard?.text, contains('Server: https://reader.example'));
    expect(clipboard?.text, contains('Pending sync: 2'));
    expect(clipboard?.text, contains('Pending sync detail: 标记已读 1、加入稍后读 1'));
    expect(
      clipboard?.text,
      contains('Reading scope: source filter Tech Radar (#2)'),
    );
    expect(
      clipboard?.text,
      contains('Search: jane analyst unread feed item source summary extra'),
    );
    expect(clipboard?.text, isNot(contains('ignored')));
    expect(
      clipboard?.text,
      contains('Sources: 4 total, 1 healthy, 1 error, 1 stale, 1 disabled'),
    );
    expect(
      clipboard?.text,
      contains('Source issues: Tech Radar (#2) · 抓取异常 · 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(
      clipboard?.text,
      contains('Design Weekly (#3) · 已停用 · 如仍需接收新文章，请启用自动抓取后刷新此源'),
    );
    expect(
      clipboard?.text,
      contains('Archive Planet (#4) · 待刷新 · 超过 24 小时未刷新；请手动刷新此源'),
    );
    expect(clipboard?.text, contains('Theme: server SYSTEM, local FOLLOW'));
    expect(
      clipboard?.text,
      contains(
        'Reader: font 20.0, line 1.90, width wide, sort oldestFirst, queue inProgress, density compact, sourceSort original, translations false',
      ),
    );
    expect(clipboard?.text, contains('Collapsed dates: 2026-04-10'));
    expect(clipboard?.text, contains('Collapsed source folders: Engineering'));
    expect(
      clipboard?.text,
      contains('AI: provider DEEPSEEK, configured false, output zh-CN'),
    );
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
    expect(find.text('已复制诊断信息'), findsOneWidget);
  });

  testWidgets('account diagnostics redact sensitive free text and URLs', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      sessionBaseUrl:
          'https://server-user:server-pass@reader.example/app?api_key=server-secret&view=diagnostics',
      pendingSyncCount: 1,
      pendingSyncDescription:
          '重试 Authorization: Bearer pending.jwt X-API-Key: pending-key password: pending-pass Bearer abc.def token=pending-token sk-pending123456 https://pending-user:pending-pass@reader.example/sync',
      includeSourceCatalog: true,
      readerPreferences: ReaderPreferences.defaultPreferences.copyWith(
        collapsedSourceFolders: ['Engineering api_key=folder-secret'],
      ),
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntryFolderFilter('Engineering token=scope-token');
    controller.setSearchQuery(
      'token=search-token Authorization: Basic search-basic api-key: search-key Bearer abc.def sk-search123456 keep',
    );
    controller.selectSection(AppSection.account);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('account-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains(
        'Server: https://redacted@reader.example/app?redacted=%5Bredacted%5D&view=diagnostics',
      ),
    );
    expect(
      clipboard?.text,
      contains(
        'Pending sync detail: 重试 Authorization: Bearer [redacted] [redacted] [redacted] Bearer [redacted] [redacted] [redacted] https://redacted@reader.example/sync',
      ),
    );
    expect(
      clipboard?.text,
      contains(
        'Search: [redacted] authorization: basic [redacted] [redacted] Bearer [redacted]',
      ),
    );
    expect(
      clipboard?.text,
      contains('Collapsed source folders: Engineering [redacted]'),
    );
    expect(
      clipboard?.text,
      contains('Source issues: Tech Radar (#2) · 抓取异常 · 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(clipboard?.text, isNot(contains('server-secret')));
    expect(clipboard?.text, isNot(contains('server-user')));
    expect(clipboard?.text, isNot(contains('server-pass')));
    expect(clipboard?.text, isNot(contains('pending.jwt')));
    expect(clipboard?.text, isNot(contains('pending-token')));
    expect(clipboard?.text, isNot(contains('pending-key')));
    expect(clipboard?.text, isNot(contains('pending-pass')));
    expect(clipboard?.text, isNot(contains('pending-user')));
    expect(clipboard?.text, isNot(contains('folder-secret')));
    expect(clipboard?.text, isNot(contains('search-token')));
    expect(clipboard?.text, isNot(contains('search-basic')));
    expect(clipboard?.text, isNot(contains('search-key')));
    expect(clipboard?.text, isNot(contains('sk-')));
  });

  testWidgets('account diagnostics reports folder reading scope', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.setEntryFolderFilter('Engineering');
    controller.selectSection(AppSection.account);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('account-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains('Reading scope: folder filter Engineering'),
    );
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
  });

  testWidgets('source page copies reader diagnostics with source scope', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains('Reading scope: source page Tech Radar (#2)'),
    );
    expect(clipboard?.text, contains('Section: 订阅源文章'));
    expect(clipboard?.text, contains('Source: Tech Radar (#2)'));
    expect(clipboard?.text, contains('Source health: 抓取异常'));
    expect(
      clipboard?.text,
      contains(
        'Source feed URL: https://redacted@tech.example.com/rss.xml?redacted=%5Bredacted%5D&topic=ai',
      ),
    );
    expect(
      clipboard?.text,
      contains('Source suggested action: 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
    expect(clipboard?.text, isNot(contains('source-user')));
    expect(clipboard?.text, isNot(contains('source-pass')));
    expect(find.text('已复制诊断信息'), findsOneWidget);
  });

  testWidgets('source page diagnostics redact sensitive source labels', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 2
              ? source.copyWith(
                  name:
                      'Tech token=source-token sk-source123456 https://source-user:source-pass@tech.example.com/private',
                  folder: 'Engineering api_key=folder-secret',
                  lastErrorMessage:
                      'timeout while fetching https://error-user:error-pass@tech.example.com/private?api_key=error-key '
                      'Authorization: Bearer raw-error-token Cookie: session=raw-session',
                )
              : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.text(
        'Tech [redacted] [redacted] https://redacted@tech.example.com/private',
      ),
      findsOneWidget,
    );
    expect(find.text('Engineering [redacted]'), findsOneWidget);
    final healthSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('source-page-health-banner-semantics')),
    );
    expect(
      healthSemantics.properties.label,
      contains(
        'Tech [redacted] [redacted] https://redacted@tech.example.com/private',
      ),
    );
    expect(
      healthSemantics.properties.label,
      contains('Engineering [redacted]'),
    );
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source'), findsNothing);
    expect(find.textContaining('source-user'), findsNothing);
    expect(find.textContaining('source-pass'), findsNothing);
    expect(find.textContaining('folder-secret'), findsNothing);
    expect(find.textContaining('error-user'), findsNothing);
    expect(find.textContaining('error-pass'), findsNothing);
    expect(find.textContaining('error-key'), findsNothing);
    expect(find.textContaining('raw-error-token'), findsNothing);
    expect(find.textContaining('raw-session'), findsNothing);
    expect(
      find.textContaining(
        '错误：timeout while fetching https://redacted@tech.example.com/private',
      ),
      findsOneWidget,
    );
    expect(
      healthSemantics.properties.label,
      contains(
        '错误：timeout while fetching https://redacted@tech.example.com/private',
      ),
    );
    expect(healthSemantics.properties.label, isNot(contains('error-user')));
    expect(healthSemantics.properties.label, isNot(contains('error-pass')));
    expect(healthSemantics.properties.label, isNot(contains('error-key')));
    expect(
      healthSemantics.properties.label,
      isNot(contains('raw-error-token')),
    );
    expect(healthSemantics.properties.label, isNot(contains('raw-session')));

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains(
        'Reading scope: source page Tech [redacted] [redacted] https://redacted@tech.example.com/private (#2)',
      ),
    );
    expect(
      clipboard?.text,
      contains(
        'Source: Tech [redacted] [redacted] https://redacted@tech.example.com/private (#2)',
      ),
    );
    expect(clipboard?.text, contains('Source folder: Engineering [redacted]'));
    expect(
      clipboard?.text,
      contains(
        'Source issues: Tech [redacted] [redacted] https://redacted@tech.example.com/private (#2) · 抓取异常',
      ),
    );
    expect(clipboard?.text, isNot(contains('source-token')));
    expect(clipboard?.text, isNot(contains('sk-source')));
    expect(clipboard?.text, isNot(contains('source-user')));
    expect(clipboard?.text, isNot(contains('source-pass')));
    expect(clipboard?.text, isNot(contains('folder-secret')));
    expect(find.text('已复制诊断信息'), findsOneWidget);
  });

  testWidgets('mobile source page copies reader diagnostics with source scope', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      includeSecondSourceFeed: true,
      includeSourceCatalog: true,
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-page-copy-diagnostics')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      contains('Reading scope: source page Tech Radar (#2)'),
    );
    expect(clipboard?.text, contains('Section: 订阅源文章'));
    expect(clipboard?.text, contains('Source: Tech Radar (#2)'));
    expect(clipboard?.text, contains('Source health: 抓取异常'));
    expect(
      clipboard?.text,
      contains(
        'Source feed URL: https://redacted@tech.example.com/rss.xml?redacted=%5Bredacted%5D&topic=ai',
      ),
    );
    expect(
      clipboard?.text,
      contains('Source suggested action: 稍后重试；如果持续超时，检查源站是否可访问'),
    );
    expect(clipboard?.text, isNot(contains('token')));
    expect(clipboard?.text, isNot(contains('sk-')));
    expect(clipboard?.text, isNot(contains('source-user')));
    expect(clipboard?.text, isNot(contains('source-pass')));
    expect(find.text('已复制诊断信息'), findsOneWidget);
  });

  testWidgets('source page source actions copy Feed URL', (tester) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('复制 Feed URL').last);
    await _pumpRouteFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://example.com/feed.xml');
    expect(find.text('已复制 Example Daily 的 Feed URL'), findsOneWidget);
  });

  testWidgets('source page source actions can mark source read', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记此源已读'));
    await _pumpRouteFrame(tester);

    expect(find.text('标记订阅源已读'), findsOneWidget);
    expect(find.text('Example Daily 的 2 篇未读文章会标记为已读。'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, [1]);
    expect(find.text('已将 Example Daily 标记为已读'), findsOneWidget);
  });

  testWidgets('source page action feedback redacts sensitive source labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const sensitiveSourceName =
        'Example token=source-token sk-source123456 '
        'https://source-user:source-pass@example.com/private';
    const redactedSourceName =
        'Example [redacted] [redacted] '
        'https://redacted@example.com/private';

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    repository._snapshot = repository._snapshot.copyWith(
      sources: [
        for (final source in repository._snapshot.sources)
          source.id == 1 ? source.copyWith(name: sensitiveSourceName) : source,
      ],
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记此源已读'));
    await _pumpRouteFrame(tester);

    expect(find.text('$redactedSourceName 的 2 篇未读文章会标记为已读。'), findsOneWidget);
    expect(find.textContaining('source-token'), findsNothing);

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, [1]);
    expect(find.text('已将 $redactedSourceName 标记为已读'), findsOneWidget);
    expect(find.textContaining('sk-source123456'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除订阅源'));
    await _pumpRouteFrame(tester);

    expect(
      find.text('删除 $redactedSourceName 后，该源历史文章也会一并从本地清理。'),
      findsOneWidget,
    );
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('source-user:source-pass'), findsNothing);

    await tester.tap(find.text('取消'));
    await _pumpRouteFrame(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 1);
    expect(repository.updatedSources.last.enabled, isFalse);
    expect(find.text('已停用 $redactedSourceName'), findsOneWidget);
    expect(find.textContaining('source-user:source-pass'), findsNothing);
  });

  testWidgets('source page source actions queue cached reads while offline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..syncFailuresRemaining = 3;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);
    await controller.syncNow();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('标记此源已读'));
    await _pumpRouteFrame(tester);

    expect(
      find.text('离线时仅会将 Example Daily 已缓存的 2 篇未读文章加入待同步。'),
      findsOneWidget,
    );

    await tester.tap(find.text('确认'));
    await _pumpRouteFrame(tester);

    expect(repository.markSourceReadIds, isEmpty);
    expect(repository.markEntriesReadBatches, [
      [1, 2],
    ]);
    expect(find.text('已将 Example Daily 的 2 篇已缓存文章加入待同步'), findsOneWidget);
    expect(find.text('离线状态下无法批量标记已读'), findsNothing);
  });

  testWidgets('source page health banner explains source issues and retries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceAcceptedCount = 1;
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.byKey(const ValueKey<String>('source-page-health-banner')),
      findsOneWidget,
    );
    expect(find.text('抓取异常'), findsOneWidget);
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('4 未读'), findsOneWidget);
    expect(
      find.textContaining('错误：timeout while fetching feed'),
      findsOneWidget,
    );
    expect(find.textContaining('建议：稍后重试；如果持续超时，检查源站是否可访问'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('source-page-health-banner-semantics')),
    );
    expect(
      semantics.properties.label,
      allOf(
        contains('当前订阅源健康摘要，Tech Radar'),
        contains('文件夹 Engineering'),
        contains('4 篇未读'),
        contains('健康状态 抓取异常'),
        contains('自动抓取'),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-health-refresh')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('已请求刷新 1 个订阅源：Tech Radar'), findsOneWidget);
  });

  testWidgets('source page health refresh explains API failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss refresh failed: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-health-refresh')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('刷新失败：源站服务异常（HTTP 503），请稍后重试'), findsOneWidget);
    expect(find.text('操作失败：当前文章状态已变化，请刷新后重试'), findsNothing);
    expect(find.text('rss refresh failed: HTTP 503'), findsNothing);
  });

  testWidgets('source page action refresh explains timeout in source context', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..refreshSourceException = TimeoutException('slow source page refresh');
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('刷新此源').last);
    await _pumpRouteFrame(tester);

    expect(repository.refreshedSourceIds, [2]);
    expect(find.text('刷新此源请求超时，请稍后重试'), findsOneWidget);
    expect(find.text('刷新请求超时，请稍后重试。'), findsNothing);
  });

  testWidgets('source page health banner can enable paused source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(3);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('已停用'), findsOneWidget);
    expect(find.text('已停用自动抓取'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('source-page-health-enable')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-health-enable')),
    );
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 3);
    expect(repository.updatedSources.last.enabled, isTrue);
    expect(repository.refreshedSourceIds, [3]);
    expect(find.text('已启用 Design Weekly'), findsOneWidget);
  });

  testWidgets('source page source actions can pause automatic fetching', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.last.id, 1);
    expect(repository.updatedSources.last.enabled, isFalse);
    expect(repository.refreshedSourceIds, isEmpty);
    expect(find.text('已停用 Example Daily'), findsOneWidget);
  });

  testWidgets('source page source actions explain toggle update failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'rss source is unreachable: HTTP 503',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('停用自动抓取'));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources, isEmpty);
    expect(find.text('更新失败：源站服务异常（HTTP 503），请稍后重试'), findsOneWidget);
    expect(find.textContaining('rss source is unreachable'), findsNothing);
    expect(find.textContaining('刷新失败'), findsNothing);
  });

  testWidgets('source page source actions can edit source metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑订阅源'));
    await _pumpRouteFrame(tester);

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('编辑订阅源'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-name-field')),
      'Example Daily Plus',
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('source-edit-folder-suggestion-Engineering'),
      ),
    );
    await _pumpFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-rss-url-field')),
      'example.com/plus.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources.single.id, 1);
    expect(repository.updatedSources.single.name, 'Example Daily Plus');
    expect(repository.updatedSources.single.folder, 'Engineering');
    expect(repository.updatedSources.single.rssUrl, 'example.com/plus.xml');
    expect(find.text('已更新订阅源'), findsOneWidget);
    expect(controller.selectedSource?.name, 'Example Daily Plus');
  });

  testWidgets('source page source actions explain edit failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..updateSourceException = const ApiException(
        statusCode: 409,
        code: 'CONFLICT',
        message: 'feed already exists',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('编辑订阅源'));
    await _pumpRouteFrame(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('source-edit-rss-url-field')),
      'example.com/duplicate.xml',
    );
    await tester.tap(find.byKey(const ValueKey<String>('source-edit-submit')));
    await _pumpRouteFrame(tester);

    expect(repository.updatedSources, isEmpty);
    expect(find.text('更新失败：这个 Feed 已经在订阅列表里'), findsOneWidget);
    expect(find.text('feed already exists'), findsNothing);
  });

  testWidgets(
    'source page source actions can delete source and return to list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = await LocalStore.inMemory();
      final repository = _ShortcutRepository(store, includeSourceCatalog: true);
      final controller = AppController(repository: repository);
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.initialize();
      await controller.openSource(1);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await _pumpFrame(tester);

      expect(controller.state.section, AppSection.sourceEntries);

      await tester.tap(
        find.byKey(const ValueKey<String>('source-page-source-actions')),
      );
      await _pumpRouteFrame(tester);
      await tester.tap(find.text('删除订阅源'));
      await _pumpRouteFrame(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除订阅源'),
        ),
        findsOneWidget,
      );
      expect(find.text('删除 Example Daily 后，该源历史文章也会一并从本地清理。'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await _pumpRouteFrame(tester);

      expect(repository.deletedSourceIds, [1]);
      expect(controller.state.section, AppSection.sources);
      expect(controller.state.snapshot.sourceById(1), isNull);
      expect(find.byKey(const ValueKey<String>('source-card-1')), findsNothing);
      expect(find.text('已删除 Example Daily'), findsOneWidget);
    },
  );

  testWidgets('source page source actions explain delete failures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true)
      ..deleteSourceException = const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'feed source not found',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('删除订阅源'));
    await _pumpRouteFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpRouteFrame(tester);

    expect(repository.deletedSourceIds, isEmpty);
    expect(controller.state.section, AppSection.sourceEntries);
    expect(controller.state.snapshot.sourceById(1)?.name, 'Example Daily');
    expect(find.text('删除失败：订阅源已在服务端删除，请刷新同步本地列表'), findsOneWidget);
    expect(find.text('feed source not found'), findsNothing);
  });

  testWidgets('mobile source page source actions open site externally', (
    tester,
  ) async {
    final launcher = _installMockUrlLauncher();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store, includeSourceCatalog: true);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    await controller.openSource(1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('source-page-source-actions')),
    );
    await _pumpRouteFrame(tester);
    await tester.tap(find.text('打开站点').last);
    await _pumpRouteFrame(tester);

    final launchCall = launcher.launchCall;
    expect(launchCall, isNotNull);
    expect(launchCall!.method, 'launch');
    final arguments = Map<String, Object?>.from(launchCall.arguments as Map);
    expect(arguments['url'], 'https://example.com');
    expect(arguments['useWebView'], isFalse);
  });

  testWidgets('about pane copies diagnostics for support handoff', (
    tester,
  ) async {
    _installMockClipboard();
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.about);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('about-copy-diagnostics')),
    );
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('Section: 设置'));
    expect(clipboard?.text, contains('Sources:'));
    expect(clipboard?.text, contains('Unread: feed'));
    expect(find.text('已复制诊断信息'), findsOneWidget);
  });

  testWidgets('AI settings save success is visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-filter-prompt-field')),
      'Keep useful articles',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      'Summarize clearly',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-translation-prompt-field')),
      'Translate naturally',
    );
    final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await _pumpFrame(tester);

    expect(
      controller.state.snapshot.settings.ai.summaryPrompt,
      'Summarize clearly',
    );
    expect(find.text('AI 设置已保存'), findsOneWidget);
  });

  testWidgets('AI settings report server validation errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAiSettingsException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'provider is not supported',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-filter-prompt-field')),
      'Keep useful articles',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      'Summarize clearly',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-translation-prompt-field')),
      'Translate naturally',
    );
    final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.ai.summaryPrompt, isEmpty);
    expect(
      find.text('AI 设置保存失败：当前服务端不支持这个 AI Provider，请刷新后重试'),
      findsOneWidget,
    );
    expect(find.text('provider is not supported'), findsNothing);
  });

  testWidgets('AI settings redact sensitive server failure details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAiSettingsException = const ApiException(
        statusCode: 502,
        code: 'UPSTREAM_ERROR',
        message:
            'provider probe failed: Authorization: Bearer sk-secretvalue123456 Cookie: sid=abc123',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-filter-prompt-field')),
      'Keep useful articles',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      'Summarize clearly',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-translation-prompt-field')),
      'Translate naturally',
    );
    final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await _pumpFrame(tester);

    expect(
      find.text(
        'AI 设置保存失败：provider probe failed: Authorization: Bearer [redacted] Cookie: [redacted]',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('sk-secretvalue123456'), findsNothing);
    expect(find.textContaining('sid=abc123'), findsNothing);
  });

  testWidgets('AI settings explain expired sessions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAiSettingsException = const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'session expired',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-filter-prompt-field')),
      'Keep useful articles',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      'Summarize clearly',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-translation-prompt-field')),
      'Translate naturally',
    );
    final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.ai.summaryPrompt, isEmpty);
    expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.textContaining('session expired'), findsNothing);
  });

  testWidgets('AI settings explain network loss while saving', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAiSettingsException = const NetworkException(
        'offline ai settings',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-filter-prompt-field')),
      'Keep useful articles',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      'Summarize clearly',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-translation-prompt-field')),
      'Translate naturally',
    );
    final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
    await tester.scrollUntilVisible(
      saveButton,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);
    expect(controller.state.snapshot.settings.ai.summaryPrompt, isEmpty);
    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试保存 AI 设置'), findsOneWidget);
    expect(find.text('离线状态下不支持写操作'), findsNothing);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  testWidgets('appearance settings save server theme and local override', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('外观'));
    await _pumpFrame(tester);

    expect(find.text('外观'), findsWidgets);
    expect(find.text('当前：系统 · 服务端：系统'), findsOneWidget);

    final serverThemeControl = find.byKey(
      const ValueKey<String>('server-theme-mode-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: serverThemeControl, matching: find.text('深色')),
    );
    await _pumpFrame(tester);

    expect(
      controller.state.snapshot.settings.appearance.themeMode,
      AppThemeMode.dark,
    );
    expect(controller.state.session?.themeOverride, isNull);
    expect(controller.state.effectiveThemeMode, AppThemeMode.dark);
    expect(find.text('当前：深色 · 服务端：深色'), findsOneWidget);
    expect(find.text('外观设置已保存'), findsOneWidget);

    final localThemeControl = find.byKey(
      const ValueKey<String>('theme-override-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: localThemeControl, matching: find.text('浅色')),
    );
    await _pumpFrame(tester);

    expect(
      controller.state.snapshot.settings.appearance.themeMode,
      AppThemeMode.dark,
    );
    expect(controller.state.session?.themeOverride, AppThemeMode.light);
    expect(controller.state.effectiveThemeMode, AppThemeMode.light);
    expect((await repository.loadSession())?.themeOverride, AppThemeMode.light);
    expect(find.text('当前：浅色 · 服务端：深色'), findsOneWidget);

    await tester.tap(
      find.descendant(of: localThemeControl, matching: find.text('跟随')),
    );
    await _pumpFrame(tester);

    expect(controller.state.session?.themeOverride, isNull);
    expect(controller.state.effectiveThemeMode, AppThemeMode.dark);
    expect((await repository.loadSession())?.themeOverride, isNull);
    expect(find.text('当前：深色 · 服务端：深色'), findsOneWidget);
  });

  testWidgets('appearance settings report server validation errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAppearanceSettingsException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'themeMode must be SYSTEM, LIGHT, or DARK',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('外观'));
    await _pumpFrame(tester);

    final serverThemeControl = find.byKey(
      const ValueKey<String>('server-theme-mode-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: serverThemeControl, matching: find.text('深色')),
    );
    await _pumpFrame(tester);

    expect(
      controller.state.snapshot.settings.appearance.themeMode,
      AppThemeMode.system,
    );
    expect(find.text('外观设置保存失败：服务端不支持这个主题值，请刷新后重试'), findsOneWidget);
    expect(find.text('themeMode must be SYSTEM, LIGHT, or DARK'), findsNothing);
  });

  testWidgets('appearance settings explain save timeouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateAppearanceSettingsException = TimeoutException(
        'slow appearance settings',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.text('外观'));
    await _pumpFrame(tester);

    final serverThemeControl = find.byKey(
      const ValueKey<String>('server-theme-mode-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: serverThemeControl, matching: find.text('深色')),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);
    expect(
      controller.state.snapshot.settings.appearance.themeMode,
      AppThemeMode.system,
    );
    expect(find.text('外观设置保存请求超时，请稍后重试'), findsOneWidget);
  });

  testWidgets('feeds settings save default language for all devices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.feeds);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('当前默认语言：zh-CN'), findsOneWidget);

    final languageControl = find.byKey(
      const ValueKey<String>('feed-default-language-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: languageControl, matching: find.text('English')),
    );
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.feeds.defaultLanguage, 'en-US');
    expect(controller.state.snapshot.settings.ai.outputLanguage, 'en-US');
    expect(find.text('当前默认语言：en-US'), findsOneWidget);
    expect(find.text('默认语言已保存'), findsOneWidget);
  });

  testWidgets('feeds settings support custom language tags', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      initialDefaultLanguage: 'fr-FR',
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.feeds);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(find.text('fr-FR'), findsWidgets);
    expect(find.text('当前默认语言：fr-FR'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('feed-custom-language-field')),
      'de-DE',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('feed-custom-language-save')),
    );
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.feeds.defaultLanguage, 'de-DE');
    expect(controller.state.snapshot.settings.ai.outputLanguage, 'de-DE');
    expect(find.text('当前默认语言：de-DE'), findsOneWidget);
    expect(find.text('默认语言已保存'), findsOneWidget);
  });

  testWidgets('feeds settings validate custom language before saving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.feeds);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('feed-custom-language-field')),
      'not a language',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('feed-custom-language-save')),
    );
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.feeds.defaultLanguage, 'zh-CN');
    expect(repository.feedSettingsUpdates, isEmpty);
    expect(find.text('默认语言 必须是 BCP 47 标签，例如 zh-CN'), findsOneWidget);
  });

  testWidgets('feeds settings report server validation errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateFeedSettingsException = const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'defaultLanguage is temporarily disabled',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.feeds);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('feed-custom-language-field')),
      'de-DE',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('feed-custom-language-save')),
    );
    await _pumpFrame(tester);

    expect(controller.state.snapshot.settings.feeds.defaultLanguage, 'zh-CN');
    expect(find.text('默认语言保存失败：服务端暂时无法接受这个语言，请稍后重试'), findsOneWidget);
    expect(find.text('defaultLanguage is temporarily disabled'), findsNothing);
  });

  testWidgets('feeds settings explain network loss while saving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store)
      ..updateFeedSettingsException = const NetworkException(
        'offline feed settings',
      );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.settings);
    controller.changeSettingsSection(SettingsSection.feeds);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    final languageControl = find.byKey(
      const ValueKey<String>('feed-default-language-segmented-button'),
    );
    await tester.tap(
      find.descendant(of: languageControl, matching: find.text('English')),
    );
    await _pumpFrame(tester);

    expect(controller.state.isOnline, isFalse);
    expect(controller.state.snapshot.settings.feeds.defaultLanguage, 'zh-CN');
    expect(find.text('当前网络不可用，已切换为离线阅读模式，可稍后重试保存默认语言'), findsOneWidget);
    expect(find.text('离线状态下不支持写操作'), findsNothing);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  testWidgets('account logout requires confirmation', (tester) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(store);
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.account);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    await tester.tap(find.byTooltip('复制服务端地址'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, 'https://reader.example');
    expect(find.text('已复制服务端地址'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(repository.logoutRequests, 0);
    expect(controller.state.session, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '退出登录'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.logoutRequests, 1);
    expect(controller.state.session, isNull);
  });

  testWidgets('account server address display and copy redact sensitive URL parts', (
    tester,
  ) async {
    _installMockClipboard();

    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await LocalStore.inMemory();
    final repository = _ShortcutRepository(
      store,
      sessionBaseUrl:
          'https://user:secret@reader.example/app?api_key=server-secret&view=account',
    );
    final controller = AppController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await store.close();
    });
    await controller.initialize();
    controller.selectSection(AppSection.account);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrame(tester);

    expect(
      find.text(
        'https://redacted@reader.example/app?redacted=%5Bredacted%5D&view=account',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('user:secret'), findsNothing);
    expect(find.textContaining('server-secret'), findsNothing);

    await tester.tap(find.byTooltip('复制服务端地址'));
    await _pumpFrame(tester);

    final clipboard = await Clipboard.getData('text/plain');
    expect(
      clipboard?.text,
      'https://redacted@reader.example/app?redacted=%5Bredacted%5D&view=account',
    );
    expect(clipboard?.text, isNot(contains('user:secret')));
    expect(clipboard?.text, isNot(contains('server-secret')));
    expect(find.text('已复制服务端地址'), findsOneWidget);
  });
}

_MockClipboard _installMockClipboard() {
  final clipboard = _MockClipboard();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        switch (methodCall.method) {
          case 'Clipboard.setData':
            final arguments = Map<String, dynamic>.from(
              methodCall.arguments as Map,
            );
            clipboard.text = arguments['text'] as String?;
            return null;
          case 'Clipboard.getData':
            if (clipboard.text == null) {
              return null;
            }
            return {'text': clipboard.text};
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  return clipboard;
}

_MockUrlLauncher _installMockUrlLauncher() {
  final launcher = _MockUrlLauncher();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_urlLauncherChannel, (methodCall) async {
        launcher.launchCall = methodCall;
        return true;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, null);
  });
  return launcher;
}

class _MockClipboard {
  String? text;
}

class _MockUrlLauncher {
  MethodCall? launchCall;
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpRouteFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Finder _badgeText(String key, String text) {
  return find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.text(text),
  );
}

class _ShortcutRepository extends RssRepository {
  _ShortcutRepository(
    LocalStore store, {
    this.pendingSyncCount = 0,
    this.pendingSyncDescription = '',
    this.lastServerTime,
    ReaderPreferences? readerPreferences,
    bool includeSecondaryUnread = false,
    bool includeOlderFeedUnread = false,
    bool includeReadBetweenUnread = false,
    bool includeSecondSourceFeed = false,
    bool includeInProgressFeed = false,
    bool includeSourceCatalog = false,
    bool includeDisabledEngineeringSource = false,
    bool includePagedFeed = false,
    bool includeFailedAiEntry = false,
    bool includeTranslatedEntry = false,
    bool includeArticleBody = false,
    bool includeCoverImage = false,
    bool includeInitialEntries = true,
    String initialDefaultLanguage = 'zh-CN',
    String? sessionBaseUrl,
    this.syncCompleter,
    this.syncCompleterAttempt = 1,
    this.exportOpmlCompleter,
    this.importOpmlImportedCount = 2,
    this.importOpmlSkippedCount = 1,
    this.loadMoreException,
  }) : super(store: store) {
    _readerPreferences =
        readerPreferences ?? ReaderPreferences.defaultPreferences;
    _sessionData = _session.copyWith(
      baseUrl: sessionBaseUrl,
      lastServerTime: lastServerTime,
    );
    _snapshot = _initialSnapshot(
      includeSecondaryUnread: includeSecondaryUnread,
      includeOlderFeedUnread: includeOlderFeedUnread,
      includeReadBetweenUnread: includeReadBetweenUnread,
      includeSecondSourceFeed: includeSecondSourceFeed,
      includeInProgressFeed: includeInProgressFeed,
      includeSourceCatalog: includeSourceCatalog,
      includeDisabledEngineeringSource: includeDisabledEngineeringSource,
      includePagedFeed: includePagedFeed,
      includeFailedAiEntry: includeFailedAiEntry,
      includeTranslatedEntry: includeTranslatedEntry,
      includeArticleBody: includeArticleBody,
      includeCoverImage: includeCoverImage,
      includeInitialEntries: includeInitialEntries,
      initialDefaultLanguage: initialDefaultLanguage,
    );
  }

  final List<int> openedEntryIds = <int>[];
  final List<int> markReadEntryIds = <int>[];
  final List<int> markUnreadEntryIds = <int>[];
  final List<List<int>> markEntriesReadBatches = <List<int>>[];
  final List<String> queuedReadStates = <String>[];
  final List<int> markSourceReadIds = <int>[];
  final List<String> markFolderReadFolders = <String>[];
  final List<int> refreshedSourceIds = <int>[];
  final List<int> deletedSourceIds = <int>[];
  final List<String> savedEntryUpdates = <String>[];
  final List<String> queuedSavedStates = <String>[];
  final List<String> noiseEntryUpdates = <String>[];
  final List<String> queuedNoiseStates = <String>[];
  final List<int> reprocessedEntryIds = <int>[];
  final List<ListKey> loadedListKeys = <ListKey>[];
  final List<ListKey> loadedMoreListKeys = <ListKey>[];
  final List<({String rssUrl, String? folder})> addedSourceRequests =
      <({String rssUrl, String? folder})>[];
  final List<FeedSource> updatedSources = <FeedSource>[];
  final List<({String opml, bool refreshAfterImport})> importedOpmlRequests =
      <({String opml, bool refreshAfterImport})>[];
  final List<String> feedSettingsUpdates = <String>[];
  int refreshAllRequests = 0;
  int logoutRequests = 0;
  final int pendingSyncCount;
  final String pendingSyncDescription;
  final DateTime? lastServerTime;
  final Completer<void>? syncCompleter;
  final int syncCompleterAttempt;
  Object? syncException;
  Object? addSourceException;
  Object? updateSourceException;
  Object? deleteSourceException;
  Object? refreshAllException;
  Object? refreshSourceException;
  Object? refreshSourcesException;
  Object? markSourceReadException;
  Object? markFolderReadException;
  String? fetchedEntryContentHtml;
  int? refreshAllAcceptedCount;
  int? refreshAllSkippedCount;
  int? refreshSourceAcceptedCount;
  int? refreshSourceSkippedCount;
  int? refreshSourcesAcceptedCount;
  int? refreshSourcesSkippedCount;
  final Object? loadMoreException;
  Object? exportOpmlException;
  final Completer<String>? exportOpmlCompleter;
  final int importOpmlImportedCount;
  final int importOpmlSkippedCount;
  int? importOpmlRefreshAcceptedCount;
  Object? importOpmlException;
  Object? importOpmlSyncExceptionCause;
  Object? updateAppearanceSettingsException;
  Object? updateAiSettingsException;
  Object? updateFeedSettingsException;
  Object? reprocessEntryAiException;
  int syncAttempts = 0;
  int syncFailuresRemaining = 0;
  int reprocessFailuresRemaining = 0;

  static const _session = SessionData(
    baseUrl: 'https://reader.example',
    token: 'token',
    user: AuthUser(
      id: 1,
      email: 'demo@rsscopilot.local',
      displayName: 'RSS Copilot Demo',
    ),
    lastServerTime: null,
    themeOverride: null,
  );

  late AppSnapshot _snapshot;
  late ReaderPreferences _readerPreferences;
  late SessionData _sessionData;

  @override
  Future<SessionData?> loadSession() async => _sessionData;

  @override
  Future<void> setThemeOverride(AppThemeMode? mode) async {
    _sessionData = _sessionData.copyWith(
      themeOverride: mode,
      clearThemeOverride: mode == null,
    );
  }

  @override
  Future<SettingsBundle> updateAppearanceSettings(
    AppThemeMode themeMode,
  ) async {
    final exception = updateAppearanceSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextSettings = _snapshot.settings.copyWith(
      appearance: AppearanceSettings(themeMode: themeMode),
    );
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<SettingsBundle> updateAiSettings({
    required AiSettings current,
    String? rawApiKey,
    bool clearApiKey = false,
  }) async {
    final exception = updateAiSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextAi = current.copyWith(
      configured: rawApiKey != null && rawApiKey.isNotEmpty
          ? true
          : current.configured && !clearApiKey,
      clearApiKeyMasked: clearApiKey,
    );
    final nextSettings = _snapshot.settings.copyWith(ai: nextAi);
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<SettingsBundle> updateFeedSettings(String defaultLanguage) async {
    feedSettingsUpdates.add(defaultLanguage);
    final exception = updateFeedSettingsException;
    if (exception != null) {
      throw exception;
    }
    final nextFeeds = _snapshot.settings.feeds.copyWith(
      defaultLanguage: defaultLanguage,
    );
    final nextSettings = _snapshot.settings.copyWith(
      feeds: nextFeeds,
      ai: _snapshot.settings.ai.copyWith(outputLanguage: defaultLanguage),
    );
    _snapshot = _snapshot.copyWith(settings: nextSettings);
    return nextSettings;
  }

  @override
  Future<AppSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<void> verifySession() async {}

  @override
  Future<void> logout() async {
    logoutRequests += 1;
  }

  @override
  Future<void> sync() async {
    syncAttempts += 1;
    final completer = syncCompleter;
    if (completer != null && syncAttempts == syncCompleterAttempt) {
      await completer.future;
    }
    final exception = syncException;
    if (exception != null) {
      throw exception;
    }
    if (syncFailuresRemaining > 0) {
      syncFailuresRemaining -= 1;
      throw const NetworkException('offline');
    }
  }

  @override
  Future<void> loadSearchEntries(ListKey key) async {
    loadedListKeys.add(key);
  }

  @override
  Future<void> loadMoreEntries(ListKey key) async {
    loadedMoreListKeys.add(key);
    final exception = loadMoreException;
    if (exception != null) {
      if (exception is ApiException &&
          exception.isBadRequest &&
          exception.message == 'invalid pagination cursor') {
        _snapshot = _snapshot.copyWith(
          listHasMore: {..._snapshot.listHasMore, key.value: false},
          listCursors: {..._snapshot.listCursors}..remove(key.value),
        );
      }
      throw exception;
    }
    final nextEntry = _entry(
      9,
      'Next Page',
      isRead: false,
      publishedAt: DateTime.utc(2026, 4, 9, 8),
    );
    _snapshot = _snapshot.copyWith(
      entries: {..._snapshot.entries, nextEntry.id: nextEntry},
      listSnapshots: {
        ..._snapshot.listSnapshots,
        key.value: [..._snapshot.listIds(key), nextEntry.id],
      },
      listHasMore: {..._snapshot.listHasMore, key.value: false},
    );
  }

  @override
  Future<void> loadSourceEntries(int sourceId) async {
    loadedListKeys.add(ListKey.source(sourceId));
  }

  @override
  Future<ReaderPreferences> loadReaderPreferences() async {
    return _readerPreferences;
  }

  @override
  Future<void> saveReaderPreferences(ReaderPreferences preferences) async {
    _readerPreferences = preferences;
  }

  @override
  Future<int> pendingEntryActionCount() async => pendingSyncCount;

  @override
  Future<({int count, String description})> pendingEntryActionStatus() async {
    return (count: pendingSyncCount, description: pendingSyncDescription);
  }

  @override
  Future<EntryRecord?> fetchEntryDetail(
    int entryId, {
    bool markRead = false,
  }) async {
    openedEntryIds.add(entryId);
    final nextContentHtml = fetchedEntryContentHtml;
    if (nextContentHtml != null) {
      _updateEntry(
        entryId,
        (entry) => entry.copyWith(contentHtml: nextContentHtml),
      );
    }
    if (markRead) {
      _updateEntry(entryId, (entry) => entry.copyWith(isRead: true));
    }
    return _snapshot.entries[entryId];
  }

  @override
  Future<void> markRead(int entryId) async {
    markReadEntryIds.add(entryId);
    _updateEntry(entryId, (entry) => entry.copyWith(isRead: true));
  }

  @override
  Future<void> markEntriesRead(List<int> entryIds) async {
    markEntriesReadBatches.add(entryIds);
    for (final entryId in entryIds) {
      _updateEntry(
        entryId,
        (entry) => entry.copyWith(isRead: true, readingProgress: 1),
      );
    }
  }

  @override
  Future<void> queueEntriesRead(List<int> entryIds) async {
    await markEntriesRead(entryIds);
  }

  @override
  Future<void> queueReadState(int entryId, bool isRead) async {
    queuedReadStates.add('$entryId:$isRead');
    _updateEntry(entryId, (entry) => entry.copyWith(isRead: isRead));
  }

  @override
  Future<void> markUnread(int entryId) async {
    markUnreadEntryIds.add(entryId);
    _updateEntry(entryId, (entry) => entry.copyWith(isRead: false));
  }

  @override
  Future<void> markSourceRead(int sourceId) async {
    markSourceReadIds.add(sourceId);
    final exception = markSourceReadException;
    if (exception != null) {
      throw exception;
    }
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          source.id == sourceId ? source.copyWith(unreadCount: 0) : source,
      ],
    );
  }

  @override
  Future<void> markFolderRead(String folder) async {
    markFolderReadFolders.add(folder);
    final exception = markFolderReadException;
    if (exception != null) {
      throw exception;
    }
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          source.folder == folder ? source.copyWith(unreadCount: 0) : source,
      ],
    );
  }

  @override
  Future<RefreshAcceptedResult> refreshAllAndPoll() async {
    refreshAllRequests += 1;
    final exception = refreshAllException;
    if (exception != null) {
      throw exception;
    }
    final acceptedCount = refreshAllAcceptedCount ?? 1;
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: acceptedCount,
      requestedCount: acceptedCount + (refreshAllSkippedCount ?? 0),
      skippedCount: refreshAllSkippedCount ?? 0,
    );
  }

  @override
  Future<RefreshAcceptedResult> refreshSourceAndPoll(int sourceId) async {
    refreshedSourceIds.add(sourceId);
    final exception = refreshSourceException;
    if (exception != null) {
      throw exception;
    }
    final acceptedCount = refreshSourceAcceptedCount ?? 1;
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: acceptedCount,
      requestedCount: 1,
      skippedCount: refreshSourceSkippedCount ?? 0,
    );
  }

  @override
  Future<RefreshAcceptedResult> refreshSourcesAndPoll(
    Iterable<int> sourceIds,
  ) async {
    final ids = sourceIds.toList(growable: false);
    refreshedSourceIds.addAll(ids);
    final exception = refreshSourcesException;
    if (exception != null) {
      throw exception;
    }
    final acceptedCount = refreshSourcesAcceptedCount ?? ids.length;
    final skippedCount =
        refreshSourcesSkippedCount ??
        (ids.length > acceptedCount ? ids.length - acceptedCount : 0);
    return RefreshAcceptedResult(
      accepted: true,
      acceptedCount: acceptedCount,
      requestedCount: ids.length,
      skippedCount: skippedCount,
    );
  }

  @override
  Future<FeedSource> addSource(String rssUrl, {String? folder}) async {
    final exception = addSourceException;
    if (exception != null) {
      throw exception;
    }
    addedSourceRequests.add((rssUrl: rssUrl, folder: folder));
    final source = FeedSource(
      id: 99,
      name: 'New Source',
      folder: folder ?? defaultSourceFolder,
      rssUrl: rssUrl,
      siteUrl: null,
      iconUrl: null,
      enabled: true,
      lastFetchedAt: null,
      hasError: false,
      unreadCount: 0,
    );
    _snapshot = _snapshot.copyWith(sources: [..._snapshot.sources, source]);
    return source;
  }

  @override
  Future<FeedSource> updateSource(FeedSource source) async {
    final exception = updateSourceException;
    if (exception != null) {
      throw exception;
    }
    updatedSources.add(source);
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final existing in _snapshot.sources)
          existing.id == source.id ? source : existing,
      ],
    );
    return source;
  }

  @override
  Future<void> deleteSource(int sourceId) async {
    final exception = deleteSourceException;
    if (exception != null) {
      throw exception;
    }
    deletedSourceIds.add(sourceId);
    _snapshot = _snapshot.copyWith(
      sources: [
        for (final source in _snapshot.sources)
          if (source.id != sourceId) source,
      ],
    );
  }

  @override
  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    final exception = importOpmlException;
    if (exception != null) {
      throw exception;
    }
    importedOpmlRequests.add((
      opml: opml,
      refreshAfterImport: refreshAfterImport,
    ));
    if (importOpmlImportedCount > 0) {
      final importedSource = FeedSource(
        id: 88,
        name: 'Imported OPML',
        folder: 'Imported',
        rssUrl: 'https://imported.example/rss',
        siteUrl: null,
        iconUrl: null,
        enabled: true,
        lastFetchedAt: null,
        hasError: false,
        unreadCount: 0,
      );
      _snapshot = _snapshot.copyWith(
        sources: [
          ..._snapshot.sources.where(
            (source) => source.id != importedSource.id,
          ),
          importedSource,
        ],
      );
    }
    final result = OpmlImportResult(
      importedCount: importOpmlImportedCount,
      skippedCount: importOpmlSkippedCount,
      refreshAcceptedCount:
          importOpmlRefreshAcceptedCount ??
          (refreshAfterImport ? importOpmlImportedCount : 0),
      sources: _snapshot.sources,
    );
    final cause = importOpmlSyncExceptionCause;
    if (cause != null) {
      throw OpmlImportSyncException(result: result, cause: cause);
    }
    return result;
  }

  @override
  Future<String> exportOpml() async {
    final completer = exportOpmlCompleter;
    if (completer != null) {
      return completer.future;
    }
    final exception = exportOpmlException;
    if (exception != null) {
      throw exception;
    }
    return '<opml version="2.0"><body></body></opml>';
  }

  @override
  Future<void> setSaved(int entryId, bool isSaved) async {
    savedEntryUpdates.add('$entryId:$isSaved');
    _setSavedState(entryId, isSaved);
  }

  @override
  Future<void> queueSavedState(int entryId, bool isSaved) async {
    queuedSavedStates.add('$entryId:$isSaved');
    _setSavedState(entryId, isSaved);
  }

  void _setSavedState(int entryId, bool isSaved) {
    _updateEntry(entryId, (entry) => entry.copyWith(isSaved: isSaved));
    final currentIds = _snapshot.listIds(ListKey.saved).toList(growable: true)
      ..remove(entryId);
    if (isSaved) {
      currentIds.add(entryId);
    }
    _snapshot = _snapshot.copyWith(
      listSnapshots: {
        ..._snapshot.listSnapshots,
        ListKey.saved.value: currentIds,
      },
    );
  }

  @override
  Future<void> setEntryNoise(int entryId, bool isNoise) async {
    noiseEntryUpdates.add('$entryId:$isNoise');
    _setEntryNoiseState(entryId, isNoise);
  }

  @override
  Future<void> queueNoiseState(int entryId, bool isNoise) async {
    queuedNoiseStates.add('$entryId:$isNoise');
    _setEntryNoiseState(entryId, isNoise);
  }

  void _setEntryNoiseState(int entryId, bool isNoise) {
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final nextEntry = isNoise
        ? entry.copyWith(isNoise: true, filterReason: '手动移入噪音箱')
        : entry.copyWith(isNoise: false, clearFilterReason: true);
    final fromKey = isNoise ? ListKey.feed : ListKey.noise;
    final toKey = isNoise ? ListKey.noise : ListKey.feed;
    final fromIds = _snapshot.listIds(fromKey).where((id) => id != entryId);
    final toIds = _sortedEntryIds([..._snapshot.listIds(toKey), entryId]);
    _snapshot = _snapshot.copyWith(
      entries: {..._snapshot.entries, entryId: nextEntry},
      listSnapshots: {
        ..._snapshot.listSnapshots,
        fromKey.value: fromIds.toList(growable: false),
        toKey.value: toIds,
      },
    );
  }

  @override
  Future<void> reprocessEntryAi(int entryId) async {
    final exception = reprocessEntryAiException;
    if (exception != null) {
      throw exception;
    }
    if (reprocessFailuresRemaining > 0) {
      reprocessFailuresRemaining -= 1;
      throw const NetworkException('offline');
    }
    reprocessedEntryIds.add(entryId);
    _updateEntry(
      entryId,
      (entry) => entry.copyWith(
        filterStatus: 'PENDING',
        summaryStatus: 'PENDING',
        translationStatus: 'PENDING',
      ),
    );
  }

  void _updateEntry(int entryId, EntryRecord Function(EntryRecord) update) {
    final entry = _snapshot.entries[entryId];
    if (entry == null) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      entries: {..._snapshot.entries, entryId: update(entry)},
    );
  }

  List<int> _sortedEntryIds(List<int> entryIds) {
    final uniqueIds = <int>{};
    final entries = <EntryRecord>[];
    for (final entryId in entryIds) {
      if (!uniqueIds.add(entryId)) {
        continue;
      }
      final entry = _snapshot.entries[entryId];
      if (entry != null) {
        entries.add(entry);
      }
    }
    entries.sort((left, right) {
      final publishedCompare = right.publishedAt.compareTo(left.publishedAt);
      if (publishedCompare != 0) {
        return publishedCompare;
      }
      return right.id.compareTo(left.id);
    });
    return entries.map((entry) => entry.id).toList(growable: false);
  }

  static EntryRecord _entry(
    int id,
    String title, {
    required bool isRead,
    DateTime? publishedAt,
    int sourceId = 1,
    String sourceName = 'Example',
    String? author,
    double readingProgress = 0,
    String? summary,
    String? filterStatus,
    String? summaryStatus,
    String? translationStatus,
    String? coverImageUrl,
    String? contentHtml,
    List<TranslationSegment> translationSegments = const [],
  }) {
    return EntryRecord(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      author: author,
      title: title,
      link: 'https://example.com/$id',
      publishedAt: publishedAt ?? DateTime.utc(2026, 4, 10, 10 - id),
      summary: summary ?? 'Summary $id',
      isRead: isRead,
      readingProgress: readingProgress,
      foreign: false,
      filterStatus: filterStatus,
      summaryStatus: summaryStatus,
      translationStatus: translationStatus,
      coverImageUrl: coverImageUrl,
      contentHtml: contentHtml,
      filterReason: null,
      translationSegments: translationSegments,
    );
  }

  static AppSnapshot _initialSnapshot({
    required bool includeSecondaryUnread,
    required bool includeOlderFeedUnread,
    required bool includeReadBetweenUnread,
    required bool includeSecondSourceFeed,
    required bool includeInProgressFeed,
    required bool includeSourceCatalog,
    required bool includeDisabledEngineeringSource,
    required bool includePagedFeed,
    required bool includeFailedAiEntry,
    required bool includeTranslatedEntry,
    required bool includeArticleBody,
    required bool includeCoverImage,
    required bool includeInitialEntries,
    required String initialDefaultLanguage,
  }) {
    final entries = <int, EntryRecord>{};
    final listSnapshots = <String, List<int>>{
      ListKey.feed.value: [],
      ListKey.noise.value: [],
      ListKey.saved.value: [],
    };

    if (includeInitialEntries) {
      entries[1] = _entry(
        1,
        'First',
        isRead: false,
        summaryStatus: includeFailedAiEntry ? 'FAILED' : null,
        coverImageUrl: includeCoverImage
            ? 'https://images.example.com/first.jpg'
            : null,
        contentHtml: includeArticleBody
            ? '<h2>Body title</h2><p>Readable <strong>article</strong> body.</p>'
            : null,
        translationSegments: includeTranslatedEntry
            ? const [
                TranslationSegment(
                  source: 'Hello world.',
                  translation: '你好，世界。',
                ),
                TranslationSegment(
                  source: 'Second paragraph.',
                  translation: '第二段。',
                ),
              ]
            : const [],
      );
      entries[2] = _entry(2, 'Second', isRead: false);
      listSnapshots[ListKey.feed.value] = [1, 2];
    }

    if (includeSecondaryUnread) {
      entries[3] = _entry(3, 'Saved Only', isRead: false);
      entries[4] = _entry(4, 'Noise Only', isRead: false);
      listSnapshots[ListKey.saved.value] = [3];
      listSnapshots[ListKey.noise.value] = [4];
    }

    if (includeOlderFeedUnread) {
      entries[5] = _entry(
        5,
        'Older',
        isRead: false,
        summary: List.filled(440, 'word').join(' '),
        publishedAt: DateTime.utc(2026, 4, 9, 9),
      );
      listSnapshots[ListKey.feed.value] = [1, 2, 5];
    }

    if (includeReadBetweenUnread) {
      entries[2] = _entry(2, 'Second', isRead: true);
    }

    if (includeSecondSourceFeed) {
      entries[6] = _entry(
        6,
        'Tech Unread',
        isRead: false,
        publishedAt: DateTime.utc(2026, 4, 10, 7),
        sourceId: 2,
        sourceName: 'Tech',
      );
      entries[7] = _entry(
        7,
        'Tech Read',
        isRead: true,
        publishedAt: DateTime.utc(2026, 4, 10, 6),
        sourceId: 2,
        sourceName: 'Tech',
      );
      listSnapshots[ListKey.feed.value] = [1, 6, 2, 7];
    }

    if (includeInProgressFeed) {
      entries[8] = _entry(
        8,
        'Half Read',
        isRead: false,
        author: 'Reader Bot',
        readingProgress: 0.42,
        publishedAt: DateTime.utc(2026, 4, 10, 8, 30),
      );
      listSnapshots[ListKey.feed.value] = [1, 8, 2];
    }

    final listHasMore = <String, bool>{
      if (includePagedFeed) ListKey.feed.value: true,
    };

    return AppSnapshot(
      sources: includeSourceCatalog
          ? _sourceCatalog(
              includeDisabledEngineeringSource:
                  includeDisabledEngineeringSource,
            )
          : const [],
      settings: _settings(defaultLanguage: initialDefaultLanguage),
      entries: entries,
      listSnapshots: listSnapshots,
      listHasMore: listHasMore,
      listCursors: const {},
    );
  }

  static SettingsBundle _settings({required String defaultLanguage}) {
    const settings = SettingsBundle.empty();
    return settings.copyWith(
      feeds: settings.feeds.copyWith(defaultLanguage: defaultLanguage),
      ai: settings.ai.copyWith(outputLanguage: defaultLanguage),
    );
  }

  static List<FeedSource> _sourceCatalog({
    bool includeDisabledEngineeringSource = false,
  }) {
    final now = DateTime.now().toUtc();
    return [
      FeedSource(
        id: 1,
        name: 'Example Daily',
        folder: 'Newsletters',
        rssUrl: 'https://example.com/feed.xml',
        siteUrl: 'https://example.com',
        iconUrl: 'https://example.com/favicon.ico',
        enabled: true,
        lastFetchedAt: now.subtract(const Duration(hours: 2)),
        hasError: false,
        unreadCount: 2,
      ),
      FeedSource(
        id: 2,
        name: 'Tech Radar',
        folder: 'Engineering',
        rssUrl:
            'https://source-user:source-pass@tech.example.com/rss.xml?x-api-key=source-token&topic=ai',
        siteUrl:
            'https://site-user:site-pass@tech.example.com?api_key=site-key&view=home',
        iconUrl: 'https://tech.example.com/favicon.ico',
        enabled: true,
        lastFetchedAt: now.subtract(const Duration(hours: 1)),
        hasError: true,
        lastErrorAt: now.subtract(const Duration(minutes: 30)),
        lastErrorMessage:
            'timeout while fetching feed https://error-user:error-pass@tech.example.com/private token=raw-token Authorization: Bearer header.jwt X-API-Key: header-key password: header-pass Bearer abc.def Basic YmFzaWMtc2VjcmV0 Cookie: session=raw-session; theme=dark\nSet-Cookie: refresh=raw-refresh; Path=/ sk-abc123456789',
        unreadCount: 4,
      ),
      FeedSource(
        id: 3,
        name: 'Design Weekly',
        folder: 'Design',
        rssUrl: 'https://weekly.example.com/rss.xml',
        siteUrl: 'https://weekly.example.com',
        iconUrl: null,
        enabled: false,
        lastFetchedAt: now.subtract(const Duration(hours: 3)),
        hasError: false,
        unreadCount: 0,
      ),
      FeedSource(
        id: 4,
        name: 'Archive Planet',
        folder: 'Archive',
        rssUrl: 'https://archive.example.com/rss.xml',
        siteUrl: 'https://archive.example.com',
        iconUrl: null,
        enabled: true,
        lastFetchedAt: now.subtract(const Duration(days: 3)),
        hasError: false,
        unreadCount: 0,
      ),
      if (includeDisabledEngineeringSource)
        FeedSource(
          id: 5,
          name: 'Paused Engineering',
          folder: 'Engineering',
          rssUrl: 'https://paused.example.com/rss.xml',
          siteUrl: 'https://paused.example.com',
          iconUrl: null,
          enabled: false,
          lastFetchedAt: now.subtract(const Duration(days: 7)),
          hasError: false,
          unreadCount: 0,
        ),
    ];
  }
}
