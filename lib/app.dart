import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/app_theme.dart';
import 'src/state/providers.dart';
import 'src/ui/home/home_page.dart';
import 'src/ui/login/login_page.dart';

class RssCopilotApp extends ConsumerStatefulWidget {
  const RssCopilotApp({super.key});

  @override
  ConsumerState<RssCopilotApp> createState() => _RssCopilotAppState();
}

class _RssCopilotAppState extends ConsumerState<RssCopilotApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControllerProvider).initialize();
    });
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(appControllerProvider).handleAppResume();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final state = controller.state;

    return MaterialApp(
      title: 'RSS Copilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: state.effectiveThemeMode.toThemeMode(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: !state.initialized
            ? const _SplashScreen()
            : state.isAuthenticated
            ? const HomePage()
            : const LoginPage(),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F1C1F), Color(0xFF1F3B40)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'RSS Copilot 正在初始化',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
