import '../../../core/localization/localized_text.dart';
import 'package:intl/intl.dart';
import '../../kitchen/domain/shopping_units.dart';
import '../domain/guide_sample_tasks.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../chef/domain/chef_recipe.dart';
import '../../chef/domain/chef_sales.dart';
import '../../chef/presentation/chef_unit_field.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../suppliers/domain/procurement_plan.dart';
import '../../suppliers/domain/supplier_catalog.dart';
import '../application/guide_progress.dart';
import '../application/guide_sample_store.dart';
import '../domain/guide_curriculum.dart';
import '../domain/guide_sample_data.dart';
import '../domain/guide_purchase_example.dart';

part 'guide_sample_recipe.dart';
part 'guide_sample_purchase.dart';
part 'guide_sample_supplier.dart';

String guideSamplePath(String id) => '/guide/practice/$id';

/// A record-backed practice workspace. It never obtains a production repository,
/// authentication provider or network client, including for premium examples.
class GuideSamplePage extends StatefulWidget {
  const GuideSamplePage({super.key, required this.lessonId});
  final String lessonId;
  @override
  State<GuideSamplePage> createState() => _GuideSamplePageState();
}

class _GuideSamplePageState extends State<GuideSamplePage> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late GuideSampleStore _store;
  GuideSampleData? _data;
  bool _started = false, _busy = false, _dirty = false, _saved = false;
  String? _error;
  int _epoch = 0, _product = 0, _saleQuantity = 10, _version = 1;
  ChefSalesPeriod _period = ChefSalesPeriod.week;
  bool _review = false;
  GuideLesson get lesson => guideLessonById(widget.lessonId)!;
  GuideSampleData get d => _data!;
  bool get en => AppLocalizations.of(context).isEnglish;
  String t(String ko, String english) => AppLocalizations.of(context).bilingual(ko, english);
  String text(GuideText value) => en ? value.en : value.ko;
  String number(double? value) => chefFormat(value);
  String money(double? value) => value == null
      ? t('계산 기준 확인 필요', 'Check conversion or cost inputs')
      : '${NumberFormat('#,##0.##', en ? 'en' : 'ko').format(value)} KRW';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _store = GuideSampleStore(en);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _store.load();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('샘플자료를 준비하지 못했습니다. 저장 공간을 확인하고 다시 시도하세요.',
            'Could not prepare samples. Check device storage and retry.'));
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void redraw(VoidCallback action) => setState(action);
  void change(VoidCallback action) => setState(() {
        _review = false;
        action();
        _dirty = true;
        _saved = false;
        _error = null;
      });
  Future<bool> save({VoidCallback? action}) async {
    if (_busy || !(_form.currentState?.validate() ?? true)) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Roll back derived actions on storage failure, so retry cannot duplicate
      // sales, requests or snapshots. Field edits remain available for retry.
      final original = GuideSampleData.fromJson(d.toJson());
      try {
        action?.call();
        d.practiced.add(lesson.id);
        await _store.save(d);
      } catch (_) {
        _data = original;
        rethrow;
      }
      final progress = GuideProgress();
      try {
        await progress.load();
        progress.recordPractice(lesson.id);
        progress.complete(lesson);
        await progress.flush();
      } finally {
        progress.dispose();
      }
      if (mounted) {
        setState(() {
          _dirty = false;
          _saved = true;
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('저장하지 못했습니다. 입력한 내용은 유지됩니다. 다시 시도해 주세요.',
            'Could not save. Your edits are retained. Please retry.'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> leave() async {
    if (_busy) return;
    if (_dirty &&
        !await confirm(
            t('저장하지 않은 연습 내용을 닫을까요?', 'Discard unsaved practice edits?'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(guideLessonPath(lesson.id));
    }
  }

  Future<bool> confirm(String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(t('취소', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(t('확인', 'Confirm')))
              ])) ==
      true;
  Future<void> reset() async {
    if (!await confirm(t(
        '이 언어의 샘플자료를 처음 상태로 되돌릴까요? 저장한 연습 수정사항이 지워집니다. 실제 자료와 학습 완료 기록은 유지됩니다.',
        'Reset samples for this language? Saved practice edits will be removed. Real records and learning completion stay unchanged.'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final data = await _store.reset();
      if (mounted) {
        setState(() {
          _data = data;
          _epoch++;
          _dirty = false;
          _saved = false;
          _review = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            t('초기화하지 못했습니다. 다시 시도하세요.', 'Could not reset. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> openLesson(String id) async {
    if (_dirty &&
        !await confirm(t(
            '저장하지 않은 변경을 버리고 이동할까요?', 'Discard unsaved edits and continue?'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    context.replace(guideSamplePath(id));
  }

  Widget field(
          String id, String label, String initial, ValueChanged<String> update,
          {int lines = 1, bool required = true, int max = 250}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              key: ValueKey('$_epoch-$id'),
              initialValue: initial,
              enabled: !_busy,
              maxLines: lines,
              maxLength: max,
              decoration: InputDecoration(
                  labelText: label, alignLabelWithHint: lines > 1),
              validator: (value) =>
                  required && (value == null || value.trim().isEmpty)
                      ? t('내용을 입력하세요.', 'Enter a value.')
                      : null,
              onChanged: (value) => change(() => update(value))));
  Widget numeric(
          String id, String label, double? initial, ValueChanged<double> update,
          {double min = .001, double max = 1000000, bool integer = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              key: ValueKey('$_epoch-$id'),
              initialValue: initial == null ? '' : number(initial),
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label),
              validator: (text) {
                final n = chefInputNumber(text ?? '');
                return n == null ||
                        !n.isFinite ||
                        n < min ||
                        n > max ||
                        (integer && n != n.roundToDouble())
                    ? t('${number(min)}~${number(max)}${integer ? ' 사이의 정수' : ' 사이의 숫자'}를 입력하세요.',
                        'Enter ${integer ? 'a whole number' : 'a number'} from ${number(min)} to ${number(max)}.')
                    : null;
              },
              onChanged: (text) {
                final n = chefInputNumber(text);
                change(() {
                  if (n != null &&
                      n.isFinite &&
                      n >= min &&
                      n <= max &&
                      (!integer || n == n.roundToDouble())) {
                    update(n);
                  }
                });
              }));
  Widget panel(String title, List<Widget> children, {IconData? icon}) => Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (icon != null) ...[
              Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(icon, color: ScoutStyle.forest)),
              const SizedBox(height: 8)
            ],
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children
          ])));
  Widget note(String ko, String english) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child:
          Text(t(ko, english), style: Theme.of(context).textTheme.bodyMedium));
  Widget metric(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
          spacing: 16,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: Theme.of(context).textTheme.titleMedium)
          ]));
  Widget action(String key, String ko, String english, VoidCallback onPressed,
          {IconData icon = Icons.save_outlined}) =>
      Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
              key: Key(key),
              onPressed: _busy ? null : onPressed,
              icon: Icon(icon),
              label: Text(t(ko, english))));
  Widget photo(String image, {double height = 110}) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset('assets/guide/$image.png',
          height: height,
          fit: BoxFit.cover,
          semanticLabel: t('연습용 식재료 그림', 'Practice ingredient illustration')));
  List<GuideLesson> get sequence =>
      guideTrackLessons(lesson.audience, guideTrackFor(lesson));
  String? get nextId {
    final index = sequence.indexWhere((l) => l.id == lesson.id);
    return index + 1 < sequence.length ? sequence[index + 1].id : null;
  }

  @override
  Widget build(BuildContext context) {
    if (guideLessonById(widget.lessonId) == null) {
      return Scaffold(
          appBar: AppBar(title: Text(t('샘플 작업실', 'Sample workspace'))),
          body: Center(
              child: Text(t('체험 항목을 찾을 수 없습니다.', 'Lesson unavailable.'))));
    }
    return PopScope(
        canPop: !_dirty && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) leave();
        },
        child: Scaffold(
            appBar: AppBar(
                title: Text(t('샘플 작업실', 'Sample workspace')),
                leading: IconButton(
                    tooltip: t('튜토리얼로 돌아가기', 'Back to tutorial'),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: leave),
                actions: [
                  IconButton(
                      key: const Key('sample-reset'),
                      tooltip: t('샘플 초기화', 'Reset samples'),
                      icon: const Icon(Icons.restart_alt),
                      onPressed: _data == null || _busy ? null : reset)
                ]),
            body: SafeArea(
                child: _data == null
                    ? Center(
                        child: _error == null
                            ? const CircularProgressIndicator()
                            : Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(_error!),
                                TextButton(
                                    onPressed: _load,
                                    child: Text(t('다시 시도', 'Retry')))
                              ]))
                    : AbsorbPointer(
                        absorbing: _busy,
                        child: Form(
                            key: _form,
                            child: SingleChildScrollView(
                                controller: _scroll,
                                padding:
                                    const EdgeInsets.fromLTRB(18, 8, 18, 32),
                                child: Center(
                                    child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 960),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Container(
                                                  padding:
                                                      const EdgeInsets.all(18),
                                                  decoration: BoxDecoration(
                                                      color: ScoutStyle.mint,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              18)),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                            t('PRACTICE · 가상 자료로 안심 체험',
                                                                'PRACTICE · Explore with fictional data'),
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .titleMedium),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(t(
                                                            '이 기기에만 저장됩니다. 발송·공개·AI는 모의 실행이며 누구나 무료로 체험할 수 있어요.',
                                                            'Saved on this device only. Sending, publishing and AI are simulated. Free for everyone to try.'))
                                                      ])),
                                              const SizedBox(height: 20),
                                              Text(text(lesson.title),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineMedium),
                                              const SizedBox(height: 8),
                                              Text(text(lesson.goal)),
                                              const SizedBox(height: 16),
                                              panel(
                                                  t('이번에는 이렇게 해보세요',
                                                      'Try this now'),
                                                  [
                                                    Text(text(guideSampleTasks[
                                                        lesson.id]!)),
                                                  ]),
                                              ExpansionTile(
                                                  title: Text(t(
                                                      '실제 업무에서의 단계 참고',
                                                      'Reference steps for your own work')),
                                                  children: [
                                                    for (var i = 0;
                                                        i < lesson.steps.length;
                                                        i++)
                                                      ListTile(
                                                          title: LocalizedText(
                                                              '${i + 1}. ${text(lesson.steps[i].title)}'),
                                                          subtitle: Text(text(
                                                              lesson.steps[i]
                                                                  .body)))
                                                  ]),
                                              const SizedBox(height: 16),
                                              if (_store.recovered)
                                                note(
                                                    '이전에 저장한 샘플 형식을 읽을 수 없어 새 연습자료를 준비했습니다.',
                                                    'Unreadable saved samples were replaced with fresh practice data.'),
                                              if (_error != null)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 16),
                                                    child: Text(_error!,
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .error))),
                                              ...switch (lesson.audience) {
                                                GuideAudience.home =>
                                                  homeContent(),
                                                GuideAudience.supplier =>
                                                  supplierContent(),
                                                GuideAudience.professional =>
                                                  lesson.id.startsWith('buy-')
                                                      ? purchaseContent()
                                                      : chefContent()
                                              },
                                              if (_saved)
                                                Container(
                                                    key: const Key(
                                                        'sample-saved'),
                                                    padding:
                                                        const EdgeInsets.all(
                                                            18),
                                                    color: ScoutStyle.mint,
                                                    child: Text(t(
                                                        '연습자료를 저장했어요. 다시 열어 이어서 사용할 수 있습니다.',
                                                        'Practice records saved. Reopen them to continue.'))),
                                              const SizedBox(height: 18),
                                              Wrap(
                                                  spacing: 10,
                                                  runSpacing: 10,
                                                  children: [
                                                    FilledButton.icon(
                                                        key: const Key(
                                                            'sample-save'),
                                                        onPressed: _busy
                                                            ? null
                                                            : () => save(),
                                                        icon: const Icon(Icons
                                                            .save_outlined),
                                                        label: Text(t(
                                                            _busy
                                                                ? '저장 중…'
                                                                : '연습 내용 저장',
                                                            _busy
                                                                ? 'Saving…'
                                                                : 'Save practice'))),
                                                    if (nextId != null)
                                                      OutlinedButton.icon(
                                                          key: const Key(
                                                              'sample-next'),
                                                          onPressed: _busy
                                                              ? null
                                                              : () async {
                                                                  if (await save() &&
                                                                      context
                                                                          .mounted) {
                                                                    context.replace(
                                                                        guideSamplePath(
                                                                            nextId!));
                                                                  }
                                                                },
                                                          icon: const Icon(Icons
                                                              .arrow_forward),
                                                          label: Text(t(
                                                              '저장하고 다음 체험',
                                                              'Save & next lesson'))),
                                                    TextButton(
                                                        onPressed: leave,
                                                        child: Text(t(
                                                            '튜토리얼로 돌아가기',
                                                            'Back to tutorial')))
                                                  ]),
                                              const SizedBox(height: 24),
                                              Text(t(
                                                  '바로 이동 · 필요한 체험부터 시작해도 자료가 준비되어 있어요.',
                                                  'Jump to a lesson · every lesson has ready-to-use records.')),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    for (final l in sequence)
                                                      ChoiceChip(
                                                          label: Text(
                                                              text(l.title)),
                                                          selected:
                                                              l.id == lesson.id,
                                                          onSelected: _busy
                                                              ? null
                                                              : (_) =>
                                                                  openLesson(
                                                                      l.id))
                                                  ]),
                                            ])))))))));
  }
}
