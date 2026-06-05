import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/models/entry_record.dart';
import 'package:rss_copilot_client/src/models/reader_preferences.dart';
import 'package:rss_copilot_client/src/ui/home/widgets/article_detail_view.dart';

void main() {
  testWidgets('shows saved reading progress in the article header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              readingProgress: 0.42,
              summaryStatus: 'PENDING',
              contentHtml: '<p>${List.filled(440, 'word').join(' ')}</p>',
            ),
            sourceIconUrl: 'https://example.com/favicon.ico',
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('读到 42%'), findsOneWidget);
    expect(find.text('2 分钟'), findsOneWidget);
    expect(find.text('剩余 2 分钟'), findsOneWidget);
    expect(find.text('Jane Analyst'), findsOneWidget);
    expect(find.text('AI 处理中'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('article-source-icon-image')),
      findsOneWidget,
    );

    final detailSummarySemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('article-detail-summary-semantics')),
    );
    expect(
      detailSummarySemantics.properties.label,
      '正在阅读，Long read，来源 Example，作者 Jane Analyst，1/1 · 1 未读，未读，阅读进度 42%，剩余 2 分钟，发布时间 2026-05-24 18:00',
    );
    expect(detailSummarySemantics.properties.header, isTrue);

    final progressBar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressBar.semanticsLabel, '阅读进度，剩余 2 分钟');
    expect(progressBar.semanticsValue, '42');
  });

  testWidgets('redacts sensitive source name in header and semantics', (
    tester,
  ) async {
    const sensitiveSourceName =
        'Tech token=source-token sk-source123456 '
        'https://source-user:source-pass@tech.example.com/private';
    const redactedSourceName =
        'Tech [redacted] [redacted] '
        'https://redacted@tech.example.com/private';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(sourceName: sensitiveSourceName),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text(redactedSourceName), findsOneWidget);
    expect(find.textContaining('source-token'), findsNothing);
    expect(find.textContaining('sk-source123456'), findsNothing);
    expect(find.textContaining('source-user:source-pass'), findsNothing);

    final detailSummarySemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('article-detail-summary-semantics')),
    );
    expect(
      detailSummarySemantics.properties.label,
      contains('来源 $redactedSourceName'),
    );
    expect(
      detailSummarySemantics.properties.label,
      isNot(contains('source-token')),
    );
    expect(
      detailSummarySemantics.properties.label,
      isNot(contains('source-user:source-pass')),
    );
  });

  testWidgets('restart reading action resets progress from the detail header', (
    tester,
  ) async {
    final reportedProgress = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              readingProgress: 0.42,
              contentHtml: _longContentHtml(),
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: reportedProgress.add,
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('从头读'), findsOneWidget);

    final restartButton = find.byKey(
      const ValueKey<String>('article-detail-restart-reading'),
    );
    await tester.ensureVisible(restartButton);
    await tester.pump();
    reportedProgress.clear();
    await tester.tap(restartButton);
    await tester.pump();

    expect(reportedProgress, [0]);
  });

  testWidgets('reader controls emit updated reading preferences', (
    tester,
  ) async {
    ReaderPreferences? changedPreferences;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (preferences) {
              changedPreferences = preferences;
            },
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('增大字号'));
    await tester.pump();

    expect(changedPreferences?.fontSize, 18);

    await tester.tap(find.byTooltip('增大行距'));
    await tester.pump();

    expect(changedPreferences?.lineHeight, closeTo(1.8, 0.001));

    await tester.tap(find.text('宽'));
    await tester.pump();

    expect(changedPreferences?.width, ReaderWidth.wide);
  });

  testWidgets('reader controls reset typography without changing queue prefs', (
    tester,
  ) async {
    ReaderPreferences? changedPreferences;
    final customPreferences = ReaderPreferences.defaultPreferences.copyWith(
      fontSize: 20,
      lineHeight: 1.9,
      width: ReaderWidth.wide,
      entrySortOrder: EntrySortOrder.oldestFirst,
      entryQueueFilter: EntryQueueFilter.inProgress,
      entryListDensity: EntryListDensity.compact,
      sourceListSortOrder: SourceListSortOrder.health,
      showTranslations: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: customPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (preferences) {
              changedPreferences = preferences;
            },
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-typography-reset')),
    );
    await tester.pump();

    expect(
      changedPreferences?.fontSize,
      ReaderPreferences.defaultPreferences.fontSize,
    );
    expect(
      changedPreferences?.lineHeight,
      ReaderPreferences.defaultPreferences.lineHeight,
    );
    expect(
      changedPreferences?.width,
      ReaderPreferences.defaultPreferences.width,
    );
    expect(changedPreferences?.entrySortOrder, EntrySortOrder.oldestFirst);
    expect(changedPreferences?.entryQueueFilter, EntryQueueFilter.inProgress);
    expect(changedPreferences?.entryListDensity, EntryListDensity.compact);
    expect(changedPreferences?.sourceListSortOrder, SourceListSortOrder.health);
    expect(changedPreferences?.showTranslations, isFalse);
  });

  testWidgets('article action buttons delegate original link actions', (
    tester,
  ) async {
    var openOriginalCount = 0;
    var copyLinkCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {
              openOriginalCount += 1;
            },
            onOpenContentLink: (_) async {},
            onCopyLink: () async {
              copyLinkCount += 1;
            },
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开原文'));
    await tester.pump();
    await tester.tap(find.text('复制链接'));
    await tester.pump();

    expect(openOriginalCount, 1);
    expect(copyLinkCount, 1);
  });

  testWidgets('toggles detail read action label from article state', (
    tester,
  ) async {
    var toggleReadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {
              toggleReadCount += 1;
            },
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('标记已读'), findsOneWidget);
    expect(find.text('标记未读'), findsNothing);

    await tester.tap(find.text('标记已读'));
    await tester.pump();

    expect(toggleReadCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(isRead: true),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 0 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {
              toggleReadCount += 1;
            },
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('标记未读'), findsOneWidget);
    expect(find.text('标记已读'), findsNothing);
  });

  testWidgets('detail summary semantics include saved and noise state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(isRead: true, isSaved: true, isNoise: true),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 0 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    final detailSummarySemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('article-detail-summary-semantics')),
    );
    expect(
      detailSummarySemantics.properties.label,
      '正在阅读，Long read，来源 Example，作者 Jane Analyst，1/1 · 0 未读，已读，稍后读，噪音箱，1 分钟，发布时间 2026-05-24 18:00',
    );
  });

  testWidgets('opens inline links from rendered article body', (tester) async {
    String? openedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              contentHtml:
                  '<p>Read the <a href="https://example.com/deep-dive">deep dive</a>.</p>',
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (url) async {
              openedUrl = url;
            },
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    final linkText = find.textRange.ofSubstring('deep dive');
    expect(linkText, findsOne);

    await tester.ensureVisible(find.textContaining('Read the deep dive'));
    await tester.pump();
    await tester.tapOnText(linkText);
    await tester.pump();

    expect(openedUrl, 'https://example.com/deep-dive');
  });

  testWidgets('shows retry action for failed AI processing', (tester) async {
    var reprocessCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(summaryStatus: 'FAILED'),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {
              reprocessCount += 1;
            },
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('AI 失败'), findsOneWidget);
    expect(find.byTooltip('AI 失败'), findsOneWidget);
    expect(find.text('重试 AI'), findsOneWidget);

    await tester.tap(find.text('重试 AI'));
    await tester.pump();

    expect(reprocessCount, 1);
  });

  testWidgets('shows AI failure reason in the status tooltip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              filterStatus: 'FAILED',
              filterReason: 'DeepSeek timeout',
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('AI 失败'), findsOneWidget);
    expect(find.byTooltip('AI 失败：DeepSeek timeout'), findsOneWidget);
  });

  testWidgets('shows visible AI pending status while keeping reading usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(summaryStatus: 'PENDING'),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('article-ai-status-notice')),
      findsOneWidget,
    );
    expect(find.text('AI 正在处理'), findsOneWidget);
    expect(find.text('摘要、翻译或去噪结果还在生成中。 文章可先继续阅读，稍后会同步最新结果。'), findsOneWidget);
    expect(find.text('重试 AI'), findsNothing);
    final noticeSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('article-ai-status-notice-semantics')),
    );
    expect(
      noticeSemantics.properties.label,
      'AI 正在处理，摘要、翻译或去噪结果还在生成中，文章可先继续阅读，稍后会同步最新结果。',
    );
  });

  testWidgets('shows visible AI failure recovery guidance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              filterStatus: 'FAILED',
              filterReason: 'DeepSeek timeout',
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('article-ai-status-notice')),
      findsOneWidget,
    );
    expect(find.text('AI 处理失败'), findsOneWidget);
    expect(find.text('DeepSeek timeout 可使用上方“重试 AI”重新处理。'), findsOneWidget);
    final noticeSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('article-ai-status-notice-semantics')),
    );
    expect(
      noticeSemantics.properties.label,
      'AI 处理失败，DeepSeek timeout，可使用上方“重试 AI”重新处理。',
    );
  });

  testWidgets('shows AI retry guidance when offline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(summaryStatus: 'FAILED'),
            showTranslations: true,
            busy: false,
            isOnline: false,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('AI 处理失败'), findsOneWidget);
    expect(find.text('服务端没有返回具体原因。 恢复在线后可重试 AI。'), findsOneWidget);
    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '重试 AI'),
    );
    expect(retryButton.onPressed, isNull);
  });

  testWidgets('shows visible AI skipped status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              filterStatus: 'SKIPPED',
              summaryStatus: 'SKIPPED',
              translationStatus: 'SKIPPED',
              filterReason: 'not enough text',
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('AI 已跳过'), findsWidgets);
    expect(find.text('not enough text 可使用上方“重试 AI”重新处理。'), findsOneWidget);
  });

  testWidgets('can refresh missing article body when online', (tester) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(contentHtml: ''),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {
              refreshCount += 1;
            },
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    expect(find.text('正文暂未同步完成'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '同步正文'), findsOneWidget);

    await tester.ensureVisible(find.text('同步正文'));
    await tester.pump();
    await tester.tap(find.text('同步正文'));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('disables missing body refresh when offline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(contentHtml: ''),
            showTranslations: true,
            busy: false,
            isOnline: false,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );

    final syncButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '同步正文'),
    );
    expect(syncButton.onPressed, isNull);
  });

  testWidgets('keeps offline-capable reader actions enabled', (tester) async {
    var toggleReadCount = 0;
    var savedCount = 0;
    var noiseCount = 0;
    var finishCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(),
            showTranslations: true,
            busy: false,
            isOnline: false,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: (_) {},
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {
              toggleReadCount += 1;
            },
            onToggleSaved: () async {
              savedCount += 1;
            },
            onToggleNoise: () async {
              noiseCount += 1;
            },
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {
              finishCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('标记已读'));
    await tester.pump();
    await tester.tap(find.text('读完'));
    await tester.pump();
    await tester.tap(find.text('稍后读'));
    await tester.pump();
    await tester.tap(find.text('移入噪音箱'));
    await tester.pump();

    expect(toggleReadCount, 1);
    expect(finishCount, 1);
    expect(savedCount, 1);
    expect(noiseCount, 1);
  });

  testWidgets('reports final reading progress before disposing', (
    tester,
  ) async {
    final reportedProgress = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: _entry(
              readingProgress: 0.2,
              contentHtml: _longContentHtml(),
            ),
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/1 · 1 未读',
            hasNextQueueEntry: false,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: reportedProgress.add,
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    expect(reportedProgress, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(reportedProgress, hasLength(1));
    expect(reportedProgress.single, greaterThan(0.2));
  });

  testWidgets('reports old article progress before switching entries', (
    tester,
  ) async {
    final oldArticleProgress = <double>[];
    final newArticleProgress = <double>[];

    Widget buildDetail({
      required EntryRecord entry,
      required ValueChanged<double> onProgressChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ArticleDetailView(
            entry: entry,
            showTranslations: true,
            busy: false,
            isOnline: true,
            queueStatus: '1/2 · 2 未读',
            hasNextQueueEntry: true,
            readerPreferences: ReaderPreferences.defaultPreferences,
            onToggleTranslations: (_) {},
            onReaderPreferencesChanged: (_) {},
            onReadingProgressChanged: onProgressChanged,
            onOpenOriginal: () async {},
            onOpenContentLink: (_) async {},
            onCopyLink: () async {},
            onToggleRead: () async {},
            onToggleSaved: () async {},
            onToggleNoise: () async {},
            onReprocessAi: () async {},
            onRefreshEntry: () async {},
            onFinishAndOpenNext: () async {},
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildDetail(
        entry: _entry(readingProgress: 0.2, contentHtml: _longContentHtml()),
        onProgressChanged: oldArticleProgress.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    expect(oldArticleProgress, isEmpty);

    await tester.pumpWidget(
      buildDetail(
        entry: _entry(
          id: 2,
          title: 'Next read',
          contentHtml: _longContentHtml(),
        ),
        onProgressChanged: newArticleProgress.add,
      ),
    );

    expect(oldArticleProgress, hasLength(1));
    expect(oldArticleProgress.single, greaterThan(0.2));
    expect(newArticleProgress, isEmpty);
  });
}

EntryRecord _entry({
  int id = 1,
  String title = 'Long read',
  double readingProgress = 0,
  bool isRead = false,
  bool isSaved = false,
  bool isNoise = false,
  String sourceName = 'Example',
  String? filterStatus,
  String? filterReason,
  String? summaryStatus,
  String? translationStatus,
  String contentHtml = '<p>Body</p>',
}) {
  return EntryRecord(
    id: id,
    sourceId: 1,
    sourceName: sourceName,
    author: 'Jane Analyst',
    title: title,
    link: 'https://example.com/1',
    publishedAt: DateTime.utc(2026, 5, 24, 10),
    summary: 'Summary',
    isRead: isRead,
    isSaved: isSaved,
    readingProgress: readingProgress,
    isNoise: isNoise,
    foreign: false,
    filterStatus: filterStatus,
    summaryStatus: summaryStatus,
    translationStatus: translationStatus,
    coverImageUrl: null,
    contentHtml: contentHtml,
    filterReason: filterReason,
    translationSegments: const [],
  );
}

String _longContentHtml() {
  final paragraphs = List.generate(
    120,
    (index) => '<p>Paragraph $index ${List.filled(28, 'word').join(' ')}.</p>',
  );
  return paragraphs.join();
}
