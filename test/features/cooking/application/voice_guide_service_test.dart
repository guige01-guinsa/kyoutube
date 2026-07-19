import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/cooking/application/voice_guide_service.dart';

void main() {
  group('VoiceGuideService', () {
    late VoiceGuideService service;

    setUp(() {
      service = VoiceGuideService();
    });

    test('start should normalize steps and begin from first valid step', () async {
      final snapshot = await service.start(
        <String>['', '  재료 손질  ', '  ', '불 조절'],
      );

      expect(snapshot.totalSteps, 2);
      expect(snapshot.currentStepIndex, 0);
      expect(snapshot.currentStepText, '재료 손질');
      expect(snapshot.isPlaying, isTrue);
    });

    test('start should honor fromIndex with clamping', () async {
      final snapshot = await service.start(
        <String>['step1', 'step2', 'step3'],
        fromIndex: 10,
      );

      expect(snapshot.currentStepIndex, 2);
      expect(snapshot.currentStepText, 'step3');
    });

    test('next and previous should move within boundaries', () async {
      await service.start(<String>['step1', 'step2']);

      final movedNext = await service.next(<String>['step1', 'step2']);
      expect(movedNext.currentStepIndex, 1);
      expect(movedNext.currentStepText, 'step2');

      final clampedNext = await service.next(<String>['step1', 'step2']);
      expect(clampedNext.currentStepIndex, 1);

      final movedPrev = await service.previous(<String>['step1', 'step2']);
      expect(movedPrev.currentStepIndex, 0);
      expect(movedPrev.currentStepText, 'step1');

      final clampedPrev = await service.previous(<String>['step1', 'step2']);
      expect(clampedPrev.currentStepIndex, 0);
    });

    test('replay should keep current index and keep playing', () async {
      await service.start(<String>['a', 'b', 'c'], fromIndex: 1);

      final snapshot = await service.replay(<String>['a', 'b', 'c']);

      expect(snapshot.currentStepIndex, 1);
      expect(snapshot.currentStepText, 'b');
      expect(snapshot.isPlaying, isTrue);
    });

    test('stopGuidance should preserve index but switch to stopped state', () async {
      await service.start(<String>['a', 'b', 'c'], fromIndex: 2);

      final stopped = await service.stopGuidance(<String>['a', 'b', 'c']);

      expect(stopped.currentStepIndex, 2);
      expect(stopped.currentStepText, 'c');
      expect(stopped.isPlaying, isFalse);
    });

    test('empty steps should return empty snapshot and stopped state', () async {
      final snapshot = await service.start(<String>['', '   ']);

      expect(snapshot.hasSteps, isFalse);
      expect(snapshot.totalSteps, 0);
      expect(snapshot.currentStepText, isEmpty);
      expect(snapshot.isPlaying, isFalse);
    });
  });
}
