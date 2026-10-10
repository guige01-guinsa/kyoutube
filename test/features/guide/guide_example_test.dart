import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/guide/domain/guide_example.dart';
import 'package:k_youtube/features/guide/domain/guide_curriculum.dart';
import 'package:k_youtube/features/guide/domain/guide_purchase_example.dart';
import 'package:k_youtube/features/guide/application/guide_progress.dart';
import 'package:k_youtube/features/suppliers/domain/procurement_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('training calculations preserve cost basis when servings change', () {
    final base = GuideExample(), scaled = GuideExample(servings: 20);
    expect(base.usage, 800);
    expect(base.purchase, 1000);
    expect(base.recipe.portionCost, 3000);
    expect(scaled.usage, 4000);
    expect(scaled.purchase, 5000);
    expect(scaled.recipe.portionCost, base.recipe.portionCost);
    expect(base.price, 4500);
    expect(base.revenueForTen, 45000);
    expect(base.differenceForTen, 15000);
    expect(GuideExample(markup: 0).differenceForTen, 0);
    expect(GuideExample(markup: 100).price, 6000);
    expect(() => GuideExample(yieldPercent: 0), throwsArgumentError);
  });
  test('24 bilingual lessons cover three roles and three professional tracks',
      () {
    expect(guideLessons.map((l) => l.id).toSet().length, 24);
    expect(guideLessonsFor(GuideAudience.professional).length, 14);
    expect(
        guideTrackLessons(GuideAudience.professional, GuideTrack.purchasing)
            .length,
        6);
    expect(
        guideTrackLessons(GuideAudience.professional, GuideTrack.cooking)
            .length,
        5);
    expect(
        guideTrackLessons(GuideAudience.professional, GuideTrack.management)
            .length,
        3);
    expect(guideLessonsFor(GuideAudience.home).length, 5);
    expect(guideLessonsFor(GuideAudience.supplier).length, 5);
    for (final l in guideLessons) {
      expect(l.steps.length, greaterThanOrEqualTo(3));
      expect(l.correctAnswer, inInclusiveRange(0, l.answers.length - 1));
      expect(guideLabels.containsKey(l.access), isTrue);
      expect(guideLabels.containsKey('route-${l.destination.name}'), isTrue);
      for (final text in [
        l.title,
        l.goal,
        l.outcome,
        l.tip,
        l.question,
        l.explanation,
        ...l.answers,
        ...l.steps.expand((s) => [s.title, s.body])
      ]) {
        expect(text.ko, isNotEmpty);
        expect(text.en, isNotEmpty);
        expect(RegExp(r'[가-힣]').hasMatch(text.en), isFalse);
      }
    }
    expect(guideLessonById('unknown'), isNull);
  });
  test(
      'purchase example uses real priorities including shipping and per-item caps',
      () {
    final p = GuidePurchaseExample();
    final fewest = p.compare()!,
        cheapest = p.compare(criterion: ProcurementPriority.lowestPrice)!,
        highest = p.compare(criterion: ProcurementPriority.highestRating)!;
    expect(fewest.supplierIds, {'A'});
    expect(fewest.total, 16000);
    expect(cheapest.supplierIds, {'B', 'C'});
    expect(cheapest.total, 8000);
    expect(highest.supplierIds, {'D'});
    expect(highest.total, 25000);
    expect(p.toggleCandidate('carrot', 'C', true), isFalse);
    expect(p.toggleCandidate('carrot', 'D', false), isTrue);
    expect(p.toggleCandidate('carrot', 'C', true), isTrue);
    expect(p.candidates['tofu'], {'A', 'C', 'D'});
    p.quantity('carrot', 2);
    expect(p.compare(criterion: ProcurementPriority.lowestPrice)!.total, 10000);
    expect(() => p.quantity('carrot', double.nan), throwsArgumentError);
    p.selected.clear();
    expect(p.compare(), isNull);
  });
  test(
      'v2 keeps unchanged lessons without completing replacement purchase lessons',
      () async {
    SharedPreferences.setMockInitialValues({
      'guide_curriculum_v2': [
        'pro-standard.done',
        'pro-purchase.done',
        'home-search.done'
      ],
      'guide_audience_v2': 'home'
    });
    final p = GuideProgress();
    await p.load();
    expect(p.audience, GuideAudience.home);
    expect(p.completedCount(GuideAudience.professional), 1);
    expect(p.completed('buy-quantity'), isFalse);
    p.selectAudience(GuideAudience.supplier);
    await p.flush();
    p.dispose();
    final restored = GuideProgress();
    await restored.load();
    expect(restored.audience, GuideAudience.supplier);
    expect(restored.completed('home-search'), isTrue);
    restored.dispose();
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('guide_curriculum_v2'),
        contains('pro-purchase.done'));
  });
  test(
      'quiz is optional, skip is not complete and replay only clears one lesson',
      () async {
    SharedPreferences.setMockInitialValues({});
    final p = GuideProgress();
    await p.load();
    final l = guideLessonById('buy-quantity')!;
    p.visit(l);
    p.skip(l);
    expect(p.completed(l.id), isFalse);
    expect(p.skipped(l.id), isTrue);
    p.recordPractice(l.id);
    expect(p.canComplete(l), isTrue);
    p.answer(l.id, false);
    p.complete(l);
    expect(p.completed(l.id), isTrue);
    expect(p.skipped(l.id), isFalse);
    final other = guideLessonById('home-search')!;
    p.recordPractice(other.id);
    p.complete(other);
    p.restart(l);
    expect(p.completed(l.id), isFalse);
    expect(p.completed(other.id), isTrue);
    await p.flush();
    p.dispose();
    final restored = GuideProgress();
    await restored.load();
    expect(restored.lastLesson, l.id);
    expect(
        restored
            .recommended(guideTrackLessons(restored.audience, restored.track))
            .first
            .id,
        l.id);
    restored.dispose();
  });
  test('direct lesson resolves its own role even when another role was saved',
      () async {
    SharedPreferences.setMockInitialValues({GuideProgress.audienceKey: 'home'});
    final p = GuideProgress(
        initialAudience: GuideAudience.professional,
        initialLesson: 'supplier-pack');
    await p.load();
    expect(p.audience, GuideAudience.supplier);
    expect(p.lastLesson, 'supplier-pack');
    p.dispose();
  });
}
