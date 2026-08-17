import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/debug/runtime_diagnostics_overlay.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_messaging_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/ops/ops_monitor_service.dart';

class KYoutubeBootstrapApp extends StatefulWidget {
  const KYoutubeBootstrapApp({super.key});

  @override
  State<KYoutubeBootstrapApp> createState() => _KYoutubeBootstrapAppState();
}

class _KYoutubeBootstrapAppState extends State<KYoutubeBootstrapApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await OpsMonitorService.markPhase('Firebase 초기화');
      await FirebaseBootstrap.initialize();

      await OpsMonitorService.markPhase('FCM 초기화');
      await FirebaseMessagingService.initialize();

      await OpsMonitorService.markPhase('Supabase 초기화');
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
      );

      await OpsMonitorService.markReady();
    } catch (error, stackTrace) {
      await OpsMonitorService.markStartupFailure(
        error: error,
        stackTrace: stackTrace,
        phase: OpsMonitorService.state.value.phase,
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _initialization = _initializeApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            builder: (BuildContext context, Widget? child) {
              return RuntimeDiagnosticsOverlay(
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _BootstrapLoadingScreen(),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            builder: (BuildContext context, Widget? child) {
              return RuntimeDiagnosticsOverlay(
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: _BootstrapErrorScreen(
              error: snapshot.error.toString(),
              onRetry: _retry,
            ),
          );
        }

        return const KYoutubeApp();
      },
    );
  }
}

class KYoutubeApp extends StatefulWidget {
  const KYoutubeApp({super.key});

  @override
  State<KYoutubeApp> createState() => _KYoutubeAppState();
}

class _KYoutubeAppState extends State<KYoutubeApp> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    // 실제 앱에서는 Supabase 초기화 이후 실행됩니다.
    // Widget Test에서는 Supabase가 초기화되지 않을 수 있으므로 안전하게 무시합니다.
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          AppRouter.router.go(AppRoutes.resetPassword);
        }
      });
    } catch (_) {
      _authSubscription = null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'playscout',
      theme: AppTheme.light,
      routerConfig: AppRouter.router,
      builder: (BuildContext context, Widget? child) {
        return RuntimeDiagnosticsOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('앱을 준비하는 중입니다...'),
          ],
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '앱 시작에 실패했습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (BuildContext context, Widget? child) {
        return RuntimeDiagnosticsOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
