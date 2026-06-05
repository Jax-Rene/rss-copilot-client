import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../core/app_theme.dart';
import '../../../core/diagnostic_redaction.dart';
import '../../../core/formatters.dart';
import '../../../core/reading_metrics.dart';
import '../../../models/entry_record.dart';
import '../../../models/reader_preferences.dart';

class ArticleDetailView extends StatefulWidget {
  const ArticleDetailView({
    super.key,
    required this.entry,
    this.sourceIconUrl,
    required this.showTranslations,
    required this.busy,
    required this.isOnline,
    required this.queueStatus,
    required this.hasNextQueueEntry,
    required this.readerPreferences,
    required this.onToggleTranslations,
    required this.onReaderPreferencesChanged,
    required this.onReadingProgressChanged,
    required this.onOpenOriginal,
    required this.onOpenContentLink,
    required this.onCopyLink,
    this.onCopyCitation,
    this.onCopySummary,
    this.onCopyTranslations,
    this.onCopyNote,
    required this.onToggleRead,
    required this.onToggleSaved,
    required this.onToggleNoise,
    required this.onReprocessAi,
    required this.onRefreshEntry,
    required this.onFinishAndOpenNext,
  });

  final EntryRecord? entry;
  final String? sourceIconUrl;
  final bool showTranslations;
  final bool busy;
  final bool isOnline;
  final String queueStatus;
  final bool hasNextQueueEntry;
  final ReaderPreferences readerPreferences;
  final ValueChanged<bool> onToggleTranslations;
  final ValueChanged<ReaderPreferences> onReaderPreferencesChanged;
  final ValueChanged<double> onReadingProgressChanged;
  final Future<void> Function() onOpenOriginal;
  final Future<void> Function(String url) onOpenContentLink;
  final Future<void> Function() onCopyLink;
  final Future<void> Function()? onCopyCitation;
  final Future<void> Function()? onCopySummary;
  final Future<void> Function()? onCopyTranslations;
  final Future<void> Function()? onCopyNote;
  final Future<void> Function() onToggleRead;
  final Future<void> Function() onToggleSaved;
  final Future<void> Function() onToggleNoise;
  final Future<void> Function() onReprocessAi;
  final Future<void> Function() onRefreshEntry;
  final Future<void> Function() onFinishAndOpenNext;

  @override
  State<ArticleDetailView> createState() => _ArticleDetailViewState();
}

class _ArticleDetailViewState extends State<ArticleDetailView> {
  final ScrollController _scrollController = ScrollController();

