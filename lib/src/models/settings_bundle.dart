enum AppThemeMode {
  system('SYSTEM'),
  light('LIGHT'),
  dark('DARK');

  const AppThemeMode(this.wireValue);

  final String wireValue;

  static AppThemeMode fromWire(String? value) {
    return switch ((value ?? '').toUpperCase()) {
      'LIGHT' => AppThemeMode.light,
      'DARK' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.configured,
    required this.apiKeyMasked,
    required this.filterPrompt,
    required this.summaryPrompt,
    required this.translationPrompt,
    required this.autoSummaryEnabled,
    required this.autoTranslationEnabled,
    required this.outputLanguage,
  });

  final String provider;
  final bool configured;
  final String? apiKeyMasked;
  final String filterPrompt;
  final String summaryPrompt;
  final String translationPrompt;
  final bool autoSummaryEnabled;
  final bool autoTranslationEnabled;
  final String outputLanguage;

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    return AiSettings(
      provider: json['provider'] as String? ?? 'DEEPSEEK',
      configured: json['configured'] as bool? ?? false,
      apiKeyMasked: json['apiKeyMasked'] as String?,
      filterPrompt: json['filterPrompt'] as String? ?? '',
      summaryPrompt: json['summaryPrompt'] as String? ?? '',
      translationPrompt: json['translationPrompt'] as String? ?? '',
      autoSummaryEnabled: json['autoSummaryEnabled'] as bool? ?? false,
      autoTranslationEnabled: json['autoTranslationEnabled'] as bool? ?? false,
      outputLanguage: json['outputLanguage'] as String? ?? 'zh-CN',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider': provider,
      'configured': configured,
      'apiKeyMasked': apiKeyMasked,
      'filterPrompt': filterPrompt,
      'summaryPrompt': summaryPrompt,
      'translationPrompt': translationPrompt,
      'autoSummaryEnabled': autoSummaryEnabled,
      'autoTranslationEnabled': autoTranslationEnabled,
      'outputLanguage': outputLanguage,
    };
  }

  AiSettings copyWith({
    String? provider,
    bool? configured,
    String? apiKeyMasked,
    bool clearApiKeyMasked = false,
    String? filterPrompt,
    String? summaryPrompt,
    String? translationPrompt,
    bool? autoSummaryEnabled,
    bool? autoTranslationEnabled,
    String? outputLanguage,
  }) {
    return AiSettings(
      provider: provider ?? this.provider,
      configured: configured ?? this.configured,
      apiKeyMasked: clearApiKeyMasked
          ? null
          : apiKeyMasked ?? this.apiKeyMasked,
      filterPrompt: filterPrompt ?? this.filterPrompt,
      summaryPrompt: summaryPrompt ?? this.summaryPrompt,
      translationPrompt: translationPrompt ?? this.translationPrompt,
      autoSummaryEnabled: autoSummaryEnabled ?? this.autoSummaryEnabled,
      autoTranslationEnabled:
          autoTranslationEnabled ?? this.autoTranslationEnabled,
      outputLanguage: outputLanguage ?? this.outputLanguage,
    );
  }
}

class AppearanceSettings {
  const AppearanceSettings({required this.themeMode});

  final AppThemeMode themeMode;

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      themeMode: AppThemeMode.fromWire(json['themeMode'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'themeMode': themeMode.wireValue};
  }
}

class FeedSettings {
  const FeedSettings({
    required this.defaultLanguage,
    required this.refreshPolicyDescription,
  });

  final String defaultLanguage;
  final String refreshPolicyDescription;

  factory FeedSettings.fromJson(Map<String, dynamic> json) {
    return FeedSettings(
      defaultLanguage: json['defaultLanguage'] as String? ?? 'zh-CN',
      refreshPolicyDescription:
          json['refreshPolicyDescription'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'defaultLanguage': defaultLanguage,
      'refreshPolicyDescription': refreshPolicyDescription,
    };
  }
}

class AccountSettings {
  const AccountSettings({required this.email, required this.displayName});

  final String email;
  final String displayName;

  factory AccountSettings.fromJson(Map<String, dynamic> json) {
    return AccountSettings(
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'email': email, 'displayName': displayName};
  }
}

class SettingsBundle {
  const SettingsBundle({
    required this.ai,
    required this.appearance,
    required this.feeds,
    required this.account,
  });

  final AiSettings ai;
  final AppearanceSettings appearance;
  final FeedSettings feeds;
  final AccountSettings account;

  factory SettingsBundle.fromJson(Map<String, dynamic> json) {
    return SettingsBundle(
      ai: AiSettings.fromJson(
        (json['ai'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      appearance: AppearanceSettings.fromJson(
        (json['appearance'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      feeds: FeedSettings.fromJson(
        (json['feeds'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      account: AccountSettings.fromJson(
        (json['account'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
    );
  }

  const SettingsBundle.empty()
    : ai = const AiSettings(
        provider: 'DEEPSEEK',
        configured: false,
        apiKeyMasked: null,
        filterPrompt: '',
        summaryPrompt: '',
        translationPrompt: '',
        autoSummaryEnabled: false,
        autoTranslationEnabled: false,
        outputLanguage: 'zh-CN',
      ),
      appearance = const AppearanceSettings(themeMode: AppThemeMode.system),
      feeds = const FeedSettings(
        defaultLanguage: 'zh-CN',
        refreshPolicyDescription: '',
      ),
      account = const AccountSettings(email: '', displayName: '');

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ai': ai.toJson(),
      'appearance': appearance.toJson(),
      'feeds': feeds.toJson(),
      'account': account.toJson(),
    };
  }

  SettingsBundle copyWith({
    AiSettings? ai,
    AppearanceSettings? appearance,
    FeedSettings? feeds,
    AccountSettings? account,
  }) {
    return SettingsBundle(
      ai: ai ?? this.ai,
      appearance: appearance ?? this.appearance,
      feeds: feeds ?? this.feeds,
      account: account ?? this.account,
    );
  }
}
