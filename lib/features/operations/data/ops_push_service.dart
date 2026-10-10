import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OpsPushService {
  static const _key = 'ops_admin_push_enabled';
  static final openRequested = ValueNotifier<bool>(false);
  static final received = ValueNotifier<int>(0);
  static bool _started = false;
  static String _language = 'ko';
  static String? _lastUser;
  static Future<void> _pending = Future<void>.value();
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void handleOpen(RemoteMessage message) {
    if (message.data['type'] == 'ops_alert') openRequested.value = true;
  }

  static void start() {
    if (!supported || _started) return;
    _started = true;
    final client = Supabase.instance.client;
    _lastUser = client.auth.currentUser?.id;
    client.auth.onAuthStateChange.listen((state) {
      final changed = _lastUser != state.session?.user.id;
      _lastUser = state.session?.user.id;
      _pending = _pending.then((_) async {
        final prefs = await SharedPreferences.getInstance();
        if (changed && prefs.getBool(_key) == true) {
          await FirebaseMessaging.instance.deleteToken();
        }
        await _sync();
      }).catchError((Object _) {});
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _queueSync());
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'ops_alert') received.value++;
    });
    _queueSync();
  }

  static void _queueSync() {
    _pending = _pending.then((_) => _sync()).catchError((Object _) {});
  }

  static Future<void> _sync() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('ops_admin_push_language') ?? 'ko';
    if (prefs.getBool(_key) != true ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    await _register();
  }

  static Future<void> _register() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) throw StateError('Push token unavailable');
    await Supabase.instance.client.rpc('admin_register_ops_device', params: {
      'p_token': token,
      'p_language': _language
    }).timeout(const Duration(seconds: 15));
  }

  static Future<void> enable(String language) async {
    if (!supported) throw StateError('Mobile notifications required');
    _language = const {'en', 'es'}.contains(language) ? language : 'ko';
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Permission required');
    }
    await _register();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    await prefs.setString('ops_admin_push_language', _language);
    start();
  }

  static Future<void> disable() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    await _pending;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await Supabase.instance.client.rpc('unregister_ops_device',
          params: {'p_token': token}).timeout(const Duration(seconds: 15));
    }
  }
}