  int? _restoredEntryId;
  bool _restoring = false;
  double? _lastReportedProgress;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant ArticleDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry?.id != widget.entry?.id) {
      _reportReadingProgress(
        entry: oldWidget.entry,
        onChanged: oldWidget.onReadingProgressChanged,
        force: true,
      );
      _restoredEntryId = null;
      _lastReportedProgress = null;
    }
  }

  @override
  void dispose() {
    _reportReadingProgress(
      entry: widget.entry,
      onChanged: widget.onReadingProgressChanged,
      force: true,
    );
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    _reportReadingProgress(
      entry: widget.entry,
      onChanged: widget.onReadingProgressChanged,
      force: true,
    );
    super.deactivate();
  }

  void _scheduleRestore() {
    final entryId = widget.entry?.id;
    if (entryId == null || _restoredEntryId == entryId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreReadingPosition(entryId);
    });
  }

  void _restoreReadingPosition(int entryId) {
    if (!mounted ||
        widget.entry?.id != entryId ||
        !_scrollController.hasClients) {
      return;
    }

    _restoredEntryId = entryId;
    final progress = widget.entry!.readingProgress.clamp(0, 1).toDouble();
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return;
    }

    _restoring = true;
    _scrollController.jumpTo(
      (maxScrollExtent * progress).clamp(0, maxScrollExtent),
    );
    _restoring = false;
    _lastReportedProgress = progress;
  }

  void _handleScroll() {
    _reportReadingProgress(
      entry: widget.entry,
      onChanged: widget.onReadingProgressChanged,
    );
  }

  void _restartReading() {
    final entry = widget.entry;
    if (entry == null) {
      return;
    }

    _lastReportedProgress = 0;
    widget.onReadingProgressChanged(0);
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(0);
  }

  void _reportReadingProgress({
    required EntryRecord? entry,
    required ValueChanged<double> onChanged,
    bool force = false,
  }) {
    if (_restoring) {
      return;
    }

    if (entry == null || !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final maxScrollExtent = position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return;
    }

    final progress = (position.pixels / maxScrollExtent).clamp(0, 1).toDouble();
    final previous = _lastReportedProgress;
    if (force) {
      if (previous != null && (previous - progress).abs() < 0.001) {
        return;
      }
      if (previous == null && progress <= 0.001) {
        return;
      }
    } else if (previous != null &&
        (previous - progress).abs() < 0.03 &&
        progress < 0.985) {
      return;
    }

    _lastReportedProgress = progress;
    onChanged(progress);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRestore();
    final current = widget.entry;
    if (current == null) {
      return Center(
        child: Text(
          '选择一篇文章开始阅读',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final theme = Theme.of(context);
    final hasCover = (current.coverImageUrl ?? '').trim().isNotEmpty;
    final readingTextStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: widget.readerPreferences.fontSize,
      height: widget.readerPreferences.lineHeight,
    );
    final readingMediumStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: widget.readerPreferences.fontSize - 1,
      height: widget.readerPreferences.lineHeight,
    );
    final readingProgress = current.readingProgress.clamp(0, 1).toDouble();
    final readingProgressPercent = (readingProgress * 100).round();
    final redactedSourceName = redactDiagnosticText(current.sourceName);
    final remainingReadingMinutes =
        ReadingMetrics.estimateRemainingReadingMinutes(current);
    final readingProgressSemanticsLabel = remainingReadingMinutes > 0
        ? '阅读进度，${ReadingMetrics.remainingReadingTimeLabel(current)}'
        : '阅读进度';
    return ColoredBox(
      color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
      child: SelectionArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.readerPreferences.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      key: const ValueKey<String>(
                        'article-detail-summary-semantics',
                      ),
                      header: true,
                      label: _articleDetailSemanticsLabel(
                        current,
                        queueStatus: widget.queueStatus,
                      ),
                      child: Text(
                        current.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          avatar: _ArticleSourceIcon(
                            imageUrl: widget.sourceIconUrl,
                          ),
                          label: Text(redactedSourceName),
                        ),
                        if ((current.author ?? '').trim().isNotEmpty)
                          Chip(
                            avatar: const Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                            ),
                            label: Text(current.author!.trim()),
                          ),
                        Chip(
                          avatar: const Icon(
                            Icons.format_list_numbered_rounded,
                            size: 16,
                          ),
                          label: Text(widget.queueStatus),
                        ),
                        Chip(
                          avatar: const Icon(Icons.schedule_rounded, size: 16),
                          label: Text(ReadingMetrics.readingTimeLabel(current)),
                        ),
                        if (current.readingProgress > 0.02)
                          Chip(
                            avatar: const Icon(
                              Icons.timeline_rounded,
                              size: 16,
                            ),
                            label: Text('读到 $readingProgressPercent%'),
                          ),
                        if (remainingReadingMinutes > 0)
                          Chip(
                            avatar: const Icon(
                              Icons.hourglass_bottom_rounded,
                              size: 16,
                            ),
                            label: Text(
                              ReadingMetrics.remainingReadingTimeLabel(current),
                            ),
                          ),
                        if (current.isNoise)
                          const Chip(
                            avatar: Icon(Icons.block_rounded, size: 16),
                            label: Text('噪音'),
                          ),
                        Text(
                          AppFormatters.detailDate(current.publishedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (current.foreign)
                          const Chip(
                            avatar: Icon(Icons.translate_rounded, size: 16),
                            label: Text('外文'),
                          ),
                        if (current.aiProcessingState !=
                            EntryAiProcessingState.none)
                          Tooltip(
                            message: _aiProcessingTooltip(current),
                            child: Chip(
                              avatar: Icon(
                                _aiProcessingIcon(current.aiProcessingState),
                                size: 16,
                              ),
                              label: Text(
                                _aiProcessingLabel(current.aiProcessingState),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: widget.onOpenOriginal,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('打开原文'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.busy ? null : widget.onToggleRead,
                          icon: Icon(
                            current.isRead
                                ? Icons.mark_email_unread_outlined
                                : Icons.mark_email_read_outlined,
                          ),
                          label: Text(current.isRead ? '标记未读' : '标记已读'),
                        ),
                        FilledButton.icon(
                          onPressed: widget.busy
                              ? null
                              : widget.onFinishAndOpenNext,
                          icon: Icon(
                            widget.hasNextQueueEntry
                                ? Icons.skip_next_rounded
                                : Icons.task_alt_rounded,
                          ),
                          label: Text(
                            widget.hasNextQueueEntry ? '读完下一篇' : '读完',
                          ),
                        ),
                        if (readingProgress > 0.02)
                          FilledButton.tonalIcon(
                            key: const ValueKey<String>(
                              'article-detail-restart-reading',
                            ),
                            onPressed: widget.busy ? null : _restartReading,
                            icon: const Icon(Icons.vertical_align_top_rounded),
                            label: const Text('从头读'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: widget.busy ? null : widget.onToggleSaved,
                          icon: Icon(
                            current.isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_add_outlined,
                          ),
                          label: Text(current.isSaved ? '取消收藏' : '稍后读'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.busy ? null : widget.onToggleNoise,
                          icon: Icon(
                            current.isNoise
                                ? Icons.move_to_inbox_rounded
                                : Icons.block_rounded,
                          ),
                          label: Text(current.isNoise ? '恢复 Feed' : '移入噪音箱'),
                        ),
                        if (_canReprocessAi(current.aiProcessingState))
                          FilledButton.tonalIcon(
                            onPressed: widget.busy || !widget.isOnline
                                ? null
                                : widget.onReprocessAi,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('重试 AI'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: widget.onCopyLink,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('复制链接'),
                        ),
                        if (widget.onCopyCitation != null)
                          FilledButton.tonalIcon(
                            onPressed: widget.onCopyCitation,
                            icon: const Icon(Icons.format_quote_rounded),
                            label: const Text('复制引用'),
                          ),
                        if (widget.onCopyNote != null)
                          FilledButton.tonalIcon(
                            onPressed: widget.onCopyNote,
                            icon: const Icon(Icons.note_add_outlined),
                            label: const Text('复制笔记'),
                          ),
                      ],
                    ),
                    if (_shouldShowAiStatusNotice(
                      current.aiProcessingState,
                    )) ...[
                      const SizedBox(height: 12),
                      _ArticleAiStatusNotice(
                        entry: current,
                        isOnline: widget.isOnline,
                      ),
                    ],
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: readingProgress,
                        minHeight: 4,
                        semanticsLabel: readingProgressSemanticsLabel,
                        semanticsValue: '$readingProgressPercent',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReaderControls(
                      preferences: widget.readerPreferences,
                      onChanged: widget.onReaderPreferencesChanged,
                    ),
                    if (hasCover) ...[
                      const SizedBox(height: 22),
                      _DetailCoverImage(imageUrl: current.coverImageUrl!),
                    ],
                    const SizedBox(height: 24),
                    if ((current.summary ?? '').trim().isNotEmpty) ...[
                      _SectionPanel(
                        title: 'AI 总结',
                        trailing: widget.onCopySummary == null
                            ? null
                            : IconButton(
                                tooltip: '复制总结',
                                onPressed: widget.onCopySummary,
                                icon: const Icon(Icons.copy_rounded),
                              ),
                        child: Text(current.summary!, style: readingTextStyle),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (current.translationSegments.isNotEmpty) ...[
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile.adaptive(
                          value: widget.showTranslations,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('显示双语译文'),
                          onChanged: widget.onToggleTranslations,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SectionPanel(
                        title: '双语阅读',
                        trailing: widget.onCopyTranslations == null
                            ? null
                            : IconButton(
                                tooltip: '复制双语',
                                onPressed: widget.onCopyTranslations,
                                icon: const Icon(Icons.copy_all_rounded),
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final segment
                                in current.translationSegments) ...[
                              SelectableText(
                                segment.source,
                                style: readingTextStyle,
                              ),
                              if (widget.showTranslations) ...[
                                const SizedBox(height: 8),
                                SelectableText(
                                  segment.translation,
                                  style: readingMediumStyle?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _SectionPanel(
                      title: '正文',
                      child: (current.contentHtml ?? '').trim().isNotEmpty
                          ? Html(
                              data: _wrapHtmlForReading(
                                current.contentHtml!,
                                widget.readerPreferences,
                              ),
                              onLinkTap: (url, _, _) {
                                final targetUrl = url?.trim();
                                if (targetUrl == null || targetUrl.isEmpty) {
                                  return;
                                }
                                unawaited(widget.onOpenContentLink(targetUrl));
                              },
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '正文暂未同步完成',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text('当前仍可通过“打开原文”继续阅读。'),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: widget.busy || !widget.isOnline
                                      ? null
                                      : widget.onRefreshEntry,
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text('同步正文'),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _wrapHtmlForReading(String contentHtml, ReaderPreferences preferences) {
  return '''
<div style="font-size: ${preferences.fontSize}px; line-height: ${preferences.lineHeight};">
$contentHtml
</div>
''';
}

IconData _aiProcessingIcon(EntryAiProcessingState state) {
  return switch (state) {
    EntryAiProcessingState.pending => Icons.auto_awesome_rounded,
    EntryAiProcessingState.failed => Icons.error_outline_rounded,
    EntryAiProcessingState.skipped => Icons.auto_awesome_outlined,
    EntryAiProcessingState.none => Icons.auto_awesome_outlined,
  };
}

String _aiProcessingLabel(EntryAiProcessingState state) {
  return switch (state) {
    EntryAiProcessingState.pending => 'AI 处理中',
    EntryAiProcessingState.failed => 'AI 失败',
    EntryAiProcessingState.skipped => 'AI 已跳过',
    EntryAiProcessingState.none => 'AI',
  };
}

String _aiProcessingTooltip(EntryRecord entry) {
  final label = _aiProcessingLabel(entry.aiProcessingState);
  final reason = entry.filterReason?.trim();
  if (entry.aiProcessingState == EntryAiProcessingState.failed &&
      reason != null &&
      reason.isNotEmpty) {
    return '$label：$reason';
  }
  return label;
}

bool _canReprocessAi(EntryAiProcessingState state) {
  return state == EntryAiProcessingState.failed ||
      state == EntryAiProcessingState.skipped;
}

bool _shouldShowAiStatusNotice(EntryAiProcessingState state) {
  return state == EntryAiProcessingState.pending ||
      state == EntryAiProcessingState.failed ||
      state == EntryAiProcessingState.skipped;
}

class _ArticleAiStatusNotice extends StatelessWidget {
  const _ArticleAiStatusNotice({required this.entry, required this.isOnline});

  final EntryRecord entry;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = entry.aiProcessingState;
    final failed = state == EntryAiProcessingState.failed;
    final pending = state == EntryAiProcessingState.pending;
    final color = failed
        ? theme.colorScheme.error
        : pending
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    final title = switch (state) {
      EntryAiProcessingState.pending => 'AI 正在处理',
      EntryAiProcessingState.failed => 'AI 处理失败',
      EntryAiProcessingState.skipped => 'AI 已跳过',
      EntryAiProcessingState.none => 'AI',
    };
    final reason = entry.filterReason?.trim();
    final detail = pending
        ? '摘要、翻译或去噪结果还在生成中。'
        : reason == null || reason.isEmpty
        ? '服务端没有返回具体原因。'
        : reason;
    final nextStep = pending
        ? '文章可先继续阅读，稍后会同步最新结果。'
        : isOnline
        ? '可使用上方“重试 AI”重新处理。'
        : '恢复在线后可重试 AI。';
    final semanticsDetail = detail.replaceFirst(RegExp(r'[。.!！?？]+$'), '');

    return Semantics(
      key: const ValueKey<String>('article-ai-status-notice-semantics'),
      container: true,
      label: '$title，$semanticsDetail，$nextStep',
      child: Container(
        key: const ValueKey<String>('article-ai-status-notice'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : pending
                  ? Icons.auto_awesome_rounded
                  : Icons.auto_awesome_outlined,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$detail $nextStep',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleSourceIcon extends StatelessWidget {
  const _ArticleSourceIcon({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Icon(
        Icons.rss_feed_rounded,
        key: const ValueKey<String>('article-source-icon-fallback'),
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        key: const ValueKey<String>('article-source-icon-image'),
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.rss_feed_rounded,
          key: const ValueKey<String>('article-source-icon-fallback'),
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _articleDetailSemanticsLabel(
  EntryRecord entry, {
  required String queueStatus,
}) {
  final parts = <String>[
    '正在阅读',
    entry.title,
    '来源 ${redactDiagnosticText(entry.sourceName)}',
  ];

  final author = entry.author?.trim();
  if (author != null && author.isNotEmpty) {
    parts.add('作者 $author');
  }

  parts
    ..add(queueStatus)
    ..add(entry.isRead ? '已读' : '未读');

  if (entry.isSaved) {
    parts.add('稍后读');
  }
  if (entry.isNoise) {
    parts.add('噪音箱');
  }

  final readingProgress = entry.readingProgress.clamp(0, 1).toDouble();
  if (entry.isInProgress) {
    parts.add('阅读进度 ${(readingProgress * 100).round()}%');
    parts.add(ReadingMetrics.remainingReadingTimeLabel(entry));
  } else {
    parts.add(ReadingMetrics.readingTimeLabel(entry));
  }

  parts.add('发布时间 ${AppFormatters.detailDate(entry.publishedAt)}');
  return parts.join('，');
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({required this.preferences, required this.onChanged});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultPreferences = ReaderPreferences.defaultPreferences;
    final canResetTypography =
        preferences.fontSize != defaultPreferences.fontSize ||
        preferences.lineHeight != defaultPreferences.lineHeight ||
        preferences.width != defaultPreferences.width;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _IconStepper(
              tooltipDecrease: '减小字号',
              tooltipIncrease: '增大字号',
              icon: Icons.format_size_rounded,
              label: '${preferences.fontSize.toStringAsFixed(0)}px',
              onDecrease: () => onChanged(
                preferences.copyWith(fontSize: preferences.fontSize - 1),
              ),
              onIncrease: () => onChanged(
                preferences.copyWith(fontSize: preferences.fontSize + 1),
              ),
            ),
            _IconStepper(
              tooltipDecrease: '降低行距',
              tooltipIncrease: '增大行距',
              icon: Icons.format_line_spacing_rounded,
              label: preferences.lineHeight.toStringAsFixed(2),
              onDecrease: () => onChanged(
                preferences.copyWith(lineHeight: preferences.lineHeight - 0.1),
              ),
              onIncrease: () => onChanged(
                preferences.copyWith(lineHeight: preferences.lineHeight + 0.1),
              ),
            ),
            SegmentedButton<ReaderWidth>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ReaderWidth.narrow, label: Text('窄')),
                ButtonSegment(
                  value: ReaderWidth.comfortable,
                  label: Text('舒适'),
                ),
                ButtonSegment(value: ReaderWidth.wide, label: Text('宽')),
              ],
              selected: {preferences.width},
              onSelectionChanged: (values) {
                onChanged(preferences.copyWith(width: values.first));
              },
            ),
            Tooltip(
              message: '恢复默认排版',
              child: IconButton.filledTonal(
                key: const ValueKey<String>('reader-typography-reset'),
                onPressed: canResetTypography
                    ? () => onChanged(
                        preferences.copyWith(
                          fontSize: defaultPreferences.fontSize,
                          lineHeight: defaultPreferences.lineHeight,
                          width: defaultPreferences.width,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconStepper extends StatelessWidget {
  const _IconStepper({
    required this.tooltipDecrease,
    required this.tooltipIncrease,
    required this.icon,
    required this.label,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String tooltipDecrease;
  final String tooltipIncrease;
  final IconData icon;
  final String label;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltipDecrease,
            visualDensity: VisualDensity.compact,
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded),
          ),
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          SizedBox(
            width: 48,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: tooltipIncrease,
            visualDensity: VisualDensity.compact,
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _DetailCoverImage extends StatelessWidget {
  const _DetailCoverImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Image.network(
        imageUrl,
        width: double.infinity,
        height: 260,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: 120,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
