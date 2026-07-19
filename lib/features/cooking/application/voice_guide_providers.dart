import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_guide_service.dart';

final voiceGuideServiceProvider = Provider<VoiceGuideService>(
  (ref) => VoiceGuideService(),
);
