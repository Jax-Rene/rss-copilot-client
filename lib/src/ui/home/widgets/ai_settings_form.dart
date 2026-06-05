import 'package:flutter/material.dart';

import '../../../core/language_tag.dart';
import '../../../models/settings_bundle.dart';

typedef AiSettingsSaveCallback =
    Future<void> Function(
      AiSettings settings, {
      String? rawApiKey,
      required bool clearApiKey,
    });

class AiSettingsForm extends StatefulWidget {
  const AiSettingsForm({
    super.key,
    required this.settings,
    required this.busy,
    required this.onSave,
  });

  final AiSettings settings;
  final bool busy;
  final AiSettingsSaveCallback onSave;

  @override
  State<AiSettingsForm> createState() => _AiSettingsFormState();
}

class _AiSettingsFormState extends State<AiSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _providerController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _filterPromptController;
  late final TextEditingController _summaryPromptController;
  late final TextEditingController _translationPromptController;
  late final TextEditingController _outputLanguageController;
  late bool _autoSummaryEnabled;
  late bool _autoTranslationEnabled;
  late bool _clearApiKey;
  bool _autoValidate = false;

  @override
  void initState() {
    super.initState();
    _providerController = TextEditingController();
    _apiKeyController = TextEditingController();
    _filterPromptController = TextEditingController();
    _summaryPromptController = TextEditingController();
    _translationPromptController = TextEditingController();
    _outputLanguageController = TextEditingController();
    _apply(widget.settings);
  }

  @override
  void didUpdateWidget(covariant AiSettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _apply(widget.settings);
    }
  }

  @override
  void dispose() {
    _providerController.dispose();
    _apiKeyController.dispose();
    _filterPromptController.dispose();
    _summaryPromptController.dispose();
    _translationPromptController.dispose();
    _outputLanguageController.dispose();
    super.dispose();
  }

  void _apply(AiSettings settings) {
    _providerController.text = settings.provider;
    _apiKeyController.clear();
    _filterPromptController.text = settings.filterPrompt;
    _summaryPromptController.text = settings.summaryPrompt;
    _translationPromptController.text = settings.translationPrompt;
    _outputLanguageController.text = settings.outputLanguage;
    _autoSummaryEnabled = settings.autoSummaryEnabled;
    _autoTranslationEnabled = settings.autoTranslationEnabled;
    _clearApiKey = false;
    _autoValidate = false;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {
        _autoValidate = true;
      });
      return;
    }

    final nextSettings = widget.settings.copyWith(
      provider: _providerController.text.trim().toUpperCase(),
      filterPrompt: _filterPromptController.text.trim(),
      summaryPrompt: _summaryPromptController.text.trim(),
      translationPrompt: _translationPromptController.text.trim(),
      autoSummaryEnabled: _autoSummaryEnabled,
      autoTranslationEnabled: _autoTranslationEnabled,
      outputLanguage: normalizeLanguageTag(_outputLanguageController.text),
    );

    final normalizedApiKey = _apiKeyController.text.trim();
    final rawApiKey = _clearApiKey || normalizedApiKey.isEmpty
        ? null
        : normalizedApiKey;
    await widget.onSave(
      nextSettings,
      rawApiKey: rawApiKey,
      clearApiKey: _clearApiKey && rawApiKey == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExistingApiKey =
        widget.settings.configured || widget.settings.apiKeyMasked != null;
    final hasPendingApiKey = _apiKeyController.text.trim().isNotEmpty;
    final hasEffectiveApiKey =
        !_clearApiKey && (hasPendingApiKey || hasExistingApiKey);
    return Form(
      key: _formKey,
      autovalidateMode: _autoValidate
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'AI',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '配置 DeepSeek Key、自动处理开关和提示词，保存后会应用到后续文章处理。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _AiReadinessNotice(
                hasEffectiveApiKey: hasEffectiveApiKey,
                hasPendingApiKey: hasPendingApiKey,
                apiKeyMasked: widget.settings.apiKeyMasked,
                clearApiKey: _clearApiKey,
                autoSummaryEnabled: _autoSummaryEnabled,
                autoTranslationEnabled: _autoTranslationEnabled,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-provider-field'),
                controller: _providerController,
                decoration: const InputDecoration(
                  labelText: 'Provider',
                  helperText: '当前仅支持 DeepSeek，后续服务端支持新 Provider 后会开放选择。',
                  suffixIcon: Icon(Icons.lock_outline_rounded),
                ),
                readOnly: true,
                textInputAction: TextInputAction.next,
                validator: _validateProvider,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-api-key-field'),
                controller: _apiKeyController,
                enabled: !widget.busy && !_clearApiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: widget.settings.apiKeyMasked == null
                      ? '输入后保存'
                      : '${widget.settings.apiKeyMasked}，留空会保留现有 Key',
                ),
                onChanged: (value) {
                  setState(() {
                    if (value.trim().isNotEmpty && _clearApiKey) {
                      _clearApiKey = false;
                    }
                  });
                },
              ),
              if (hasExistingApiKey) ...[
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    key: const ValueKey<String>('ai-clear-api-key'),
                    contentPadding: EdgeInsets.zero,
                    value: _clearApiKey,
                    title: const Text('清除现有 API Key'),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: widget.busy
                        ? null
                        : (value) {
                            setState(() {
                              _clearApiKey = value ?? false;
                              if (_clearApiKey) {
                                _apiKeyController.clear();
                              }
                            });
                          },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-output-language-field'),
                controller: _outputLanguageController,
                decoration: const InputDecoration(
                  labelText: '输出语言',
                  hintText: 'zh-CN',
                  helperText: '使用 zh-CN、en-US、ja-JP 这类语言标签',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => validateLanguageTag(value, '输出语言'),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _outputLanguageController,
                builder: (context, value, child) {
                  final selectedLanguage = normalizedLanguageTagOrNull(
                    value.text,
                  );
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickOutputLanguages
                        .map(
                          (option) => ChoiceChip(
                            key: ValueKey<String>(
                              'ai-output-language-${option.value}',
                            ),
                            label: Text(option.label),
                            tooltip: '设置输出语言为 ${option.value}',
                            selected: selectedLanguage == option.value,
                            onSelected: widget.busy
                                ? null
                                : (_) {
                                    _outputLanguageController.text =
                                        option.value;
                                  },
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  value: _autoSummaryEnabled,
                  title: const Text('自动生成摘要'),
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          setState(() {
                            _autoSummaryEnabled = value;
                          });
                        },
                ),
              ),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  value: _autoTranslationEnabled,
                  title: const Text('自动生成翻译'),
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          setState(() {
                            _autoTranslationEnabled = value;
                          });
                        },
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-filter-prompt-field'),
                controller: _filterPromptController,
                decoration: const InputDecoration(labelText: '去噪 Prompt'),
                minLines: 3,
                maxLines: 6,
                validator: (value) => _requiredField(value, '去噪 Prompt'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-summary-prompt-field'),
                controller: _summaryPromptController,
                decoration: const InputDecoration(labelText: '摘要 Prompt'),
                minLines: 3,
                maxLines: 6,
                validator: (value) => _requiredField(value, '摘要 Prompt'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>('ai-translation-prompt-field'),
                controller: _translationPromptController,
                decoration: const InputDecoration(labelText: '翻译 Prompt'),
                minLines: 3,
                maxLines: 6,
                validator: (value) => _requiredField(value, '翻译 Prompt'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey<String>('ai-settings-save'),
                onPressed: widget.busy ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(widget.busy ? '保存中...' : '保存 AI 设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _quickOutputLanguages = [
  (value: 'zh-CN', label: '中文'),
  (value: 'en-US', label: 'English'),
  (value: 'ja-JP', label: '日本語'),
];

String? _validateProvider(String? value) {
  final requiredError = _requiredField(value, 'Provider');
  if (requiredError != null) {
    return requiredError;
  }
  if (value!.trim().toUpperCase() != 'DEEPSEEK') {
    return 'Provider 当前仅支持 DEEPSEEK';
  }
  return null;
}

class _AiReadinessNotice extends StatelessWidget {
  const _AiReadinessNotice({
    required this.hasEffectiveApiKey,
    required this.hasPendingApiKey,
    required this.apiKeyMasked,
    required this.clearApiKey,
    required this.autoSummaryEnabled,
    required this.autoTranslationEnabled,
  });

  final bool hasEffectiveApiKey;
  final bool hasPendingApiKey;
  final String? apiKeyMasked;
  final bool clearApiKey;
  final bool autoSummaryEnabled;
  final bool autoTranslationEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAutomaticAiWork = autoSummaryEnabled || autoTranslationEnabled;
    final (icon, title, message, color) = switch ((
      clearApiKey,
      hasEffectiveApiKey,
      hasAutomaticAiWork,
    )) {
      (true, _, true) => (
        Icons.warning_amber_rounded,
        '保存后会暂停自动 AI 处理',
        '你正在清除 API Key，后续文章会跳过去噪、摘要和翻译，直到重新配置 Key。',
        theme.colorScheme.error,
      ),
      (true, _, false) => (
        Icons.key_off_outlined,
        '保存后会清除 API Key',
        '当前已关闭自动摘要和翻译；清除 Key 后不会影响普通阅读。',
        theme.colorScheme.tertiary,
      ),
      (_, false, true) => (
        Icons.warning_amber_rounded,
        '缺少 API Key',
        '自动摘要或翻译已开启，但没有可用 Key；后续文章会跳过 AI 处理。',
        theme.colorScheme.error,
      ),
      (_, false, false) => (
        Icons.pause_circle_outline_rounded,
        '自动 AI 处理已关闭',
        '当前没有配置 Key，也未开启自动摘要或翻译；普通阅读不受影响。',
        theme.colorScheme.onSurfaceVariant,
      ),
      (_, true, false) => (
        Icons.pause_circle_outline_rounded,
        'AI Key 已就绪',
        '当前已关闭自动摘要和翻译；你仍可在单篇文章上手动重试 AI。',
        theme.colorScheme.tertiary,
      ),
      (_, true, true) => (
        Icons.check_circle_outline_rounded,
        hasPendingApiKey ? '新 API Key 将在保存后生效' : 'AI 自动处理已就绪',
        '后续文章会按当前开关自动生成摘要或双语翻译。',
        theme.colorScheme.primary,
      ),
    };

    final currentKeyDetail =
        !clearApiKey && !hasPendingApiKey && hasEffectiveApiKey
        ? _currentKeyDetail(apiKeyMasked)
        : '';
    final fullMessage = currentKeyDetail.isEmpty
        ? message
        : '$message $currentKeyDetail';

    return Semantics(
      key: const ValueKey<String>('ai-readiness-notice'),
      label: 'AI 就绪状态，$title，$fullMessage',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
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
                  const SizedBox(height: 3),
                  Text(
                    fullMessage,
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

String _currentKeyDetail(String? apiKeyMasked) {
  final masked = apiKeyMasked?.trim();
  if (masked == null || masked.isEmpty) {
    return '服务端已保存 Key。';
  }
  return '当前 Key：$masked。';
}

String? _requiredField(String? value, String label) {
  return value == null || value.trim().isEmpty ? '$label 不能为空' : null;
}
