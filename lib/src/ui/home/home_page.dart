import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/api/api_exception.dart';
import '../../models/app_section.dart';
import '../../models/entry_record.dart';
import '../../models/feed_source.dart';
import '../../models/settings_bundle.dart';
import '../../state/app_controller.dart';
import '../../state/providers.dart';
import 'responsive_home_shell.dart';
import 'widgets/ai_settings_form.dart';
import 'widgets/article_detail_view.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final state = controller.state;
    final theme = Theme.of(context);

    final message = state.errorMessage;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.scaffoldBackgroundColor,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (message != null)
                MaterialBanner(
                  content: Text(message),
                  actions: [
                    TextButton(
                      onPressed: controller.clearError,
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              Expanded(
                child: ResponsiveHomeShell(
                  navigationPane: _DesktopSidebar(controller: controller),
                  listPane: _DesktopListPane(controller: controller),
                  detailPane: _DesktopDetailPane(controller: controller),
                  mobileBody: _MobileHomeBody(controller: controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final totalUnread = state.snapshot.sources.fold<int>(
      0,
      (sum, source) => sum + source.unreadCount,
    );
    final items = <({AppSection section, IconData icon, String label})>[
      (section: AppSection.feed, icon: Icons.article_outlined, label: 'Feed'),
      (
        section: AppSection.noise,
        icon: Icons.filter_alt_outlined,
        label: 'Noise',
      ),
      (
        section: AppSection.sources,
        icon: Icons.rss_feed_rounded,
        label: 'Sources',
      ),
      (
        section: AppSection.settings,
        icon: Icons.tune_rounded,
        label: 'Settings',
      ),
      (
        section: AppSection.account,
        icon: Icons.person_outline_rounded,
        label: 'Account',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(
              totalUnread.toString(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          for (final item in items) ...[
            _SidebarButton(
              selected:
                  state.section == item.section ||
                  (item.section == AppSection.sources &&
                      state.section == AppSection.sourceEntries),
              icon: item.icon,
              label: item.label,
              onTap: () => controller.selectSection(item.section),
            ),
            const SizedBox(height: 10),
          ],
          const Spacer(),
          IconButton(
            tooltip: '立即同步',
            onPressed: state.busy ? null : () => controller.syncNow(),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopListPane extends StatelessWidget {
  const _DesktopListPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.section == AppSection.settings) {
      return _SettingsMenu(controller: controller);
    }
    if (state.section == AppSection.account) {
      return _AccountMenu(controller: controller);
    }
    if (state.section == AppSection.sources) {
      return _SourceListPane(controller: controller, mobile: false);
    }
    return _EntryListPane(controller: controller, mobile: false);
  }
}

class _DesktopDetailPane extends StatelessWidget {
  const _DesktopDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.section == AppSection.settings) {
      return _SettingsDetailPane(controller: controller);
    }
    if (state.section == AppSection.account) {
      return _AccountDetailPane(controller: controller);
    }
    if (state.section == AppSection.sources) {
      return Center(
        child: Text(
          '选择一个订阅源，进入该源的文章流。',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    return ArticleDetailView(
      entry: controller.selectedEntry,
      showTranslations: state.showTranslations,
      busy: state.busy,
      isOnline: state.isOnline,
      onToggleTranslations: controller.toggleTranslations,
      onMarkUnread: () => controller.markSelectedUnread(),
    );
  }
}

class _MobileHomeBody extends StatefulWidget {
  const _MobileHomeBody({required this.controller});

  final AppController controller;

  @override
  State<_MobileHomeBody> createState() => _MobileHomeBodyState();
}

class _MobileHomeBodyState extends State<_MobileHomeBody> {
  int _indexForSection(AppSection section) {
    return switch (section) {
      AppSection.feed => 0,
      AppSection.noise => 1,
      AppSection.sources || AppSection.sourceEntries => 2,
      AppSection.settings || AppSection.account => 3,
    };
  }

  AppSection _sectionForIndex(int index) {
    return switch (index) {
      0 => AppSection.feed,
      1 => AppSection.noise,
      2 => AppSection.sources,
      _ => AppSection.settings,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final currentIndex = _indexForSection(state.section);
    return Scaffold(
      body: switch (state.section) {
        AppSection.feed || AppSection.noise => _EntryListPane(
          controller: controller,
          mobile: true,
        ),
        AppSection.sources || AppSection.sourceEntries => _SourceListPane(
          controller: controller,
          mobile: true,
        ),
        AppSection.settings ||
        AppSection.account => _SettingsDetailPane(controller: controller),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) =>
            controller.selectSection(_sectionForIndex(index)),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.filter_alt_outlined),
            label: 'Noise',
          ),
          NavigationDestination(
            icon: Icon(Icons.rss_feed_rounded),
            label: 'Sources',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _EntryListPane extends StatelessWidget {
  const _EntryListPane({required this.controller, required this.mobile});

  final AppController controller;
  final bool mobile;

  Future<void> _showActionError(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on SocketException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下不支持写操作')));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openMobileDetail(
    BuildContext context,
    EntryRecord entry,
  ) async {
    await controller.openEntry(entry.id);
    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final latestController = ref.watch(appControllerProvider);
            return Scaffold(
              appBar: AppBar(title: Text(entry.sourceName)),
              body: ArticleDetailView(
                entry: latestController.selectedEntry,
                showTranslations: latestController.state.showTranslations,
                busy: latestController.state.busy,
                isOnline: latestController.state.isOnline,
                onToggleTranslations: latestController.toggleTranslations,
                onMarkUnread: () => latestController.markSelectedUnread(),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final entries = controller.visibleEntries;
    final title = switch (state.section) {
      AppSection.feed => 'Feed 流',
      AppSection.noise => '噪音箱',
      AppSection.sourceEntries => controller.selectedSource?.name ?? '订阅源文章',
      _ => state.section.title,
    };

    final listView = ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = state.selectedEntryId == entry.id;
        return Card(
          color: selected && !mobile
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.65)
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => mobile
                ? _openMobileDetail(context, entry)
                : controller.openEntry(entry.id),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: entry.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                        ),
                      ),
                      if (!entry.isRead)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(left: 8, top: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        entry.sourceName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        AppFormatters.listDate(entry.publishedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (entry.foreign)
                        Text(
                          '外文',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                    ],
                  ),
                  if ((entry.summary ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      entry.summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mobile) {
      return Column(
        children: [
          AppBar(
            title: Text(title),
            actions: [
              IconButton(
                onPressed: state.busy
                    ? null
                    : () => controller.toggleUnreadOnly(!state.unreadOnly),
                icon: Icon(
                  state.unreadOnly
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                ),
              ),
              IconButton(
                onPressed: state.busy
                    ? null
                    : () => _showActionError(
                        context,
                        () => controller.refreshAll(),
                      ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => controller.refreshAll(),
              child: entries.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('当前没有可展示的文章')),
                      ],
                    )
                  : listView,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.section == AppSection.sourceEntries)
                TextButton.icon(
                  onPressed: controller.backToSourceList,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回订阅源列表'),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch.adaptive(
                    value: state.unreadOnly,
                    onChanged: controller.toggleUnreadOnly,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: state.busy
                        ? null
                        : () => _showActionError(
                            context,
                            () => controller.refreshAll(),
                          ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新全部'),
                  ),
                  if (state.section == AppSection.feed ||
                      state.section == AppSection.noise)
                    FilledButton.tonalIcon(
                      onPressed: state.busy
                          ? null
                          : () => _showActionError(
                              context,
                              () => controller.markAllRead(),
                            ),
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('全部标记已读'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('当前没有可展示的文章'))
              : listView,
        ),
      ],
    );
  }
}

class _SourceListPane extends StatelessWidget {
  const _SourceListPane({required this.controller, required this.mobile});

  final AppController controller;
  final bool mobile;

  Future<void> _showAddDialog(BuildContext context) async {
    final inputController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加订阅源'),
        content: TextField(
          controller: inputController,
          decoration: const InputDecoration(
            labelText: 'RSS URL',
            hintText: 'https://example.com/feed.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(inputController.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    inputController.dispose();

    if (result == null || result.isEmpty || !context.mounted) {
      return;
    }

    try {
      await controller.addSource(result);
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法添加订阅源')));
    }
  }

  Future<void> _showEditDialog(BuildContext context, FeedSource source) async {
    final nameController = TextEditingController(text: source.name);
    final rssUrlController = TextEditingController(text: source.rssUrl);
    final iconUrlController = TextEditingController(text: source.iconUrl ?? '');
    var enabled = source.enabled;

    final updated = await showDialog<FeedSource>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑订阅源'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rssUrlController,
                  decoration: const InputDecoration(labelText: 'RSS URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: iconUrlController,
                  decoration: const InputDecoration(labelText: '图标 URL'),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: enabled,
                  title: const Text('启用自动抓取'),
                  onChanged: (value) => setState(() {
                    enabled = value;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  source.copyWith(
                    name: nameController.text.trim(),
                    rssUrl: rssUrlController.text.trim(),
                    iconUrl: iconUrlController.text.trim().isEmpty
                        ? null
                        : iconUrlController.text.trim(),
                    enabled: enabled,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    rssUrlController.dispose();
    iconUrlController.dispose();

    if (updated == null || !context.mounted) {
      return;
    }

    try {
      await controller.updateSource(updated);
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法编辑订阅源')));
    }
  }

  Future<void> _deleteSource(BuildContext context, FeedSource source) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除订阅源'),
            content: Text('删除 ${source.name} 后，该源历史文章也会一并从本地清理。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.deleteSource(source.id);
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法删除订阅源')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final sources = state.snapshot.sources;

    final content = sources.isEmpty
        ? const Center(child: Text('还没有订阅源，先添加一个 RSS URL。'))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final source = sources[index];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => controller.openSource(source.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: source.hasError
                              ? const Icon(Icons.error_outline_rounded)
                              : const Icon(Icons.rss_feed_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                source.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                source.rssUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (source.lastFetchedAt != null)
                                Text(
                                  '最近刷新 ${AppFormatters.listDate(source.lastFetchedAt!)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${source.unreadCount}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    unawaited(_showEditDialog(context, source));
                                  case 'delete':
                                    unawaited(_deleteSource(context, source));
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

    if (mobile) {
      return Column(
        children: [
          AppBar(
            title: const Text('订阅源'),
            actions: [
              IconButton(
                onPressed: state.busy ? null : () => controller.refreshAll(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                onPressed: state.busy ? null : () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => controller.refreshAll(),
              child: content,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '订阅源',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy ? null : () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加'),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in SettingsSection.values) ...[
          ListTile(
            selected: state.settingsSection == section,
            title: Text(section.label),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onTap: () => controller.changeSettingsSection(section),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SettingsDetailPane extends StatelessWidget {
  const _SettingsDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final settings = state.snapshot.settings;
    return switch (state.settingsSection) {
      SettingsSection.ai => AiSettingsForm(
        settings: settings.ai,
        busy: state.busy,
        onSave: (nextSettings, rawApiKey) => controller.saveAiSettings(
          settings: nextSettings,
          rawApiKey: rawApiKey,
        ),
      ),
      SettingsSection.appearance => _AppearancePane(controller: controller),
      SettingsSection.feeds => _FeedsPane(settings: settings),
      SettingsSection.about => _AboutPane(controller: controller),
    };
  }
}

class _AppearancePane extends StatelessWidget {
  const _AppearancePane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final selected = state.session?.themeOverride;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Appearance',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('服务端当前只返回外观设置快照，这里额外支持本机本地覆盖。'),
        const SizedBox(height: 20),
        SegmentedButton<AppThemeMode?>(
          segments: const [
            ButtonSegment<AppThemeMode?>(value: null, label: Text('跟随服务端')),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.system,
              label: Text('系统'),
            ),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.light,
              label: Text('浅色'),
            ),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.dark,
              label: Text('深色'),
            ),
          ],
          selected: <AppThemeMode?>{selected},
          onSelectionChanged: (values) =>
              controller.setThemeOverride(values.first),
        ),
        const SizedBox(height: 20),
        Text(
          '服务端默认主题：${state.snapshot.settings.appearance.themeMode.wireValue}',
        ),
      ],
    );
  }
}

class _FeedsPane extends StatelessWidget {
  const _FeedsPane({required this.settings});

  final SettingsBundle settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Feeds',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('默认语言'),
          subtitle: Text(settings.feeds.defaultLanguage),
        ),
        ListTile(
          title: const Text('刷新策略'),
          subtitle: Text(settings.feeds.refreshPolicyDescription),
        ),
      ],
    );
  }
}

class _AboutPane extends StatelessWidget {
  const _AboutPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.state.session;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'About',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('当前账号'),
          subtitle: Text(session?.user.email ?? '-'),
        ),
        ListTile(
          title: const Text('服务端地址'),
          subtitle: Text(session?.baseUrl ?? '-'),
        ),
        ListTile(
          title: const Text('最近同步游标'),
          subtitle: Text(session?.lastServerTime?.toIso8601String() ?? '-'),
        ),
      ],
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final email = controller.state.session?.user.email ?? '-';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(title: Text(email)),
        const SizedBox(height: 8),
        const ListTile(title: Text('支持登出和查看当前服务器信息')),
      ],
    );
  }
}

class _AccountDetailPane extends StatelessWidget {
  const _AccountDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.state.session;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '账号',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('邮箱'),
          subtitle: Text(session?.user.email ?? '-'),
        ),
        ListTile(
          title: const Text('显示名称'),
          subtitle: Text(session?.user.displayName ?? '-'),
        ),
        ListTile(
          title: const Text('服务端'),
          subtitle: Text(session?.baseUrl ?? '-'),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: controller.state.busy ? null : () => controller.logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}
