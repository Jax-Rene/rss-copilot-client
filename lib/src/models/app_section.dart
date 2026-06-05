enum AppSection {
  feed,
  noise,
  saved,
  sources,
  sourceEntries,
  settings,
  account;

  String get title {
    return switch (this) {
      AppSection.feed => 'Feed 流',
      AppSection.noise => '噪音箱',
      AppSection.saved => '稍后读',
      AppSection.sources => '订阅源',
      AppSection.sourceEntries => '订阅源文章',
      AppSection.settings => '设置',
      AppSection.account => '账号',
    };
  }
}

enum SettingsSection {
  ai('AI'),
  appearance('外观'),
  feeds('订阅'),
  about('关于');

  const SettingsSection(this.label);

  final String label;
}
