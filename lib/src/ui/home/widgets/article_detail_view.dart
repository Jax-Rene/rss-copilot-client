import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/formatters.dart';
import '../../../models/entry_record.dart';

class ArticleDetailView extends StatelessWidget {
  const ArticleDetailView({
    super.key,
    required this.entry,
    required this.showTranslations,
    required this.busy,
    required this.isOnline,
    required this.onToggleTranslations,
    required this.onMarkUnread,
  });

  final EntryRecord? entry;
  final bool showTranslations;
  final bool busy;
  final bool isOnline;
  final ValueChanged<bool> onToggleTranslations;
  final Future<void> Function() onMarkUnread;

  Future<void> _openOriginal() async {
    final current = entry;
    if (current == null) {
      return;
    }

    final uri = Uri.tryParse(current.link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    final current = entry;
    if (current == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: current.link));
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制原文链接')));
  }

  @override
  Widget build(BuildContext context) {
    final current = entry;
    if (current == null) {
      return Center(
        child: Text(
          '选择一篇文章开始阅读',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text(
            current.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(current.sourceName)),
              Text(
                AppFormatters.detailDate(current.publishedAt),
                style: theme.textTheme.bodySmall,
              ),
              if (current.foreign)
                const Chip(
                  avatar: Icon(Icons.translate_rounded, size: 16),
                  label: Text('外文'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _openOriginal,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('打开原文'),
              ),
              FilledButton.tonalIcon(
                onPressed: busy || !isOnline ? null : onMarkUnread,
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: const Text('标记未读'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _copyLink(context),
                icon: const Icon(Icons.link_rounded),
                label: const Text('复制链接'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if ((current.summary ?? '').trim().isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 总结',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(current.summary!),
                  ],
                ),
              ),
            ),
          if ((current.summary ?? '').trim().isNotEmpty)
            const SizedBox(height: 20),
          if (current.translationSegments.isNotEmpty) ...[
            SwitchListTile.adaptive(
              value: showTranslations,
              contentPadding: EdgeInsets.zero,
              title: const Text('显示双语译文'),
              subtitle: const Text('译文段落按原文顺序显示，可一键隐藏。'),
              onChanged: onToggleTranslations,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '双语阅读',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final segment in current.translationSegments) ...[
                      SelectableText(
                        segment.source,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                      ),
                      if (showTranslations) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          segment.translation,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.7,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: (current.contentHtml ?? '').trim().isNotEmpty
                  ? Html(data: current.contentHtml!)
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
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
