enum AppSection {
  feed,
  noise,
  sources,
  sourceEntries,
  settings,
  account;

  String get title {
    return switch (this) {
      AppSection.feed => 'Feed 流',
      AppSection.noise => '噪音箱',
      AppSection.sources => '订阅源',
      AppSection.sourceEntries => '订阅源文章',
      AppSection.settings => '设置',
      AppSection.account => '账号',
    };
  }
}

enum SettingsSection {
  ai('AI'),
  appearance('Appearance'),
  feeds('Feeds'),
  about('About');

  const SettingsSection(this.label);

  final String label;
}
