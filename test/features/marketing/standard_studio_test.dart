import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/marketing/application/marketing_providers.dart';
import 'package:k_youtube/features/marketing/data/standard_studio_repository.dart';
import 'package:k_youtube/features/marketing/presentation/standard_studio_page.dart';
import 'package:k_youtube/features/marketing/presentation/source_recipe_dialog.dart';
import 'package:k_youtube/features/marketing/presentation/standard_studio_summary.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';

class PollingStudioRepository extends StandardStudioRepository {
  int calls = 0;
  @override
  Future<StandardRow> command(String action, StandardRow values) async {
    calls++;
    return {
      'projects': [
        {'status': calls == 1 ? 'rendering' : 'uploaded'}
      ]
    };
  }
}

StandardRow overview(
        {String status = 'sample_approved', bool capture = false}) =>
    {
      'config': {
        'enabled': true,
        'standard_enabled': true,
        'standard_worker_seen_at': DateTime.now().toUtc().toIso8601String(),
        'standard_capture_ready': capture,
        'revision': 1,
        'sample_usd': .1,
        'render_usd': .2
      },
      'series': [
        {'id': 'series', 'title': '검사용 시리즈'}
      ],
      'projects': [
        {
          'id': 'project',
          'food': '검사 음식',
          'status': status,
          'revision': 1,
          'plan_revision': 1
        }
      ],
      'jobs': [],
    };

