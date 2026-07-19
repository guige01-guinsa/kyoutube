import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrap {
  static Future<void> initialize() async {
    if (!_isSupportedPlatform) {
      return;
    }

    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (error) {
      throw StateError(
        'Firebase initialization failed. Add android/app/google-services.json for Android and GoogleService-Info.plist to ios/Runner for iOS before running the app. Original error: ${error.code}',
      );
    }
  }

  static bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}