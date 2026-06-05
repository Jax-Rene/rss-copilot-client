import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/data/api/api_exception.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';
import 'package:rss_copilot_client/src/repositories/rss_repository.dart';
import 'package:rss_copilot_client/src/state/app_controller.dart';
import 'package:rss_copilot_client/src/state/providers.dart';
import 'package:rss_copilot_client/src/ui/login/login_page.dart';

void main() {
  testWidgets('login form blocks non HTTP server URL before submit', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      'ftp://reader.example',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(find.text('请输入有效服务端地址，支持 http/https 或省略协议'), findsOneWidget);
    expect(fixture.repository.loginRequests, isEmpty);
  });

  testWidgets('login form hints scheme-less server URL support', (
    tester,
  ) async {
    await _pumpLoginPage(tester);

    expect(
      find.text('localhost:8080 或 https://reader.example.com'),
      findsOneWidget,
    );
  });

  testWidgets('login form pre-fills configured local preview server URL', (
    tester,
  ) async {
    await _pumpLoginPage(
      tester,
      initialBaseUrl: ' http://127.0.0.1:18080/api/health ',
      initialEmail: 'demo@rsscopilot.local',
      initialPassword: 'changeme123',
    );

    final baseUrlField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('login-base-url-field')),
    );
    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('login-email-field')),
    );
    final passwordField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('login-password-field')),
    );
    expect(baseUrlField.controller!.text, 'http://127.0.0.1:18080');
    expect(emailField.controller!.text, 'demo@rsscopilot.local');
    expect(passwordField.controller!.text, 'changeme123');
  });

  testWidgets('login form can fill local demo credentials', (tester) async {
    final fixture = await _pumpLoginPage(tester);

    expect(find.text('本地演示账号：demo@rsscopilot.local'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('login-fill-demo-credentials')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.email,
      'demo@rsscopilot.local',
    );
    expect(fixture.repository.loginRequests.single.password, 'changeme123');
  });

  testWidgets('login form avoids filling a password for custom local account', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(
      tester,
      initialEmail: 'you@example.com',
    );

    expect(find.text('本地登录账号：you@example.com'), findsOneWidget);
    expect(find.text('填入邮箱'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('login-fill-demo-credentials')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, isEmpty);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets('login form stays scrollable on compact screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLoginPage(tester);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('login-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login form trims API server URL before submit', (tester) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      ' http://localhost:8080/api/ ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      ' demo@rsscopilot.local ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'http://localhost:8080',
    );
    expect(
      fixture.repository.loginRequests.single.email,
      'demo@rsscopilot.local',
    );
    expect(fixture.repository.loginRequests.single.password, 'changeme123');
  });

  testWidgets('login form accepts copied health endpoint URL', (tester) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      ' https://reader.example.com/rss/api/health ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'https://reader.example.com/rss',
    );
  });

  testWidgets('login form strips URL credentials before submit', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      ' https://user:secret@reader.example.com/rss/api/health ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'https://reader.example.com/rss',
    );
  });

  testWidgets('login form accepts copied API URL with query and fragment', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      ' https://reader.example.com/rss/api/health?from=proxy#status ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'https://reader.example.com/rss',
    );
  });

  testWidgets('login form still rejects non API server URL query params', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      'https://reader.example.com/rss?from=proxy',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(find.text('服务端地址不能包含查询参数或片段'), findsOneWidget);
    expect(fixture.repository.loginRequests, isEmpty);
  });

  testWidgets('login form accepts scheme-less local server URL', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      'localhost:8080',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'http://localhost:8080',
    );
  });

  testWidgets('login form defaults scheme-less LAN server URL to HTTP', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      '192.168.1.10:8080',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'http://192.168.1.10:8080',
    );
  });

  testWidgets(
    'login form defaults scheme-less private 172 server URL to HTTP',
    (tester) async {
      final fixture = await _pumpLoginPage(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('login-base-url-field')),
        '172.20.1.10:8080',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login-email-field')),
        'demo@rsscopilot.local',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login-password-field')),
        'changeme123',
      );
      await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
      await tester.pump();

      expect(fixture.repository.loginRequests, hasLength(1));
      expect(
        fixture.repository.loginRequests.single.baseUrl,
        'http://172.20.1.10:8080',
      );
    },
  );

  testWidgets('login form defaults scheme-less remote server URL to HTTPS', (
    tester,
  ) async {
    final fixture = await _pumpLoginPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('login-base-url-field')),
      'reader.example.com/rss',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-email-field')),
      'demo@rsscopilot.local',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login-password-field')),
      'changeme123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
    await tester.pump();

    expect(fixture.repository.loginRequests, hasLength(1));
    expect(
      fixture.repository.loginRequests.single.baseUrl,
      'https://reader.example.com/rss',
    );
  });

  testWidgets('login form can toggle password visibility', (tester) async {
    await _pumpLoginPage(tester);

    EditableText passwordEditableText() {
      return tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('login-password-field')),
          matching: find.byType(EditableText),
        ),
      );
    }

    expect(passwordEditableText().obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('login-password-visibility')),
    );
    await tester.pump();

    expect(passwordEditableText().obscureText, isFalse);
    expect(find.byTooltip('隐藏密码'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('login-password-visibility')),
    );
    await tester.pump();

    expect(passwordEditableText().obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);
  });

  testWidgets(
    'login form shows credential error without debug exception text',
    (tester) async {
      await _pumpLoginPage(
        tester,
        loginError: const ApiException(
          statusCode: 401,
          code: 'UNAUTHORIZED',
          message: 'invalid credentials',
        ),
      );

      await _submitValidLogin(tester);

      expect(find.text('登录失败：邮箱或密码不正确'), findsOneWidget);
      expect(find.textContaining('ApiException('), findsNothing);
    },
  );

  testWidgets('login form explains malformed login requests', (tester) async {
    await _pumpLoginPage(
      tester,
      loginError: const ApiException(
        statusCode: 400,
        code: 'BAD_REQUEST',
        message: 'request body is invalid',
      ),
    );

    await _submitValidLogin(tester);

    expect(find.text('登录失败：请求内容不完整，请检查邮箱、密码和服务端地址'), findsOneWidget);
    expect(find.text('request body is invalid'), findsNothing);
  });

  testWidgets('login form explains temporary server failures', (tester) async {
    await _pumpLoginPage(
      tester,
      loginError: const ApiException(
        statusCode: 500,
        code: 'INTERNAL_SERVER_ERROR',
        message: 'database is locked',
      ),
    );

    await _submitValidLogin(tester);

    expect(find.text('登录失败：服务端暂时不可用，请稍后重试'), findsOneWidget);
    expect(find.text('database is locked'), findsNothing);
  });

  testWidgets('login form shows network error without debug exception text', (
    tester,
  ) async {
    await _pumpLoginPage(
      tester,
      loginError: const NetworkException('Connection refused'),
    );

    await _submitValidLogin(tester);

    expect(find.text('登录失败：无法连接服务端，请确认服务端已启动并且地址正确'), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsNothing);
    expect(find.textContaining('NetworkException'), findsNothing);
  });

  testWidgets('login form shows timeout error without debug exception text', (
    tester,
  ) async {
    await _pumpLoginPage(tester, loginError: TimeoutException('slow'));

    await _submitValidLogin(tester);

    expect(find.text('登录失败：连接服务端超时，请稍后重试'), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });

  testWidgets('login form shows server health check failure clearly', (
    tester,
  ) async {
    await _pumpLoginPage(
      tester,
      loginError: const ServerHealthException(
        '未检测到 RSS Copilot 健康检查接口，请确认服务端已更新并且地址正确',
      ),
    );

    await _submitValidLogin(tester);

    expect(
      find.text('服务端检查失败：未检测到 RSS Copilot 健康检查接口，请确认服务端已更新并且地址正确'),
      findsOneWidget,
    );
    expect(find.textContaining('ServerHealthException'), findsNothing);
  });

  testWidgets('login form redacts sensitive server health failure details', (
    tester,
  ) async {
    await _pumpLoginPage(
      tester,
      loginError: const ServerHealthException(
        '健康检查失败：https://user:secret@reader.example/api/health?api_key=raw-key '
        'Authorization: Bearer header.jwt X-API-Key: header-key password: header-pass '
        'Cookie: session=raw-session; theme=dark Set-Cookie: refresh=raw-refresh sk-login123456',
      ),
    );

    await _submitValidLogin(tester);

    expect(
      find.textContaining(
        '服务端检查失败：健康检查失败：https://redacted@reader.example/api/health?',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('[redacted]'), findsOneWidget);
    expect(find.textContaining('user:secret'), findsNothing);
    expect(find.textContaining('raw-key'), findsNothing);
    expect(find.textContaining('header.jwt'), findsNothing);
    expect(find.textContaining('header-key'), findsNothing);
    expect(find.textContaining('header-pass'), findsNothing);
    expect(find.textContaining('raw-session'), findsNothing);
    expect(find.textContaining('raw-refresh'), findsNothing);
    expect(find.textContaining('sk-login'), findsNothing);
  });
}

Future<_LoginFixture> _pumpLoginPage(
  WidgetTester tester, {
  Object? loginError,
  String? initialBaseUrl,
  String? initialEmail,
  String? initialPassword,
}) async {
  final store = await LocalStore.inMemory();
  final repository = _RecordingLoginRepository(store, loginError: loginError);
  final controller = AppController(repository: repository);
  addTearDown(() async {
    controller.dispose();
    await store.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        home: LoginPage(
          initialBaseUrl: initialBaseUrl,
          initialEmail: initialEmail,
          initialPassword: initialPassword,
        ),
      ),
    ),
  );
  await tester.pump();

  return _LoginFixture(repository);
}

Future<void> _submitValidLogin(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('login-base-url-field')),
    'http://localhost:8080',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('login-email-field')),
    'demo@rsscopilot.local',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('login-password-field')),
    'changeme123',
  );
  await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
  await tester.pump();
}

class _LoginFixture {
  const _LoginFixture(this.repository);

  final _RecordingLoginRepository repository;
}

class _RecordingLoginRepository extends RssRepository {
  _RecordingLoginRepository(LocalStore store, {Object? loginError})
    : _loginError = loginError,
      super(store: store);

  final List<({String baseUrl, String email, String password})> loginRequests =
      <({String baseUrl, String email, String password})>[];
  final Object? _loginError;

  @override
  Future<SessionData> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    loginRequests.add((baseUrl: baseUrl, email: email, password: password));
    throw _loginError ?? StateError('stop after recording login request');
  }
}
