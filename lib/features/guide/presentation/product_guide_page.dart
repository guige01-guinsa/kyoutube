import '../../../core/localization/localized_text.dart';
import 'guide_sample_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/official_channels_card.dart';
import '../application/guide_progress.dart';
import '../domain/guide_curriculum.dart';
import '../domain/guide_purchase_example.dart';
import 'guide_example_card.dart';
import 'guide_training_card.dart';

class ProductGuidePage extends StatefulWidget {
  const ProductGuidePage({super.key, this.initialAudience, this.initialLesson});
  final GuideAudience? initialAudience;
  final String? initialLesson;
  @override
  State<ProductGuidePage> createState() => _ProductGuidePageState();
}

class _ProductGuidePageState extends State<ProductGuidePage> {
  late final GuideProgress _progress;
  final _scroll = ScrollController();
  GuidePurchaseExample _purchase = GuidePurchaseExample();
  String? _selected;
  bool _all = false, _example = false;
  int _run = 0;
  final Map<String, int> _answers = {};
  @override
  void initState() {
    super.initState();
    _progress = GuideProgress(
        initialAudience: widget.initialAudience,
        initialLesson: widget.initialLesson);
    _progress.load().then((_) {
      if (!mounted) return;
      setState(() => _selected = guideLessonById(widget.initialLesson)?.id);
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String t(GuideText text) =>
      AppLocalizations.of(context).bilingual(text.ko, text.en);
  String tr(String ko, String en) =>
      AppLocalizations.of(context).bilingual(ko, en);
  String label(String key) => t(guideLabels[key]!);
  List<GuideLesson> get _lessons =>
      guideTrackLessons(_progress.audience, _progress.track);
  void _top() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _open(GuideLesson? lesson) {
    setState(() {
      _selected = lesson?.id;
      _example = false;
    });
    if (lesson != null) _progress.visit(lesson);
    _top();
  }

  void _next(GuideLesson lesson, {bool skip = false}) {
    final list = _lessons, index = list.indexWhere((l) => l.id == lesson.id);
    if (skip) _progress.skip(lesson);
    _open(index >= 0 && index + 1 < list.length ? list[index + 1] : null);
  }

  Future<void> _openSamples(GuideLesson lesson) async {
    await context.push(guideSamplePath(lesson.id));
    if (mounted) await _progress.load();
  }

  String _route(GuideDestination destination) => switch (destination) {
        GuideDestination.search => '/',
        GuideDestination.youtube => '/youtube',
        GuideDestination.recipes => '/my-recipes',
        GuideDestination.chef => '/chef',
        GuideDestination.sales => '/chef-sales',
        GuideDestination.shopping => '/kitchen?tab=shopping',
        GuideDestination.suppliers => '/shopping-stores',
        GuideDestination.directory => '/supplier-directory',
        GuideDestination.planner => '/supplier-plan',
        GuideDestination.purchases => '/purchases',
        GuideDestination.ledger => '/supplier-request-ledger',
        GuideDestination.business => '/supplier-business',
        GuideDestination.ingredients => '/ingredient-search',
      };
  IconData _roleIcon(GuideAudience a) => switch (a) {
        GuideAudience.professional => Icons.balance_outlined,
        GuideAudience.home => Icons.restaurant_outlined,
        GuideAudience.supplier => Icons.storefront_outlined
      };
  Widget heading(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
  static const gap = SizedBox(height: 16);
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _selected == null || widget.initialLesson != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected != null) _open(null);
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(label('title')),
            leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (widget.initialLesson != null && context.canPop()) {
                    context.pop();
                  } else if (_selected != null) {
                    _open(null);
                  } else if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/workspace');
                  }
                })),
        body: SafeArea(
            child: ListenableBuilder(
                listenable: _progress,
                builder: (context, _) {
                  if (!_progress.ready) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1000),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (_progress.saveFailed) ...[
                                      Text(label('saveError')),
                                      gap
                                    ],
                                    if (_selected == null)
                                      ..._overview()
                                    else
                                      ..._lesson(guideLessonById(_selected)!),
                                  ]))));
                })),
      ));

  List<Widget> _overview() {
    final course = guideCourses[_progress.audience]!, lessons = _lessons;
    final recommendations = _progress.recommended(lessons);
    final total = guideLessonsFor(_progress.audience).length,
        count = _progress.completedCount(_progress.audience);
    return [
      const OfficialChannelsCard(),
      gap,
      Text(label('choose'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in GuideAudience.values)
          ChoiceChip(
              key: Key('guide-audience-${a.name}'),
              showCheckmark: false,
              selectedColor: ScoutStyle.forest,
              labelStyle: TextStyle(
                  color:
                      _progress.audience == a ? Colors.white : ScoutStyle.ink),
              avatar: Icon(_roleIcon(a),
                  size: 18,
                  color: _progress.audience == a
                      ? Colors.white
                      : ScoutStyle.forest),
              label: Text(t(guideCourses[a]!.title)),
              selected: _progress.audience == a,
              onSelected: (_) {
                _progress.selectAudience(a);
                setState(() => _all = false);
                _top();
              })
      ]),
      gap,
      Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [ScoutStyle.ink, Color(0xff165947)]),
              borderRadius: BorderRadius.circular(24)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LocalizedText('RECIPE SCOUT · ${tr('직접 해보는 안내', 'LEARN BY DOING')}',
                style: const TextStyle(
                    color: ScoutStyle.peach, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 12),
            Text(t(course.hero),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(t(course.intro),
                style: const TextStyle(color: Colors.white, height: 1.5)),
            const SizedBox(height: 20),
            LocalizedText('${label('progress')} · $count / $total',
                style: const TextStyle(color: ScoutStyle.peach)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: count / total,
                color: ScoutStyle.peach,
                backgroundColor: Colors.white24,
                minHeight: 5,
                semanticsLabel: label('progress')),
          ])),
      gap,
      if (_progress.audience == GuideAudience.professional) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final track in GuideTrack.values)
            ChoiceChip(
                key: Key('guide-track-${track.name}'),
                label: Text(switch (track) {
                  GuideTrack.purchasing =>
                    tr('구매 업무 · 6개 실습', 'Purchasing · 6 lessons'),
                  GuideTrack.cooking =>
                    tr('조리 연구 · 5개 실습', 'Cooking · 5 lessons'),
                  GuideTrack.management =>
                    tr('경영 관리 · 3개 실습', 'Management · 3 lessons'),
                }),
                selected: _progress.track == track,
                onSelected: (_) {
                  _progress.selectTrack(track);
                  setState(() => _all = false);
                })
        ]),
        gap,
      ],
      Text(label('saved'), style: Theme.of(context).textTheme.bodySmall),
      gap,
      heading(tr('지금 해볼 일', 'Try this next')),
      const SizedBox(height: 8),
      Text(tr('하나를 골라 짧게 체험하세요. 순서대로 모두 배울 필요는 없습니다.',
          'Choose one short activity. You can learn in any order.')),
      gap,
      FilledButton.icon(
          key: const Key('guide-continue'),
          onPressed: () => _open(recommendations.first),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_progress.lastLesson == null
              ? tr('추천 실습 시작', 'Start a recommended lesson')
              : label('continue'))),
      gap,
      LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 800 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.4
            ? 3
            : 1;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final l in recommendations)
            SizedBox(
                width: (c.maxWidth - 12 * (columns - 1)) / columns,
                child: _lessonTile(l))
        ]);
      }),
      gap,
      OutlinedButton.icon(
          key: const Key('guide-show-all'),
          onPressed: () => setState(() => _all = !_all),
          icon: Icon(_all ? Icons.expand_less : Icons.view_list_outlined),
          label: LocalizedText(_all
              ? tr('전체 과정 접기', 'Collapse lessons')
              : '${tr('전체 과정 보기', 'View all lessons')} · ${lessons.length}')),
      if (_all) ...[
        gap,
        for (final l in lessons.where((l) => !recommendations.contains(l)))
          Padding(
              padding: const EdgeInsets.only(bottom: 10), child: _lessonTile(l))
      ],
      gap,
      Text(label('previewNote'), style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  Widget _lessonTile(GuideLesson l) => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          key: Key('guide-lesson-${l.id}'),
          onTap: () => _open(l),
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        _progress.completed(l.id)
                            ? Icons.check_circle_outline
                            : Icons.touch_app_outlined,
                        color: ScoutStyle.forest),
                    const SizedBox(height: 12),
                    Text(t(l.title),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(t(l.goal)),
                    const SizedBox(height: 12),
                    LocalizedText(
                        '${tr('약', 'About')} ${l.minutes} ${tr('분', 'min')} · ${_progress.completed(l.id) ? label('done') : _progress.skipped(l.id) ? tr('나중에 보기', 'For later') : tr('체험하기', 'Try it')}',
                        style: Theme.of(context).textTheme.labelMedium),
                  ]))));

  List<Widget> _lesson(GuideLesson lesson) {
    final done = _progress.completed(lesson.id),
        answer = _answers[lesson.id],
        correct = _progress.passed(lesson.id);
    final list = _lessons, index = list.indexWhere((l) => l.id == lesson.id);
    return [
      Wrap(spacing: 12, runSpacing: 8, children: [
        Text(t(guideCourses[lesson.audience]!.title),
            style: Theme.of(context).textTheme.labelLarge),
        LocalizedText(
            '${index + 1} / ${list.length} · ${tr('약', 'About')} ${lesson.minutes} ${tr('분', 'min')}')
      ]),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: (index + 1) / list.length, minHeight: 4),
      gap,
      Text(t(lesson.title), style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Text(t(lesson.goal)),
      gap,
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: ScoutStyle.ink, borderRadius: BorderRadius.circular(20)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label('outcome'),
                style: const TextStyle(color: ScoutStyle.peach)),
            const SizedBox(height: 8),
            Text(t(lesson.outcome),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white))
          ])),
      gap,
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
            key: const Key('guide-sample-workspace'),
            onPressed: () => _openSamples(lesson),
            icon: const Icon(Icons.auto_awesome_motion_outlined),
            label: Text(tr('샘플로 바로 체험', 'Practice with sample records'))),
        OutlinedButton.icon(
            key: const Key('guide-try-example'),
            onPressed: () => setState(() => _example = !_example),
            icon: const Icon(Icons.touch_app_outlined),
            label: Text(_example
                ? tr('예제 접기', 'Hide example')
                : tr('예제로 연습', 'Try an example'))),
        OutlinedButton.icon(
            key: const Key('guide-practice'),
            onPressed: () => context.push(_route(lesson.destination)),
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('내 자료로 시작', 'Use my own data'))),
      ]),
      const SizedBox(height: 8),
      Text(tr('샘플은 무료로 체험하고 저장·초기화할 수 있어요. 실제 자료 이용에는 해당 요금제 권한이 적용됩니다.',
          'Sample records are free to practice, save and reset. Your own data uses your plan permissions.')),
      const SizedBox(height: 8),
      LocalizedText('${label(lesson.access)} · ${label('return')}',
          style: Theme.of(context).textTheme.bodySmall),
      if (_example) ...[
        gap,
        if (lesson.practice != GuidePractice.none)
          GuideExampleCard(
              key: ValueKey('${lesson.id}-$_run'),
              practice: lesson.practice,
              onPracticed: () => _progress.recordPractice(lesson.id))
        else
          GuideTrainingCard(
              key: ValueKey('${lesson.id}-$_run'),
              lesson: lesson,
              purchase: _purchase,
              onPracticed: () => _progress.recordPractice(lesson.id)),
      ],
      const SizedBox(height: 24),
      heading(label('steps')),
      const SizedBox(height: 8),
      Text(label('stepHint'), style: Theme.of(context).textTheme.bodySmall),
      gap,
      for (var i = 0; i < lesson.steps.length; i++)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
                child: CheckboxListTile(
                    key: Key('guide-step-$i'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.all(12),
                    value: _progress.checked(lesson.id, i),
                    onChanged: (_) => _progress.toggle(lesson.id, i),
                    title: LocalizedText('${i + 1}. ${t(lesson.steps[i].title)}',
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(t(lesson.steps[i].body)))))),
      gap,
      Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: ScoutStyle.peach.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(18)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading(label('tip')),
                const SizedBox(height: 8),
                Text(t(lesson.tip))
              ])),
      gap,
      ExpansionTile(
          key: ValueKey('guide-quiz-${lesson.id}'),
          title: Text(label('quiz')),
          children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t(lesson.question),
                          style: Theme.of(context).textTheme.titleMedium),
                      gap,
                      for (var i = 0; i < lesson.answers.length; i++)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton(
                                key: Key('guide-answer-$i'),
                                style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    backgroundColor:
                                        answer == i ? ScoutStyle.mint : null),
                                onPressed: () {
                                  setState(() => _answers[lesson.id] = i);
                                  _progress.answer(
                                      lesson.id, i == lesson.correctAnswer);
                                },
                                child: Text(t(lesson.answers[i])))),
                      if (answer != null || correct)
                        Semantics(
                            liveRegion: true,
                            child: LocalizedText(
                                '${label(correct ? 'correct' : 'retry')} ${t(lesson.explanation)}')),
                    ])),
          ]),
      gap,
      if (done)
        Container(
            key: const Key('guide-result'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: ScoutStyle.mint,
                borderRadius: BorderRadius.circular(18)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_outline, color: ScoutStyle.forest),
              const SizedBox(height: 8),
              heading(tr('한 가지를 해냈어요', 'One task learned')),
              const SizedBox(height: 8),
              Text(t(lesson.outcome)),
              Text(tr('학습 완료 기록입니다. 실제 업무 처리 여부는 해당 화면에서 확인하세요.',
                  'This records learning completion. Check the real workspace for business actions.'))
            ])),
      if (!done) ...[
        FilledButton.icon(
            key: const Key('guide-complete'),
            onPressed: _progress.canComplete(lesson)
                ? () => _progress.complete(lesson)
                : null,
            icon: const Icon(Icons.check),
            label: Text(label('complete'))),
        const SizedBox(height: 8),
        Text(label('unlock'), style: Theme.of(context).textTheme.bodySmall),
      ],
      gap,
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (done)
          FilledButton.icon(
              key: const Key('guide-next'),
              onPressed: () => _next(lesson),
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                  index + 1 < list.length ? label('next') : label('overview')))
        else
          TextButton(
              key: const Key('guide-skip'),
              onPressed: () => _next(lesson, skip: true),
              child: Text(tr('건너뛰고 다음에 보기', 'Skip for now'))),
        TextButton(
            key: const Key('guide-restart'),
            onPressed: () {
              _progress.restart(lesson);
              setState(() {
                _run++;
                _example = true;
                _answers.remove(lesson.id);
                if (lesson.id.startsWith('buy-')) {
                  _purchase = GuidePurchaseExample();
                }
              });
              _top();
            },
            child: Text(tr('다시 연습하기', 'Practice again'))),
        TextButton(
            key: const Key('guide-overview'),
            onPressed: () => _open(null),
            child: Text(label('overview'))),
      ]),
    ];
  }
}
