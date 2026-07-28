import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  static const String onboardingCompletedKey = 'app.onboarding_completed_v1';

  const OnboardingState._();

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onboardingCompletedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingCompletedKey, true);
  }
}
