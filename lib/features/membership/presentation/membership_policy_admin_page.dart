import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

import '../application/membership_providers.dart';
import '../domain/membership.dart';

class MembershipPolicyAdminPage extends ConsumerWidget {
  const MembershipPolicyAdminPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    MembershipPlanPolicy policy,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MembershipPolicyDialog(policy: policy),
    );
    if (saved == true) {
      ref.invalidate(managedMembershipPlanPoliciesProvider);
      ref.invalidate(activeMembershipPlanPoliciesProvider);
      ref.invalidate(membershipInfoProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(managedMembershipPlanPoliciesProvider);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('요금제 정책 관리')),
      body: ScoutPageBody(
          maxWidth: 1000,
          child: policies.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(managedMembershipPlanPoliciesProvider),
                icon: const Icon(Icons.refresh),
                label: const LocalizedText('다시 불러오기'),
              ),
            ),
            data: (items) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(managedMembershipPlanPoliciesProvider);
                ref.invalidate(youtubeDraftSuccessStatsProvider);
                await ref.read(managedMembershipPlanPoliciesProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  const _YoutubeDraftSuccessCard(),
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: LocalizedText(
                        '결제 가격은 Google Play Console에서 먼저 변경하세요. '
                        '이 화면의 기준 가격은 운영 기록과 안내용이며 실제 결제 금액을 바꾸지 않습니다.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final policy in items) ...<Widget>[
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(policy.code == 'free'
                              ? Icons.person_outline
                              : Icons.workspace_premium_outlined),
                        ),
                        title: LocalizedText(policy.displayName),
                        subtitle: LocalizedText(
                          '${policy.allowanceLabelFor(Localizations.localeOf(context).languageCode)}\n'
                          '${policy.recipeModel} · ${NumberFormat.decimalPattern().format(policy.priceKrw)} ${context.tr('원')} · '
                          '${context.tr(policy.isActive ? '활성' : '중지됨')}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: context.tr('정책 수정'),
                          icon: const Icon(Icons.tune),
                          onPressed: () => _edit(context, ref, policy),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          )),
    );
  }
}

class _YoutubeDraftSuccessCard extends ConsumerWidget {
  const _YoutubeDraftSuccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(youtubeDraftSuccessStatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: stats.when(
          loading: () => const Center(child: LinearProgressIndicator()),
          error: (_, __) => Row(
            children: <Widget>[
              const Expanded(
                child: LocalizedText('YouTube 초안 성공률을 불러오지 못했습니다.'),
              ),
              IconButton(
                tooltip: context.tr('다시 불러오기'),
                onPressed: () =>
                    ref.invalidate(youtubeDraftSuccessStatsProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          data: (value) {
            if (value.attempts == 0) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LocalizedText(
                    'YouTube 초안 성공률 (최근 30일)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  LocalizedText('아직 집계할 초안 시도가 없습니다.'),
                ],
              );
            }
            final progress = (value.successRate / 100).clamp(0.0, 1.0);
            final reachedTarget = value.successRate >= 90;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const LocalizedText(
                  'YouTube 초안 성공률 (최근 30일)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                LocalizedText(
                  '${value.successRate.toStringAsFixed(1)}% · '
                  '${context.tr('성공')} ${value.successes}/${value.attempts}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: reachedTarget
                            ? colorScheme.primary
                            : colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                LocalizedText(
                  '${context.tr('자막 사용')} ${value.transcriptAttempts} · '
                  '${context.tr('자동 보완')} ${value.repairedAttempts}',
                ),
                if (!reachedTarget) ...<Widget>[
                  const SizedBox(height: 6),
                  const LocalizedText('목표 성공률 90%까지 개선 데이터를 수집하고 있습니다.'),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MembershipPolicyDialog extends ConsumerStatefulWidget {
  const _MembershipPolicyDialog({required this.policy});

  final MembershipPlanPolicy policy;

  @override
  ConsumerState<_MembershipPolicyDialog> createState() =>
      _MembershipPolicyDialogState();
}

class _MembershipPolicyDialogState
    extends ConsumerState<_MembershipPolicyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceController;
  late final TextEditingController _dailyController;
  late final TextEditingController _weeklyController;
  late final TextEditingController _monthlyController;
  late String _model;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _priceController = TextEditingController(text: '${policy.priceKrw}');
    _dailyController = TextEditingController(text: '${policy.dailyLimit}');
    _weeklyController = TextEditingController(text: '${policy.weeklyLimit}');
    _monthlyController = TextEditingController(text: '${policy.monthlyLimit}');
    _model = policy.recipeModel;
    _isActive = policy.isActive;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = int.parse(_priceController.text);
    final daily = int.parse(_dailyController.text);
    final weekly = int.parse(_weeklyController.text);
    final monthly = int.parse(_monthlyController.text);
    if (weekly < daily || monthly < weekly) {
      setState(() => _error = '사용 한도는 일간 ≤ 주간 ≤ 월간 순서여야 합니다.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membershipServiceProvider).updatePlanPolicy(
            MembershipPlanPolicy(
              code: widget.policy.code,
              displayName: widget.policy.displayName,
              productId: widget.policy.productId,
              priceKrw: price,
              billingPeriod: widget.policy.billingPeriod,
              recipeModel: _model,
              dailyLimit: daily,
              weeklyLimit: weekly,
              monthlyLimit: monthly,
              isActive: _isActive,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '요금제 정책을 저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFree = widget.policy.code == 'free';
    return AlertDialog(
      title: LocalizedText(widget.policy.displayName),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _priceController,
                  enabled: !isFree,
                  decoration: InputDecoration(
                    labelText: context.tr('내부 기준 가격(원)'),
                    helperText: context.tr('실제 가격은 Play Console에서 변경해야 합니다.'),
                  ),
                  keyboardType: TextInputType.number,
                  validator: _nonNegativeInteger,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  decoration: InputDecoration(labelText: context.tr('AI 모델')),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'gpt-4o-mini',
                      child: LocalizedText('gpt-4o-mini'),
                    ),
                    DropdownMenuItem(
                      value: 'gpt-5.4-mini',
                      child: LocalizedText('gpt-5.4-mini'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _model = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dailyController,
                  decoration:
                      InputDecoration(labelText: context.tr('일간 AI 한도')),
                  keyboardType: TextInputType.number,
                  validator: _nonNegativeInteger,
                ),
                TextFormField(
                  controller: _weeklyController,
                  decoration:
                      InputDecoration(labelText: context.tr('주간 AI 한도')),
                  keyboardType: TextInputType.number,
                  validator: _nonNegativeInteger,
                ),
                TextFormField(
                  controller: _monthlyController,
                  decoration:
                      InputDecoration(labelText: context.tr('월간 AI 한도')),
                  keyboardType: TextInputType.number,
                  validator: _nonNegativeInteger,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('상품 활성화'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                if (_error != null)
                  LocalizedText(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const LocalizedText('취소'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: LocalizedText(_saving ? '저장 중...' : '저장'),
        ),
      ],
    );
  }

  String? _nonNegativeInteger(String? value) {
    final number = int.tryParse((value ?? '').trim());
    if (number == null || number < 0) return context.tr('0 이상의 정수를 입력해 주세요.');
    return null;
  }
}
