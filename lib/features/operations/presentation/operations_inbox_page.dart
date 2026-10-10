import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/localization/app_localizations.dart';
import '../data/operations_alerts_repository.dart';
import '../data/ops_push_service.dart';
import '../domain/operations_alert.dart';

class OperationsInboxPage extends ConsumerStatefulWidget {
  const OperationsInboxPage({super.key});
  @override
  ConsumerState<OperationsInboxPage> createState() =>
      _OperationsInboxPageState();
}

class _OperationsInboxPageState extends ConsumerState<OperationsInboxPage> {
  int? _before;
  bool _busy = false;
  bool get _en => AppLocalizations.of(context).isEnglish;
  String _t(String ko, String en) => AppLocalizations.of(context).bilingual(ko, en);
  @override
  void initState() {
    super.initState();
    OpsPushService.received.addListener(_refresh);
  }

  @override
  void dispose() {
    OpsPushService.received.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(opsInboxProvider(_before));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t('설정을 저장했습니다.', 'Settings saved.'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_t('완료하지 못했습니다. 관리자 권한·알림 권한·연결 상태를 확인해 주세요.',
                'Could not complete. Check admin access, notification permission and connection.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _budget(int current) async {
    var amount = (current / 1073741824).toStringAsFixed(0);
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(_t('DB 용량 알림 기준', 'Database alert budget')),
              content: Form(
                  key: form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_t('알림 계산에 사용할 GB 기준입니다. 서버 용량이나 요금제는 바뀌지 않습니다.',
                        'This budget is for alerts. It does not change server capacity or billing.')),
                    TextFormField(
                        initialValue: amount,
                        onChanged: (value) => amount = value,
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          return number == null || number < 1 || number > 102400
                              ? _t('1~102400의 정수를 입력하세요.',
                                  'Enter an integer from 1 to 102400.')
                              : null;
                        },
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'GiB (1–102400)')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_t('취소', 'Cancel'))),
                FilledButton(
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      Navigator.pop(context, int.parse(amount) * 1073741824);
                    },
                    child: Text(_t('저장', 'Save')))
              ],
            ));
    if (!mounted || value == null) return;
    await _run(
        () => ref.read(opsAlertsRepositoryProvider).setDatabaseBudget(value));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(opsInboxProvider(_before));
    return Scaffold(
      appBar: AppBar(title: Text(_t('운영 알림함', 'Operations inbox')), actions: [
        IconButton(
            tooltip: _t('새로고침', 'Refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh))
      ]),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_t('관리자 권한 또는 서버 연결을 확인해 주세요. 알림 기능 적용 전에는 조회할 수 없습니다.',
                      'Check admin access and server connection. The alert service must be deployed first.')),
                  TextButton(
                      onPressed: _refresh, child: Text(_t('다시 시도', 'Retry')))
                ]))),
        data: (data) {
          final checked =
              DateTime.tryParse(data['last_checked_at'] as String? ?? '');
          final stale = checked == null ||
              DateTime.now().difference(checked).inMinutes >= 15;
          final items = (data['events'] as List? ?? [])
              .map((e) => OperationsAlert(Map<String, dynamic>.from(e as Map)))
              .toList();
          return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    ScoutPageHeading(
                      title: _t('운영 알림과 점검', 'Operations alerts and checks'),
                      subtitle: _t('서비스 상태를 확인하고 이 기기에서 받을 알림을 설정하세요.',
                          'Review service health and manage notifications for this device.'),
                      icon: Icons.notifications_active_outlined,
                    ),
                    const SizedBox(height: 24),
                    Card(
                        color: stale
                            ? Theme.of(context).colorScheme.errorContainer
                            : null,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      stale
                                          ? _t('자동 감시 실행 상태를 확인하세요',
                                              'Check the monitoring schedule')
                                          : _t('운영 상태 감시 중',
                                              'Operations monitoring'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 8),
                                  Text(checked == null
                                      ? _t(
                                          '아직 자동 점검 기록이 없습니다. 배포 및 예약 실행이 필요합니다.',
                                          'No scheduled check recorded. Deployment and scheduling are required.')
                                      : _t('마지막 점검: ', 'Last check: ') +
                                          DateFormat('yyyy-MM-dd HH:mm')
                                              .format(checked.toLocal())),
                                  LocalizedText(
                                      '${_t('전송 대기 / 실패: ', 'Push pending / failed: ')}${data['pending_push'] ?? 0} / ${data['failed_push'] ?? 0}'),
                                  if (data['last_dispatch_ok'] != true)
                                    Text(_t('푸시 전송 서비스의 설정 또는 실행 상태를 확인하세요.',
                                        'Check push delivery configuration and run status.')),
                                ]))),
                    const SizedBox(height: 8),
                    Text(_t(
                        '새 경고·위험·복구를 알립니다. 푸시에는 상세 수치를 포함하지 않습니다. 서버 사양은 자동으로 변경하지 않습니다.',
                        'New warnings, critical states and recovery are recorded. Push messages contain no detailed metrics. Server capacity is not changed automatically.')),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() =>
                                  OpsPushService.enable(Localizations.localeOf(context).languageCode)),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: Text(_t(
                              '이 휴대폰에서 푸시 받기', 'Enable push on this phone'))),
                      OutlinedButton(
                          onPressed:
                              _busy ? null : () => _run(OpsPushService.disable),
                          child: Text(_t('푸시 끄기', 'Disable push'))),
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () => _budget(
                                  (data['database_budget_bytes'] as num? ??
                                          8589934592)
                                      .toInt()),
                          child: Text(
                              _t('DB 알림 기준 설정', 'Set database alert budget'))),
                    ]),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      Text(_t('이 기간에 기록된 알림이 없습니다.',
                          'No alerts recorded for this page.')),
                    for (final item in items)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                              item.severity == 'recovered'
                                                  ? Icons.check_circle_outline
                                                  : Icons.warning_amber_rounded,
                                              color: item.severity == 'critical'
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : null),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: LocalizedText(item.title(_en),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium))
                                        ]),
                                    const SizedBox(height: 6),
                                    LocalizedText(item.severity == 'recovered'
                                        ? _t('복구', 'Recovered')
                                        : item.severity == 'critical'
                                            ? _t('위험', 'Critical')
                                            : _t('주의', 'Warning')),
                                    Text(DateFormat('yyyy-MM-dd HH:mm')
                                        .format(item.createdAt.toLocal())),
                                    if (item.measurement(_en).isNotEmpty)
                                      LocalizedText(item.measurement(_en)),
                                    const SizedBox(height: 8),
                                    Text(item.severity == 'recovered'
                                        ? _t('새 점검에서 복구 기준을 충족했습니다.',
                                            'A new check met the recovery threshold.')
                                        : item.action(_en)),
                                    TextButton(
                                        onPressed: _busy || item.isRead
                                            ? null
                                            : () => _run(() => ref
                                                .read(
                                                    opsAlertsRepositoryProvider)
                                                .markRead(item.id)),
                                        child: Text(item.isRead
                                            ? _t('확인함', 'Read')
                                            : _t('확인 표시', 'Mark read'))),
                                  ]))),
                    Wrap(spacing: 8, children: [
                      if (_before != null)
                        TextButton(
                            onPressed: () => setState(() => _before = null),
                            child: Text(_t('최신 알림', 'Latest alerts'))),
                      if (items.length == 50)
                        TextButton(
                            onPressed: () =>
                                setState(() => _before = items.last.id),
                            child: Text(_t('이전 알림', 'Older alerts'))),
                    ]),
                  ])));
        },
      ),
    );
  }
}
