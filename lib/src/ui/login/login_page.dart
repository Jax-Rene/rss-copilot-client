import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostic_redaction.dart';
import '../../data/api/api_exception.dart';
import '../../state/providers.dart';

const _demoEmail = 'demo@rsscopilot.local';
const _demoPassword = 'changeme123';
const _configuredDefaultBaseUrl = String.fromEnvironment(
  'RSS_COPILOT_DEFAULT_BASE_URL',
);
const _configuredDefaultEmail = String.fromEnvironment(
  'RSS_COPILOT_DEFAULT_EMAIL',
);
const _configuredDefaultPassword = String.fromEnvironment(
  'RSS_COPILOT_DEFAULT_PASSWORD',
);

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({
    super.key,
    this.initialBaseUrl,
    this.initialEmail,
    this.initialPassword,
  });

  final String? initialBaseUrl;
  final String? initialEmail;
  final String? initialPassword;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final defaultBaseUrl = _defaultLoginBaseUrl(
      initialBaseUrl: widget.initialBaseUrl,
    );
    _baseUrlController = TextEditingController(text: defaultBaseUrl);
    _emailController = TextEditingController(
      text: _initialLoginEmail(initialEmail: widget.initialEmail),
    );
    _passwordController = TextEditingController(
      text: _initialLoginPassword(initialPassword: widget.initialPassword),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await ref
          .read(appControllerProvider)
          .login(
            baseUrl: _normalizeServerBaseUrl(_baseUrlController.text),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(_loginErrorMessage(error))));
    }
  }

  void _fillDemoCredentials() {
    setState(() {
      _emailController.text = _credentialFillEmail(
        initialEmail: widget.initialEmail,
      );
      _passwordController.text = _credentialFillPassword(
        initialEmail: widget.initialEmail,
        initialPassword: widget.initialPassword,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider).state;
    final theme = Theme.of(context);
    final credentialLabel = _credentialFillEmail(
      initialEmail: widget.initialEmail,
    );
    final credentialPassword = _credentialFillPassword(
      initialEmail: widget.initialEmail,
      initialPassword: widget.initialPassword,
    );
    final credentialLabelPrefix = credentialPassword.isEmpty
        ? '本地登录账号'
        : '本地演示账号';
    final credentialButtonLabel = credentialPassword.isEmpty ? '填入邮箱' : '填入';

    return Scaffold(
      body: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'RSS Copilot',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '登录到你的 RSS Copilot 服务端。',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              key: const ValueKey<String>(
                                'login-base-url-field',
                              ),
                              controller: _baseUrlController,
                              decoration: const InputDecoration(
                                labelText: '服务端地址',
                                hintText:
                                    'localhost:8080 或 https://reader.example.com',
                              ),
                              validator: _validateServerBaseUrl,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey<String>('login-email-field'),
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: '邮箱',
                              ),
                              validator: (value) =>
                                  (value ?? '').trim().isEmpty ? '请输入邮箱' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey<String>(
                                'login-password-field',
                              ),
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: '密码',
                                suffixIcon: IconButton(
                                  key: const ValueKey<String>(
                                    'login-password-visibility',
                                  ),
                                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  (value ?? '').isEmpty ? '请输入密码' : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_add_alt_1_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '$credentialLabelPrefix：$credentialLabel',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey<String>(
                                        'login-fill-demo-credentials',
                                      ),
                                      onPressed: state.busy
                                          ? null
                                          : _fillDemoCredentials,
                                      child: Text(credentialButtonLabel),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (state.errorMessage != null) ...[
                              Text(
                                state.errorMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            FilledButton.icon(
                              key: const ValueKey<String>('login-submit'),
                              onPressed: state.busy ? null : _submit,
                              icon: state.busy
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(state.busy ? '登录中...' : '登录并初始化'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _defaultLoginBaseUrl({String? initialBaseUrl}) {
  final explicitBaseUrl = initialBaseUrl?.trim();
  if (explicitBaseUrl != null && explicitBaseUrl.isNotEmpty) {
    return _normalizeServerBaseUrl(explicitBaseUrl);
  }
  if (_configuredDefaultBaseUrl.trim().isNotEmpty) {
    return _normalizeServerBaseUrl(_configuredDefaultBaseUrl);
  }
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8080'
      : 'http://localhost:8080';
}

String _initialLoginEmail({String? initialEmail}) {
  final explicitEmail = initialEmail?.trim();
  if (explicitEmail != null && explicitEmail.isNotEmpty) {
    return explicitEmail;
  }
  if (_configuredDefaultEmail.trim().isNotEmpty) {
    return _configuredDefaultEmail.trim();
  }
  return '';
}

String _initialLoginPassword({String? initialPassword}) {
  if (initialPassword != null && initialPassword.isNotEmpty) {
    return initialPassword;
  }
  if (_configuredDefaultPassword.isNotEmpty) {
    return _configuredDefaultPassword;
  }
  return '';
}

String _credentialFillEmail({String? initialEmail}) {
  final explicitEmail = initialEmail?.trim();
  if (explicitEmail != null && explicitEmail.isNotEmpty) {
    return explicitEmail;
  }
  if (_configuredDefaultEmail.trim().isNotEmpty) {
    return _configuredDefaultEmail.trim();
  }
  return _demoEmail;
}

String _credentialFillPassword({
  String? initialEmail,
  String? initialPassword,
}) {
  if (initialPassword != null && initialPassword.isNotEmpty) {
    return initialPassword;
  }
  if (_configuredDefaultPassword.isNotEmpty) {
    return _configuredDefaultPassword;
  }
  final email = _credentialFillEmail(initialEmail: initialEmail);
  if (email != _demoEmail) {
    return '';
  }
  return _demoPassword;
}

String? _validateServerBaseUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return '请输入服务端地址';
  }

  final uri = Uri.tryParse(_applyDefaultServerBaseUrlScheme(trimmed));
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (scheme != 'http' && scheme != 'https')) {
    return '请输入有效服务端地址，支持 http/https 或省略协议';
  }
  if ((uri.hasQuery || uri.hasFragment) && !_hasApiPathSegment(uri)) {
    return '服务端地址不能包含查询参数或片段';
  }
  return null;
}

String _normalizeServerBaseUrl(String value) {
  final withScheme = _applyDefaultServerBaseUrlScheme(value.trim());
  final uri = Uri.tryParse(withScheme.replaceFirst(RegExp(r'/+$'), ''));
  if (uri == null || !uri.hasAuthority) {
    return withScheme.replaceFirst(RegExp(r'/+$'), '');
  }
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final apiIndex = segments.lastIndexWhere(
    (segment) => segment.toLowerCase() == 'api',
  );
  final normalizedUri = apiIndex < 0
      ? _serverBaseUri(uri)
      : _serverBaseUri(
          uri,
          pathSegments: segments.take(apiIndex).toList(growable: false),
        );
  return normalizedUri.toString().replaceFirst(RegExp(r'/+$'), '');
}

Uri _serverBaseUri(Uri uri, {List<String>? pathSegments}) {
  return Uri(
    scheme: uri.scheme,
    userInfo: '',
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: pathSegments ?? uri.pathSegments,
  );
}

bool _hasApiPathSegment(Uri uri) {
  return uri.pathSegments.any((segment) => segment.toLowerCase() == 'api');
}

String _applyDefaultServerBaseUrlScheme(String value) {
  if (value.contains('://')) {
    return value;
  }
  final host = _serverBaseUrlHost(value);
  if (!_looksLikeServerBaseUrlHost(host)) {
    return value;
  }
  return '${_defaultServerBaseUrlScheme(host)}://$value';
}

String _serverBaseUrlHost(String value) {
  var endIndex = value.length;
  for (final delimiter in ['/', '?', '#']) {
    final delimiterIndex = value.indexOf(delimiter);
    if (delimiterIndex >= 0 && delimiterIndex < endIndex) {
      endIndex = delimiterIndex;
    }
  }
  var authority = value.substring(0, endIndex);
  final userInfoIndex = authority.lastIndexOf('@');
  if (userInfoIndex >= 0) {
    authority = authority.substring(userInfoIndex + 1);
  }
  if (authority.startsWith('[')) {
    final bracketIndex = authority.indexOf(']');
    return bracketIndex > 0 ? authority.substring(1, bracketIndex) : authority;
  }
  final firstColonIndex = authority.indexOf(':');
  if (firstColonIndex >= 0 && firstColonIndex == authority.lastIndexOf(':')) {
    return authority.substring(0, firstColonIndex);
  }
  return authority;
}

bool _looksLikeServerBaseUrlHost(String host) {
  final normalizedHost = host.toLowerCase();
  return normalizedHost == 'localhost' ||
      normalizedHost.contains('.') ||
      normalizedHost.contains(':');
}

String _defaultServerBaseUrlScheme(String host) {
  return _isLocalServerBaseUrlHost(host) ? 'http' : 'https';
}

bool _isLocalServerBaseUrlHost(String host) {
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost' ||
      normalizedHost == '127.0.0.1' ||
      normalizedHost == '::1') {
    return true;
  }
  if (normalizedHost.startsWith('10.') ||
      normalizedHost.startsWith('192.168.')) {
    return true;
  }
  if (!normalizedHost.startsWith('172.')) {
    return false;
  }
  final parts = normalizedHost.split('.');
  if (parts.length < 2) {
    return false;
  }
  final secondOctet = int.tryParse(parts[1]);
  return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
}

String _loginErrorMessage(Object error) {
  if (error is ServerHealthException) {
    return '服务端检查失败：${redactDiagnosticText(error.message, emptyPlaceholder: '')}';
  }
  if (error is ApiException) {
    if (error.isUnauthorized) {
      return '登录失败：邮箱或密码不正确';
    }
    if (error.isBadRequest) {
      return '登录失败：请求内容不完整，请检查邮箱、密码和服务端地址';
    }
    if (error.statusCode == 403 || error.code == 'FORBIDDEN') {
      return '登录失败：账号暂不可用，请检查服务端用户配置';
    }
    if (error.statusCode >= 500) {
      return '登录失败：服务端暂时不可用，请稍后重试';
    }
    return '登录失败：服务端返回异常，请稍后重试';
  }
  if (error is TimeoutException) {
    return '登录失败：连接服务端超时，请稍后重试';
  }
  if (error is NetworkException) {
    return '登录失败：无法连接服务端，请确认服务端已启动并且地址正确';
  }
  return '登录失败：请稍后重试';
}
