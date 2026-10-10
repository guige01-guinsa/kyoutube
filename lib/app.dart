import 'core/auth/auth_return.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/oauth_deep_link_service.dart';
import 'core/config/env.dart';
import 'core/debug/runtime_diagnostics_overlay.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_messaging_service.dart';
import 'core/router/app_router.dart';
import 'core/router/app_exit_confirmation.dart';
import 'features/auth/application/account_service.dart';
import 'features/auth/application/auth_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/app_localizations.dart';
import 'core/ops/ops_monitor_service.dart';
import 'core/ops/ops_telemetry.dart';
import 'features/operations/data/ops_push_service.dart';

class KYoutubeBootstrapApp extends StatefulWidget {
  const KYoutubeBootstrapApp({super.key});

  @override
  State<KYoutubeBootstrapApp> createState() => _KYoutubeBootstrapAppState();
}

class _KYoutubeBootstrapAppState extends State<KYoutubeBootstrapApp> {
  late Future<void> _initialization;
  OAuthDeepLinkService? _oauthDeepLinkService;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Supabase는 로그인/레시피/계정 관리의 핵심 서비스이므로 먼저 초기화한다.
      await OpsMonitorService.markPhase('Supabase 초기화');
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
        ),
      );

      OpsMonitorService.telemetry =
          OpsTelemetry.forClient(Supabase.instance.client);
      _oauthDeepLinkService ??= OAuthDeepLinkService();
      await _oauthDeepLinkService!.start();

      // Firebase/FCM은 부가 기능이다.
      // 초기화 실패가 핵심 앱 기능의 시작을 막으면 안 된다.
      try {
        await OpsMonitorService.markPhase('Firebase 초기화');
        await FirebaseBootstrap.initialize()
            .timeout(const Duration(seconds: 8));

        await OpsMonitorService.markPhase('FCM 초기화');
        await FirebaseMessagingService.initialize()
            .timeout(const Duration(seconds: 8));
        OpsPushService.start();
      } catch (error, stackTrace) {
        OpsMonitorService.recordError(
          error,
          source: 'firebase_startup',
          stackTrace: stackTrace,
        );
      }

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

  @override
  void dispose() {
    _oauthDeepLinkService?.dispose();
    super.dispose();
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
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            localeResolutionCallback: (locale, supported) =>
                AppLocalizations.resolveLocale(locale),
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
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            localeResolutionCallback: (locale, supported) =>
                AppLocalizations.resolveLocale(locale),
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
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final _exitDispatcher =
      AppExitBackButtonDispatcher(confirmExit: _confirmExit);
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _confirmExit() async {
    final navigatorContext =
        AppRouter.router.routerDelegate.navigatorKey.currentContext;
    if (navigatorContext == null || !mounted) return;
    final container =
        ProviderScope.containerOf(navigatorContext, listen: false);
    await showAppExitConfirmation(navigatorContext,
        signedIn: container.read(activeAccountIdProvider) != null,
        signOut: () =>
            container.read(accountServiceProvider).signOutCurrentAccount(),
        exitApp: () => SystemNavigator.pop());
  }

  void _showOperationsAlert() {
    final english =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode != 'ko';
    _messenger.currentState?.showSnackBar(SnackBar(
        content: Text(
            english ? 'An operational status changed.' : '운영 상태가 변경되었습니다.'),
        action: SnackBarAction(
            label: english ? 'View' : '확인',
            onPressed: () => AppRouter.router.go(AppRoutes.operationsInbox))));
  }

  void _openOperationsAlert() {
    if (!OpsPushService.openRequested.value) return;
    OpsPushService.openRequested.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppRouter.router.go(AppRoutes.operationsInbox);
    });
  }

  @override
  void initState() {
    super.initState();

    // 실제 앱에서는 Supabase 초기화 이후 실행됩니다.
    OpsPushService.openRequested.addListener(_openOperationsAlert);
    OpsPushService.received.addListener(_showOperationsAlert);
    _openOperationsAlert();
    // Widget Test에서는 Supabase가 초기화되지 않을 수 있으므로 안전하게 무시합니다.
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        switch (data.event) {
          case AuthChangeEvent.passwordRecovery:
            AppRouter.router.go(AppRoutes.resetPassword);
            break;
          case AuthChangeEvent.signedOut:
            AppRouter.router.go(AppRoutes.workspace);
            break;
          case AuthChangeEvent.signedIn:
            final router = AppRouter.router;
            final before = router.routeInformationProvider.value.uri;
            if (before.path == '/account/mfa') return;
            final saved = await AuthReturnStore.take();
            if (!mounted) return;
            final current = router.routeInformationProvider.value.uri;
            if (current != before) return;
            final target = (current.path == '/login'
                    ? safeAuthReturn(current.queryParameters['returnTo'])
                    : null) ??
                saved;
            if (current.path == '/login' &&
                current.queryParameters['resume'] == '1' &&
                router.canPop() &&
                (current.queryParameters['account'] == null ||
                    current.queryParameters['account'] ==
                        data.session?.user.id)) {
              router.pop(true);
            } else if (target != null || current.path == '/login') {
              router.go(target ?? AppRoutes.workspace);
            }
            break;
          default:
            break;
        }
      });
    } catch (_) {
      _authSubscription = null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    OpsPushService.openRequested.removeListener(_openOperationsAlert);
    OpsPushService.received.removeListener(_showOperationsAlert);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: AppTheme.light,
      routeInformationProvider: AppRouter.router.routeInformationProvider,
      routeInformationParser: AppRouter.router.routeInformationParser,
      routerDelegate: AppRouter.router.routerDelegate,
      backButtonDispatcher:
          _android ? _exitDispatcher : AppRouter.router.backButtonDispatcher,
      // Android must send root back gestures to Flutter before closing the
      // activity, including when predictive back would otherwise exit directly.
      onNavigationNotification: _android
          ? (_) {
              unawaited(SystemNavigator.setFrameworkHandlesBack(true));
              return true;
            }
          : null,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          AppLocalizations.resolveLocale(locale),
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
            LocalizedText('앱을 준비하는 중입니다...'),
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
                  const LocalizedText(
                    '앱 시작에 실패했습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LocalizedText(
                    error,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const LocalizedText('다시 시도'),
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
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          AppLocalizations.resolveLocale(locale),
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
                    LocalizedText(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LocalizedText(
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
