class VoiceGuideService {
  VoiceGuideService();

  Future<void> speakStep(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    // TTS is intentionally disabled in this build profile.
  }

  Future<void> stop() async {
    // No-op while TTS dependency is disabled.
  }
}
