import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/models/settings_bundle.dart';
import 'package:rss_copilot_client/src/ui/home/widgets/ai_settings_form.dart';

void main() {
  testWidgets('AI settings form blocks blank prompt fields', (tester) async {
    var submitted = false;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {
        submitted = true;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-summary-prompt-field')),
      ' ',
    );
    await _tapSave(tester);
    await tester.pump();

    expect(submitted, isFalse);
    expect(find.text('摘要 Prompt 不能为空'), findsOneWidget);
  });

  testWidgets('AI settings form can clear an existing API key', (tester) async {
    Object? submittedApiKey = _unset;
    bool? submittedClearApiKey;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {
        submittedApiKey = rawApiKey;
        submittedClearApiKey = clearApiKey;
      },
    );

    await tester.tap(find.byKey(const ValueKey<String>('ai-clear-api-key')));
    await tester.pump();

    final apiKeyField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('ai-api-key-field')),
    );
    expect(apiKeyField.enabled, isFalse);

    await _tapSave(tester);
    await tester.pump();

    expect(submittedApiKey, isNull);
    expect(submittedClearApiKey, isTrue);
  });

  testWidgets('AI settings form saves a replacement API key', (tester) async {
    Object? submittedApiKey = _unset;
    bool? submittedClearApiKey;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {
        submittedApiKey = rawApiKey;
        submittedClearApiKey = clearApiKey;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-api-key-field')),
      ' sk-new ',
    );
    await _tapSave(tester);
    await tester.pump();

    expect(submittedApiKey, 'sk-new');
    expect(submittedClearApiKey, isFalse);
  });

  testWidgets('AI settings form displays provider as read-only', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    final providerFieldFinder = find.byKey(
      const ValueKey<String>('ai-provider-field'),
    );
    final providerFormField = tester.widget<TextFormField>(providerFieldFinder);
    final providerTextField = tester.widget<TextField>(
      find.descendant(
        of: providerFieldFinder,
        matching: find.byType(TextField),
      ),
    );

    expect(providerTextField.readOnly, isTrue);
    expect(providerFormField.controller?.text, 'DEEPSEEK');
    expect(
      find.text('当前仅支持 DeepSeek，后续服务端支持新 Provider 后会开放选择。'),
      findsOneWidget,
    );
  });

  testWidgets('AI settings form rejects invalid output language', (
    tester,
  ) async {
    var submitted = false;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {
        submitted = true;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-output-language-field')),
      'not a language',
    );
    await _tapSave(tester);
    await tester.pump();

    expect(submitted, isFalse);
    expect(find.text('输出语言 必须是 BCP 47 标签，例如 zh-CN'), findsOneWidget);
  });

  testWidgets('AI settings form normalizes output language before saving', (
    tester,
  ) async {
    AiSettings? submittedSettings;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (settings, {rawApiKey, required clearApiKey}) async {
        submittedSettings = settings;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-output-language-field')),
      ' en-us ',
    );
    await _tapSave(tester);
    await tester.pump();

    expect(submittedSettings?.outputLanguage, 'en-US');
  });

  testWidgets('AI settings form offers quick output language choices', (
    tester,
  ) async {
    AiSettings? submittedSettings;

    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (settings, {rawApiKey, required clearApiKey}) async {
        submittedSettings = settings;
      },
    );

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('ai-output-language-zh-CN')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('ai-output-language-en-US')),
    );
    await tester.pump();

    final languageField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('ai-output-language-field')),
    );
    expect(languageField.controller?.text, 'en-US');
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('ai-output-language-en-US')),
          )
          .selected,
      isTrue,
    );

    await _tapSave(tester);
    await tester.pump();

    expect(submittedSettings?.outputLanguage, 'en-US');
  });

  testWidgets('AI settings form explains missing API key impact', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: false, apiKeyMasked: null),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    expect(find.text('缺少 API Key'), findsOneWidget);
    expect(find.text('自动摘要或翻译已开启，但没有可用 Key；后续文章会跳过 AI 处理。'), findsOneWidget);

    final notice = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('ai-readiness-notice')),
    );
    expect(notice.properties.label, contains('AI 就绪状态，缺少 API Key'));
  });

  testWidgets('AI settings form updates readiness while replacing key', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: false, apiKeyMasked: null),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-api-key-field')),
      'sk-new',
    );
    await tester.pump();

    expect(find.text('新 API Key 将在保存后生效'), findsOneWidget);
    expect(find.text('缺少 API Key'), findsNothing);
  });

  testWidgets('AI settings form shows the current masked API key', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    expect(
      find.text('后续文章会按当前开关自动生成摘要或双语翻译。 当前 Key：sk-***key。'),
      findsOneWidget,
    );

    final notice = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('ai-readiness-notice')),
    );
    expect(notice.properties.label, contains('当前 Key：sk-***key'));
  });

  testWidgets('AI settings form hides old masked key while replacing key', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-api-key-field')),
      'sk-new',
    );
    await tester.pump();

    expect(find.text('新 API Key 将在保存后生效'), findsOneWidget);
    expect(find.textContaining('当前 Key：sk-***key'), findsNothing);
  });

  testWidgets('AI settings form warns before clearing key', (tester) async {
    await _pumpForm(
      tester,
      settings: _settings(configured: true, apiKeyMasked: 'sk-***key'),
      onSave: (_, {rawApiKey, required clearApiKey}) async {},
    );

    await tester.tap(find.byKey(const ValueKey<String>('ai-clear-api-key')));
    await tester.pump();

    expect(find.text('保存后会暂停自动 AI 处理'), findsOneWidget);
    expect(
      find.text('你正在清除 API Key，后续文章会跳过去噪、摘要和翻译，直到重新配置 Key。'),
      findsOneWidget,
    );
  });
}

const _unset = Object();

Future<void> _tapSave(WidgetTester tester) async {
  final saveButton = find.byKey(const ValueKey<String>('ai-settings-save'));
  await tester.scrollUntilVisible(
    saveButton,
    500,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(saveButton);
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required AiSettings settings,
  required AiSettingsSaveCallback onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 900,
          child: AiSettingsForm(
            settings: settings,
            busy: false,
            onSave: onSave,
          ),
        ),
      ),
    ),
  );
}

AiSettings _settings({required bool configured, String? apiKeyMasked}) {
  return AiSettings(
    provider: 'DEEPSEEK',
    configured: configured,
    apiKeyMasked: apiKeyMasked,
    filterPrompt: 'Filter prompt',
    summaryPrompt: 'Summary prompt',
    translationPrompt: 'Translation prompt',
    autoSummaryEnabled: true,
    autoTranslationEnabled: true,
    outputLanguage: 'zh-CN',
  );
}
