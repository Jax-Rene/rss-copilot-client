import 'package:flutter/material.dart';

import '../../../models/settings_bundle.dart';

class AiSettingsForm extends StatefulWidget {
  const AiSettingsForm({
    super.key,
    required this.settings,
    required this.busy,
    required this.onSave,
  });

  final AiSettings settings;
  final bool busy;
  final Future<void> Function(AiSettings settings, String? rawApiKey) onSave;

  @override
  State<AiSettingsForm> createState() => _AiSettingsFormState();
}

class _AiSettingsFormState extends State<AiSettingsForm> {
  late final TextEditingController _providerController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _filterPromptController;
  late final TextEditingController _summaryPromptController;
  late final TextEditingController _translationPromptController;
  late final TextEditingController _outputLanguageController;
  late bool _autoSummaryEnabled;
  late bool _autoTranslationEnabled;

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
  }

  Future<void> _save() async {
    final nextSettings = widget.settings.copyWith(
      provider: _providerController.text.trim().toUpperCase(),
      filterPrompt: _filterPromptController.text.trim(),
      summaryPrompt: _summaryPromptController.text.trim(),
      translationPrompt: _translationPromptController.text.trim(),
      autoSummaryEnabled: _autoSummaryEnabled,
      autoTranslationEnabled: _autoTranslationEnabled,
      outputLanguage: _outputLanguageController.text.trim(),
    );

    final rawApiKey = _apiKeyController.text.trim().isEmpty
        ? null
        : _apiKeyController.text.trim();
    await widget.onSave(nextSettings, rawApiKey);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'AI',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '当前服务端开放了 AI 设置更新接口，客户端直接按接口文档保存。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _providerController,
          decoration: const InputDecoration(labelText: 'Provider'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: widget.settings.apiKeyMasked ?? '输入后会覆盖现有 Key',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _outputLanguageController,
          decoration: const InputDecoration(labelText: '输出语言'),
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
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
        SwitchListTile.adaptive(
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
        const SizedBox(height: 16),
        TextFormField(
          controller: _filterPromptController,
          decoration: const InputDecoration(labelText: '去噪 Prompt'),
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _summaryPromptController,
          decoration: const InputDecoration(labelText: '摘要 Prompt'),
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _translationPromptController,
          decoration: const InputDecoration(labelText: '翻译 Prompt'),
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: widget.busy ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(widget.busy ? '保存中...' : '保存 AI 设置'),
        ),
      ],
    );
  }
}
