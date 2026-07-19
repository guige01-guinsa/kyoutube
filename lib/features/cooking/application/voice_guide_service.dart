class VoiceGuideSnapshot {
  const VoiceGuideSnapshot({
    required this.currentStepIndex,
    required this.totalSteps,
    required this.isPlaying,
    required this.currentStepText,
  });

  final int currentStepIndex;
  final int totalSteps;
  final bool isPlaying;
  final String currentStepText;

  bool get hasSteps => totalSteps > 0;
  bool get isFirstStep => !hasSteps || currentStepIndex <= 0;
  bool get isLastStep => !hasSteps || currentStepIndex >= totalSteps - 1;
}

class VoiceGuideService {
  VoiceGuideService();

  int _currentStepIndex = 0;
  bool _isPlaying = false;

  Future<VoiceGuideSnapshot> start(
    List<String> rawSteps, {
    int? fromIndex,
  }) async {
    final steps = _normalizeSteps(rawSteps);

    if (steps.isEmpty) {
      _currentStepIndex = 0;
      _isPlaying = false;
      return _snapshotFor(steps);
    }

    final requestedIndex = fromIndex ?? _currentStepIndex;
    _currentStepIndex = _clampIndex(requestedIndex, steps.length);
    _isPlaying = true;
    await speakStep(steps[_currentStepIndex]);
    return _snapshotFor(steps);
  }

  Future<VoiceGuideSnapshot> next(List<String> rawSteps) async {
    final steps = _normalizeSteps(rawSteps);

    if (steps.isEmpty) {
      _currentStepIndex = 0;
      _isPlaying = false;
      return _snapshotFor(steps);
    }

    _currentStepIndex = _clampIndex(_currentStepIndex + 1, steps.length);
    _isPlaying = true;
    await speakStep(steps[_currentStepIndex]);
    return _snapshotFor(steps);
  }

  Future<VoiceGuideSnapshot> previous(List<String> rawSteps) async {
    final steps = _normalizeSteps(rawSteps);

    if (steps.isEmpty) {
      _currentStepIndex = 0;
      _isPlaying = false;
      return _snapshotFor(steps);
    }

    _currentStepIndex = _clampIndex(_currentStepIndex - 1, steps.length);
    _isPlaying = true;
    await speakStep(steps[_currentStepIndex]);
    return _snapshotFor(steps);
  }

  Future<VoiceGuideSnapshot> replay(List<String> rawSteps) async {
    final steps = _normalizeSteps(rawSteps);

    if (steps.isEmpty) {
      _currentStepIndex = 0;
      _isPlaying = false;
      return _snapshotFor(steps);
    }

    _currentStepIndex = _clampIndex(_currentStepIndex, steps.length);
    _isPlaying = true;
    await speakStep(steps[_currentStepIndex]);
    return _snapshotFor(steps);
  }

  Future<VoiceGuideSnapshot> stopGuidance(List<String> rawSteps) async {
    await stop();
    return _snapshotFor(_normalizeSteps(rawSteps));
  }

  VoiceGuideSnapshot snapshot(List<String> rawSteps) {
    return _snapshotFor(_normalizeSteps(rawSteps));
  }

  Future<void> speakStep(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    // TTS is intentionally disabled in this build profile.
  }

  Future<void> stop() async {
    _isPlaying = false;
    // No-op while TTS dependency is disabled.
  }

  List<String> _normalizeSteps(List<String> rawSteps) {
    return rawSteps
        .map((String step) => step.trim())
        .where((String step) => step.isNotEmpty)
        .toList();
  }

  int _clampIndex(int index, int length) {
    if (length <= 0) {
      return 0;
    }

    if (index < 0) {
      return 0;
    }

    if (index >= length) {
      return length - 1;
    }

    return index;
  }

  VoiceGuideSnapshot _snapshotFor(List<String> steps) {
    if (steps.isEmpty) {
      return const VoiceGuideSnapshot(
        currentStepIndex: 0,
        totalSteps: 0,
        isPlaying: false,
        currentStepText: '',
      );
    }

    _currentStepIndex = _clampIndex(_currentStepIndex, steps.length);

    return VoiceGuideSnapshot(
      currentStepIndex: _currentStepIndex,
      totalSteps: steps.length,
      isPlaying: _isPlaying,
      currentStepText: steps[_currentStepIndex],
    );
  }
}
