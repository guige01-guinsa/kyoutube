import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../ops/ops_monitor_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseMessagingDebugState {
  const FirebaseMessagingDebugState({
    required this.isSupportedPlatform,
    required this.isInitialized,
    this.permissionStatus = 'not-requested',
    this.tokenPreview,
    this.lastMessageTitle,
    this.lastMessageBody,
    this.errorMessage,
  });

  final bool isSupportedPlatform;
  final bool isInitialized;
  final String permissionStatus;

  /// A diagnostic-only token preview. Never store the complete registration
  /// token in UI state because this state can be rendered, copied, or logged.
  final String? tokenPreview;
  final String? lastMessageTitle;
  final String? lastMessageBody;
  final String? errorMessage;

  FirebaseMessagingDebugState copyWith({
    bool? isSupportedPlatform,
    bool? isInitialized,
    String? permissionStatus,
    String? tokenPreview,
    String? lastMessageTitle,
    String? lastMessageBody,
    String? errorMessage,
    bool clearTokenPreview = false,
    bool clearLastMessageTitle = false,
    bool clearLastMessageBody = false,
    bool clearErrorMessage = false,
  }) {
    return FirebaseMessagingDebugState(
      isSupportedPlatform: isSupportedPlatform ?? this.isSupportedPlatform,
      isInitialized: isInitialized ?? this.isInitialized,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      tokenPreview:
          clearTokenPreview ? null : (tokenPreview ?? this.tokenPreview),
      lastMessageTitle: clearLastMessageTitle
          ? null
          : (lastMessageTitle ?? this.lastMessageTitle),
      lastMessageBody: clearLastMessageBody
          ? null
          : (lastMessageBody ?? this.lastMessageBody),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static final ValueNotifier<FirebaseMessagingDebugState> debugState =
      ValueNotifier<FirebaseMessagingDebugState>(
    const FirebaseMessagingDebugState(
      isSupportedPlatform: false,
      isInitialized: false,
    ),
  );

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedAppSubscription;
  static bool _initialized = false;

  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String? tokenPreviewForDiagnostics(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    if (token.length <= 8) {
      return '[MASKED]';
    }

    return '${token.substring(0, 4)}…${token.substring(token.length - 4)}';
  }

  static Future<void> initialize() async {
    if (_initialized || !isSupportedPlatform) {
      debugState.value = debugState.value.copyWith(
        isSupportedPlatform: isSupportedPlatform,
      );
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;
      final initialMessage = await messaging.getInitialMessage();
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final token = await messaging.getToken();

      debugState.value = FirebaseMessagingDebugState(
        isSupportedPlatform: true,
        isInitialized: true,
        permissionStatus: settings.authorizationStatus.name,
        tokenPreview: tokenPreviewForDiagnostics(token),
      );

      if (initialMessage != null) {
        debugState.value = debugState.value.copyWith(
          lastMessageTitle: OpsMonitorService.redact(
            initialMessage.notification?.title ?? '(앱 시작)',
          ),
          lastMessageBody: OpsMonitorService.redact(
            initialMessage.notification?.body ?? '(데이터 메시지)',
          ),
          clearErrorMessage: true,
        );
      }

      _tokenRefreshSubscription =
          messaging.onTokenRefresh.listen((String token) {
        debugState.value = debugState.value.copyWith(
          tokenPreview: tokenPreviewForDiagnostics(token),
          clearErrorMessage: true,
        );
      });

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          debugState.value = debugState.value.copyWith(
            lastMessageTitle: OpsMonitorService.redact(
              message.notification?.title ?? '(제목 없음)',
            ),
            lastMessageBody: OpsMonitorService.redact(
              message.notification?.body ?? '(데이터 메시지)',
            ),
            clearErrorMessage: true,
          );
        },
      );

      _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage message) {
          debugState.value = debugState.value.copyWith(
            lastMessageTitle: OpsMonitorService.redact(
              message.notification?.title ?? '(앱 열림)',
            ),
            lastMessageBody: OpsMonitorService.redact(
              message.notification?.body ?? '(데이터 메시지)',
            ),
            clearErrorMessage: true,
          );
        },
      );

      _initialized = true;
    } catch (error) {
      debugState.value = FirebaseMessagingDebugState(
        isSupportedPlatform: true,
        isInitialized: false,
        errorMessage: OpsMonitorService.redact(error.toString()),
      );
    }
  }

  static Future<void> refreshToken() async {
    if (!isSupportedPlatform || kReleaseMode) {
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.deleteToken();
      final token = await messaging.getToken();
      debugState.value = debugState.value.copyWith(
        isSupportedPlatform: true,
        isInitialized: true,
        tokenPreview: tokenPreviewForDiagnostics(token),
        clearErrorMessage: true,
      );
    } catch (error) {
      debugState.value = debugState.value.copyWith(
        errorMessage: OpsMonitorService.redact(error.toString()),
      );
    }
  }

  static Future<void> requestPermission() async {
    if (!isSupportedPlatform) {
      return;
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugState.value = debugState.value.copyWith(
        isSupportedPlatform: true,
        isInitialized: true,
        permissionStatus: settings.authorizationStatus.name,
        clearErrorMessage: true,
      );
    } catch (error) {
      debugState.value = debugState.value.copyWith(
        errorMessage: OpsMonitorService.redact(error.toString()),
      );
    }
  }

  static Future<void> deleteDeviceToken() async {
    if (!isSupportedPlatform) {
      return;
    }

    try {
      await FirebaseMessaging.instance.deleteToken();

      debugState.value = debugState.value.copyWith(
        clearTokenPreview: true,
        clearErrorMessage: true,
      );
    } catch (error) {
      // FCM token 삭제 실패가 로그아웃/회원탈퇴를 막으면 안 된다.
      debugState.value = debugState.value.copyWith(
        errorMessage: OpsMonitorService.redact(error.toString()),
      );
    }
  }

  static Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _openedAppSubscription = null;
    _initialized = false;
  }
}