void main() {
  testWidgets('active work refreshes automatically and stops after completion',
      (tester) async {
    final repository = PollingStudioRepository();
    final container = ProviderContainer(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioRepositoryProvider.overrideWithValue(repository),
    ]);
    final subscription = container.listen(standardStudioProvider, (_, __) {});
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await tester.pump();
    await container.read(standardStudioProvider.future);
    expect(repository.calls, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await container.read(standardStudioProvider.future);
    expect(repository.calls, 2);
    await tester.pump(const Duration(seconds: 10));
    expect(repository.calls, 2);
  });
  test(
      'only confirmed private upload can display the queue-inclusive target as met',
      () {
    expect(standardPipelineTiming({'production_ms': 1000, 'target_met': true}),
        isNot(contains('목표 달성')));
    final uploaded = {
      'end_to_end_ms': 150000,
      'target_ms': 180000,
      'target_met': true,
      'privacy': 'private',
      'youtube_id': 'abcdefghijk'
    };
    expect(standardPipelineTiming(uploaded), contains('150초 · 3분 목표 달성'));
    expect(standardPipelineTiming({...uploaded, 'end_to_end_ms': 181000}),
        contains('목표 초과'));
    final en = const AppLocalizations(Locale('en'))
        .translate(standardPipelineTiming(uploaded));
    final es = const AppLocalizations(Locale('es'))
        .translate(standardPipelineTiming(uploaded));
    expect(en, contains('150 seconds'));
    expect(es, contains('150 segundos'));
  });
  testWidgets(
      'fast button requires both source and voice consent and states private auto upload',
      (tester) async {
    final data = overview(status: 'draft', capture: true);
    (data['config'] as Map)['fast_recipe_enabled'] = true;
    final project = (data['projects'] as List).first as Map;
    project['plan'] = {
      'profile': 'ko-180-source-v1',
      'title': '검토 원고',
      'recipe': {'url': 'https://www.youtube.com/watch?v=abcdefghijk'},
      'scenes': [],
      'sources': []
    };
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider.overrideWith((ref) async => data),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    final fast = find.widgetWithText(FilledButton, '제작·비공개 업로드 (180초 목표)');
    expect(tester.widget<FilledButton>(fast).onPressed, isNull);
    for (final tile in find
        .byType(CheckboxListTile)
        .evaluate()
        .map((e) => e.widget as CheckboxListTile)
        .toList()) {
      tile.onChanged?.call(true);
    }
    await tester.pump();
    await tester.ensureVisible(fast);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(fast).onPressed, isNotNull);
    await tester.tap(fast);
    await tester.pumpAndSettle();
    expect(find.text('제작·비공개 업로드 승인'), findsOneWidget);
    expect(find.textContaining('추가 영상 확인 승인을 기다리지 않습니다.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'alternative source is disclosed before recipe review and production',
      (tester) async {
    final data = overview(status: 'draft');
    final project = (data['projects'] as List).first as Map;
    project['plan'] = {
      'profile': 'ko-180-source-v1',
      'title': '대체 영상 원고',
      'recipe': {'url': 'https://www.youtube.com/watch?v=12345678901'},
      'scenes': <Map<String, dynamic>>[],
      'sources': <Map<String, dynamic>>[],
    };
    project['source_receipt'] = {
      'selection': {
        'requested_url': 'https://www.youtube.com/watch?v=abcdefghijk',
        'selected_url': 'https://www.youtube.com/watch?v=12345678901',
        'requires_review': true,
      },
    };
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider.overrideWith((ref) async => data),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('기준을 변경했습니다.'), findsOneWidget);
    expect(find.text('처음 요청한 영상'), findsOneWidget);
    expect(find.text('https://www.youtube.com/watch?v=abcdefghijk'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, '확인한 원고로 자동 제작'))
            .onPressed,
        isNull);
  });
  test('recipe URLs normalize shared links without accepting other origins',
      () {
    expect(canonicalRecipeVideoUrl('https://youtu.be/abcdefghijk?si=share'),
        'https://www.youtube.com/watch?v=abcdefghijk');
    expect(
        canonicalRecipeVideoUrl(
            'https://m.youtube.com/watch?v=abcdefghijk&t=3'),
        'https://www.youtube.com/watch?v=abcdefghijk');
    for (final input in [
      'https://youtube.com.evil.test/watch?v=abcdefghijk',
      'https://user@youtube.com/watch?v=abcdefghijk',
      'http://youtube.com/watch?v=abcdefghijk',
      'https://youtu.be/bad'
    ]) {
      expect(canonicalRecipeVideoUrl(input), isNull);
    }
  });
  testWidgets(
      'source start asks only for dish and URL and returns no cost consent',
      (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showRecipeSourceStart(context);
                    },
                    child: const Text('start'))))));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).at(0), '불고기');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'https://youtu.be/abcdefghijk');
    await tester.tap(find.text('원고 자동 준비'));
    await tester.pumpAndSettle();
    expect(result?['food'], '불고기');
    expect(
        result?['source_url'], 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(result?.containsKey('cost_confirmed'), isFalse);
  });
  test(
      'secure request IDs are unique UUID v4; errors do not expose server bodies',
      () {
    final ids = List.generate(100, (_) => standardRequestId());
    expect(ids.toSet().length, 100);
    expect(
        ids.every((id) => RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id)),
        isTrue);
    expect(standardError(StateError('private provider response')),
        isNot(contains('private provider')));
  });
  testWidgets('non-administrator cannot load pilot data or operate production',
      (tester) async {
    var read = false;
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => false),
      standardStudioProvider.overrideWith((ref) async {
        read = true;
        return overview();
      }),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.text('마케팅 관리자만 이용할 수 있습니다.'), findsOneWidget);
    expect(read, isFalse);
  });
  testWidgets(
      'missing real capture disables paid render with clear explanation',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider.overrideWith((ref) async => overview()),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.text('한국어 · 원본 레시피 → 원고 확인 → 제작·검사 → 비공개 업로드'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '한국어 60초 영상 제작'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('실제 앱 안내 화면 준비 중'), findsOneWidget);
  });
  testWidgets('unknown outcome offers diagnosis, not automatic paid retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      marketingAdminProvider.overrideWith((ref) async => true),
      standardStudioProvider
          .overrideWith((ref) async => overview(status: 'needs_review')),
    ], child: const MaterialApp(home: StandardStudioPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('자동 재시도하지 않습니다. 작업 기록'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '한국어 60초 영상 제작'), findsNothing);
  });
  testWidgets(
      'existing studio summary exposes completed video without nested menus',
      (tester) async {
    final data = overview(status: 'preview');
    (data['projects'] as List).first['preview'] = {'path': 'private/ko.mp4'};
    await tester.pumpWidget(ProviderScope(
        overrides: [
          standardStudioProvider.overrideWith((ref) async => data),
        ],
        child:
            const MaterialApp(home: Scaffold(body: StandardStudioSummary()))));
    await tester.pumpAndSettle();
    expect(find.text('검사 음식 · 완성 영상 검토'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '영상 미리보기'), findsOneWidget);
    expect(find.text('원고 편집·영상 제작 열기'), findsOneWidget);
  });
}
