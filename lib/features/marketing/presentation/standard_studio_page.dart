import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/marketing_providers.dart';
import '../data/standard_studio_repository.dart';

class StandardStudioPage extends ConsumerStatefulWidget {
  const StandardStudioPage({super.key});
  @override
  ConsumerState<StandardStudioPage> createState() => _StandardStudioPageState();
}

class _StandardStudioPageState extends ConsumerState<StandardStudioPage> {
  bool _busy = false;
  String? _error;
  ({String action, StandardRow values})? _pending;
  final _opened = <String>{};
  final _reviewed = <String>{};
  final _sources = <String>{};

  Future<void> _command(String action, StandardRow values) async {
    setState(() {
      _busy = true;
      _error = null;
      _pending = (action: action, values: values);
    });
    try {
      await ref.read(standardStudioRepositoryProvider).command(action, values);
      _pending = null;
      ref.invalidate(standardStudioProvider);
    } catch (error) {
      // A server rejection is known not to have queued work. An uncertain network
      // response retains the exact id/payload; never offer a fresh paid request.
      if (error is PostgrestException &&
          (error.message.startsWith('STORY_') ||
              error.message.contains('ADMIN_MFA_REQUIRED'))) {
        _pending = null;
        ref.invalidate(standardStudioProvider);
      }
      if (mounted) setState(() => _error = standardError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(List<StandardRow> series) async {
    String food = '',
        presenter =
            '아름답고 단정한 한국인 할머니. 따뜻하고 또렷한 여성 목소리, 가벼운 유머. 실존 인물을 모사하지 않는다.';
    String? seriesId = series.firstOrNull?['id'] as String?;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('새 음식 · 한국어 1분'),
              content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                      child: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            DropdownButtonFormField<String>(
                                initialValue: seriesId,
                                decoration:
                                    const InputDecoration(labelText: '한국어 시리즈'),
                                items: series
                                    .map((s) => DropdownMenuItem(
                                        value: s['id'] as String,
                                        child: Text(s['title'] as String)))
                                    .toList(),
                                validator: (v) =>
                                    v == null ? '한국어 시리즈가 필요합니다.' : null,
                                onChanged: (v) => seriesId = v),
                            TextFormField(
                                decoration:
                                    const InputDecoration(labelText: '음식 이름'),
                                maxLength: 30,
                                onChanged: (v) => food = v.trim(),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? '음식 이름을 입력하세요.'
                                    : null),
                            TextFormField(
                                initialValue: presenter,
                                decoration: const InputDecoration(
                                    labelText: '진행자·목소리·지킬 설정'),
                                minLines: 3,
                                maxLines: 6,
                                maxLength: 500,
                                onChanged: (v) => presenter = v.trim(),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? '설정을 입력하세요.'
                                    : null),
                            const Text(
                                '기획 저장은 무료입니다. 유료 작업은 견적 확인 후 별도로 시작합니다.'),
                          ])))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(dialog, true);
                      }
                    },
                    child: const Text('기획 저장'))
              ],
            ));
    if (accepted == true && mounted) {
      await _command('create', {
        'id': standardRequestId(),
        'series_id': seriesId,
        'food': food,
        'presenter': presenter,
      });
    }
  }

  Future<void> _queue(
      String stage, StandardRow project, StandardRow config) async {
    final cost = stage == 'upload' ? 0 : config['${stage}_usd'];
    if (cost == null) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(stage == 'upload' ? '비공개 업로드 확인' : '작업 비용 확인'),
              content: Text(
                  '예상 예약액: USD $cost\n실제 청구 상한이 아닙니다. 실패 작업도 예약액을 보존하며 자동 재시도하지 않습니다.\n\n'
                  '${stage == 'sample' ? '첫 장면의 짧은 시험 음성만 생성합니다.' : stage == 'render' ? '한국어 60초 영상 한 편을 제작합니다.' : stage == 'upload' ? '확인한 영상만 비공개로 업로드합니다.' : '출처를 조사하고 한국어 원고를 작성합니다.'}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('승인'))
              ],
            ));
    if (accepted != true || !mounted) return;
    await _command(stage, {
      'id': standardRequestId(),
      'project_id': project['id'],
      'revision': project['revision'],
      'quote_revision': config['revision'],
      'cost_confirmed': true,
      if (stage == 'sample' || stage == 'render') 'sources_reviewed': true,
      if (stage == 'upload') ...{
        'preview_reviewed': true,
        'sha256': (project['preview'] as Map)['sha256']
      },
    });
  }

  Future<void> _open(StandardRow artifact, bool sample) async {
    setState(() => _busy = true);
    try {
      final url = await ref
          .read(standardStudioRepositoryProvider)
          .preview(artifact['path'] as String, sample: sample);
      if (!await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        throw StateError('not_opened');
      }
      if (mounted) setState(() => _opened.add(artifact['sha256'] as String));
    } catch (_) {
      if (mounted) setState(() => _error = '미리보기를 열지 못했습니다. 다시 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StandardRow project) async {
    final plan = Map<String, dynamic>.from(project['plan'] as Map);
    final scenes = (plan['scenes'] as List)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('한국어 원고 수정'),
              content: SizedBox(
                  width: 650,
                  child: SingleChildScrollView(
                      child: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text(
                                '수정하면 이전 시험 음성 승인은 해제됩니다. 출처 연결은 유지됩니다.'),
                            TextFormField(
                                initialValue: plan['title'] as String,
                                maxLength: 45,
                                decoration:
                                    const InputDecoration(labelText: '제목'),
                                onChanged: (v) => plan['title'] = v.trim(),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? '제목을 입력하세요.'
                                    : null),
                            for (var i = 0; i < scenes.length; i++) ...[
                              Text(
                                  '${i + 1}번째 장면 · ${i * 10}~${(i + 1) * 10}초'),
                              TextFormField(
                                  initialValue: scenes[i]['spoken'] as String,
                                  maxLength: 50,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                      labelText: '읽어 줄 말'),
                                  onChanged: (v) =>
                                      scenes[i]['spoken'] = v.trim(),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                          ? '원고를 입력하세요.'
                                          : null),
                              TextFormField(
                                  initialValue: scenes[i]['caption'] as String,
                                  maxLength: 60,
                                  maxLines: 3,
                                  decoration:
                                      const InputDecoration(labelText: '화면 글'),
                                  onChanged: (v) =>
                                      scenes[i]['caption'] = v.trim(),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                          ? '화면 글을 입력하세요.'
                                          : null),
                            ],
                          ])))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(dialog, true);
                      }
                    },
                    child: const Text('저장'))
              ],
            ));
    if (accepted == true && mounted) {
      await _command('save_plan', {
        'project_id': project['id'],
        'revision': project['revision'],
        'plan': {...plan, 'scenes': scenes},
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('한국어 1분 제작소'), actions: [
          IconButton(
              tooltip: '새로고침',
              onPressed:
                  _busy ? null : () => ref.invalidate(standardStudioProvider),
              icon: const Icon(Icons.refresh))
        ]),
        body: ref.watch(marketingAdminProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('관리자 권한을 확인하지 못했습니다.')),
              data: (allowed) => !allowed
                  ? const Center(child: Text('마케팅 관리자만 이용할 수 있습니다.'))
                  : ref.watch(standardStudioProvider).when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(standardError(e))),
                      data: _content),
            ),
      );

  Widget _content(StandardRow data) {
    final config = Map<String, dynamic>.from(data['config'] as Map);
    final seen =
        DateTime.tryParse(config['standard_worker_seen_at'] as String? ?? '');
    final ready = config['enabled'] == true &&
        config['standard_enabled'] == true &&
        seen != null &&
        DateTime.now().toUtc().difference(seen).inMinutes < 20;
    final editable = !_busy && _pending == null;
    final produce = editable && ready;
    final series = standardRows(data, 'series');
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('한국어만 · 60초 · 원고 → 시험 음성 → 영상 → 비공개 검토'),
      Text(ready ? '제작 서버 연결됨' : '운영 연결 대기 · 새 유료 작업은 잠겨 있습니다.'),
      const Text('3분·5분 제작은 안정화 후 추가합니다. 공개 게시와 유료 재시도는 자동 실행하지 않습니다.'),
      if (_error != null)
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_busy) const LinearProgressIndicator(),
      if (_pending != null)
        OutlinedButton(
            onPressed: _busy
                ? null
                : () => _command(_pending!.action, _pending!.values),
            child: const Text('같은 요청 결과 확인')),
      FilledButton.icon(
          onPressed:
              editable && series.isNotEmpty ? () => _create(series) : null,
          icon: const Icon(Icons.add),
          label: const Text('새 음식 기획')),
      if (series.isEmpty) const Text('기존 제작소에서 한국어 시리즈를 먼저 만들어 주세요.'),
      for (final project in standardRows(data, 'projects'))
        _project(project, config, editable, produce),
      ExpansionTile(title: const Text('작업 기록'), children: [
        for (final job in standardRows(data, 'jobs'))
          ListTile(
              title: Text('${job['stage']} · ${job['status']}'),
              subtitle: Text(
                  '예상 예약 USD ${job['reserved_usd']} · ${job['error_code'] ?? ''}'))
      ]),
    ]);
  }

  Widget _project(
      StandardRow project, StandardRow config, bool editable, bool produce) {
    final status = project['status'] as String;
    final plan = project['plan'] as Map?;
    final identity = '${project['id']}:${project['plan_revision']}';
    final sample = project['sample'] as Map?;
    final preview = project['preview'] as Map?;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${project['food']} · ${standardStatus(status)}',
                  style: Theme.of(context).textTheme.titleMedium),
              if (status == 'planning')
                FilledButton(
                    onPressed:
                        produce ? () => _queue('draft', project, config) : null,
                    child: const Text('자료 조사와 원고 작성')),
              if (plan != null)
                ExpansionTile(title: Text(plan['title'] as String), children: [
                  for (final scene in plan['scenes'] as List)
                    ListTile(
                        title: Text(scene['spoken'] as String),
                        subtitle: Text(scene['caption'] as String)),
                  for (final source in plan['sources'] as List)
                    ListTile(
                        title: Text(source['title'] as String),
                        subtitle: SelectableText(source['url'] as String)),
                ]),
              if (plan != null &&
                  ['draft', 'sample_review', 'sample_approved', 'needs_review']
                      .contains(status))
                OutlinedButton(
                    onPressed: editable ? () => _edit(project) : null,
                    child: const Text('원고 수정')),
              if (status == 'draft') ...[
                CheckboxListTile(
                    title: const Text('원고와 음식 정보의 출처를 검토했습니다.'),
                    value: _sources.contains(identity),
                    onChanged: editable
                        ? (v) => setState(() {
                              v == true
                                  ? _sources.add(identity)
                                  : _sources.remove(identity);
                            })
                        : null),
                FilledButton(
                    onPressed: produce && _sources.contains(identity)
                        ? () => _queue('sample', project, config)
                        : null,
                    child: const Text('첫 장면 시험 음성 만들기')),
              ],
              if (sample != null &&
                  ['sample_review', 'sample_approved'].contains(status)) ...[
                OutlinedButton(
                    onPressed: editable
                        ? () => _open(Map<String, dynamic>.from(sample), true)
                        : null,
                    child: const Text('시험 음성 듣기')),
                if (status == 'sample_review') ...[
                  CheckboxListTile(
                      title: const Text('직접 듣고 발음·속도·목소리를 확인했습니다.'),
                      value: _reviewed.contains(sample['sha256']),
                      onChanged: editable && _opened.contains(sample['sha256'])
                          ? (v) => setState(() {
                                v == true
                                    ? _reviewed.add(sample['sha256'] as String)
                                    : _reviewed.remove(sample['sha256']);
                              })
                          : null),
                  FilledButton(
                      onPressed:
                          editable && _reviewed.contains(sample['sha256'])
                              ? () => _command('approve_sample', {
                                    'project_id': project['id'],
                                    'revision': project['revision'],
                                    'sha256': sample['sha256'],
                                    'listened': true,
                                  })
                              : null,
                      child: const Text('이 음성으로 제작')),
                ],
              ],
              if (status == 'sample_approved') ...[
                if (config['standard_capture_ready'] != true)
                  const Text('실제 앱 안내 화면 준비 중 · 유료 영상 제작은 아직 시작하지 않습니다.'),
                FilledButton(
                    onPressed:
                        produce && config['standard_capture_ready'] == true
                            ? () => _queue('render', project, config)
                            : null,
                    child: const Text('한국어 60초 영상 제작')),
              ],
              if (preview != null &&
                  ['preview', 'uploaded'].contains(status)) ...[
                OutlinedButton(
                    onPressed: editable
                        ? () => _open(Map<String, dynamic>.from(preview), false)
                        : null,
                    child: const Text('영상 미리보기')),
                if (status == 'preview') ...[
                  CheckboxListTile(
                      title: const Text('영상·음성·자막·음악을 확인했습니다.'),
                      value: _reviewed.contains(preview['sha256']),
                      onChanged: editable && _opened.contains(preview['sha256'])
                          ? (v) => setState(() {
                                v == true
                                    ? _reviewed.add(preview['sha256'] as String)
                                    : _reviewed.remove(preview['sha256']);
                              })
                          : null),
                  FilledButton(
                      onPressed:
                          produce && _reviewed.contains(preview['sha256'])
                              ? () => _queue('upload', project, config)
                              : null,
                      child: const Text('비공개 업로드')),
                ],
                if (status == 'uploaded' &&
                    RegExp(r'^[A-Za-z0-9_-]{11}$')
                        .hasMatch(preview['youtube_id'] as String? ?? ''))
                  SelectableText(
                      'https://www.youtube.com/watch?v=${preview['youtube_id']}'),
              ],
              if (status == 'needs_review')
                const Text(
                    '실패·응답 유실 가능성이 있어 자동 재시도하지 않습니다. 작업 기록과 저장된 파일을 확인해야 합니다.'),
            ])));
  }
}
