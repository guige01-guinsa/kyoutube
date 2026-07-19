import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseMessagingDebugState {
  const FirebaseMessagingDebugState({
    required this.isSupportedPlatform,
    required this.isInitialized,
    this.permissionStatus = 'not-requested',
    this.token,
    this.lastMessageTitle,
    this.lastMessageBody,
    this.errorMessage,
  });

  final bool isSupportedPlatform;
  final bool isInitialized;
  final String permissionStatus;
  final String? token;
  final String? lastMessageTitle;
  final String? lastMessageBody;
  final String? errorMessage;

  FirebaseMessagingDebugState copyWith({
    bool? isSupportedPlatform,
    bool? isInitialized,
    String? permissionStatus,
    String? token,
    String? lastMessageTitle,
    String? lastMessageBody,
    String? errorMessage,
    bool clearToken = false,
    bool clearLastMessageTitle = false,
    bool clearLastMessageBody = false,
    bool clearErrorMessage = false,
  }) {
    return FirebaseMessagingDebugState(
      isSupportedPlatform: isSupportedPlatform ?? this.isSupportedPlatform,
      isInitialized: isInitialized ?? this.isInitialized,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      token: clearToken ? null : (token ?? this.token),
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
        token: token,
      );

      if (initialMessage != null) {
        debugState.value = debugState.value.copyWith(
          lastMessageTitle: initialMessage.notification?.title ?? '(앱 시작)',
          lastMessageBody: initialMessage.notification?.body ??
              initialMessage.data.toString(),
          clearErrorMessage: true,
        );
      }

      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((String token) {
        debugState.value = debugState.value.copyWith(
          token: token,
          clearErrorMessage: true,
        );
      });

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          debugState.value = debugState.value.copyWith(
            lastMessageTitle: message.notification?.title ?? '(제목 없음)',
            lastMessageBody: message.notification?.body ??
                message.data.toString(),
            clearErrorMessage: true,
          );
        },
      );

      _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage message) {
          debugState.value = debugState.value.copyWith(
            lastMessageTitle: message.notification?.title ?? '(앱 열림)',
            lastMessageBody:
                message.notification?.body ?? message.data.toString(),
            clearErrorMessage: true,
          );
        },
      );

      _initialized = true;
    } catch (error) {
      debugState.value = FirebaseMessagingDebugState(
        isSupportedPlatform: true,
        isInitialized: false,
        errorMessage: error.toString(),
      );
    }
  }

  static Future<void> refreshToken() async {
    if (!isSupportedPlatform) {
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugState.value = debugState.value.copyWith(
        isSupportedPlatform: true,
        isInitialized: true,
        token: token,
        clearErrorMessage: true,
      );
    } catch (error) {
      debugState.value = debugState.value.copyWith(
        errorMessage: error.toString(),
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
        errorMessage: error.toString(),
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