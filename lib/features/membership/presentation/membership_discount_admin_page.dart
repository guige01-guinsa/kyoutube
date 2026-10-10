import 'package:k_youtube/core/widgets/scout_page.dart';
import '../domain/billing_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

import '../application/membership_providers.dart';
import '../domain/membership.dart';

class MembershipDiscountAdminPage extends ConsumerWidget {
  const MembershipDiscountAdminPage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, [
    SubscriptionDiscountCampaign? campaign,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DiscountCampaignDialog(campaign: campaign),
    );
    if (saved == true) {
      ref.invalidate(managedDiscountCampaignsProvider);
      ref.invalidate(activeDiscountCampaignsProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SubscriptionDiscountCampaign campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('할인 행사 삭제'),
        content: LocalizedText('${campaign.name}: ${context.tr('행사를 삭제할까요?')}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(membershipServiceProvider)
          .deleteDiscountCampaign(campaign.id);
      ref.invalidate(managedDiscountCampaignsProvider);
      ref.invalidate(activeDiscountCampaignsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('할인 행사를 삭제하지 못했습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(managedDiscountCampaignsProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('할인 행사 관리')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const LocalizedText('행사 추가'),
      ),
      body: ScoutPageBody(
          maxWidth: 1000,
          child: campaigns.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(managedDiscountCampaignsProvider),
                icon: const Icon(Icons.refresh),
                label: const LocalizedText('다시 불러오기'),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: LocalizedText('등록된 할인 행사가 없습니다.'),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(managedDiscountCampaignsProvider);
                  await ref.read(managedDiscountCampaignsProvider.future);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final campaign = items[index];
                    final status = _statusLabel(campaign, now);
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.local_offer_outlined),
                        ),
                        title: LocalizedText(campaign.name),
                        subtitle: LocalizedText(
                          '${campaign.headlineKo} / ${campaign.headlineEn}\n'
                          '${context.tr(_planLabel(campaign.planCode))} · ${context.tr(status)}\n'
                          '${DateFormat('yyyy.MM.dd').format(campaign.startsAt.toLocal())}'
                          ' ~ ${DateFormat('yyyy.MM.dd').format(campaign.endsAt.toLocal())}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openEditor(context, ref, campaign);
                            } else {
                              _delete(context, ref, campaign);
                            }
                          },
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem(
                                value: 'edit', child: LocalizedText('수정')),
                            PopupMenuItem(
                                value: 'delete', child: LocalizedText('삭제')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          )),
    );
  }

  String _statusLabel(SubscriptionDiscountCampaign campaign, DateTime now) {
    if (!campaign.isActive) return '중지됨';
    if (now.isBefore(campaign.startsAt)) return '예정';
    if (!now.isBefore(campaign.endsAt)) return '종료';
    return '진행 중';
  }

  String _planLabel(String code) => BillingPlan.byCode(code)?.title ?? code;
}

class _DiscountCampaignDialog extends ConsumerStatefulWidget {
  const _DiscountCampaignDialog({this.campaign});

  final SubscriptionDiscountCampaign? campaign;

  @override
  ConsumerState<_DiscountCampaignDialog> createState() =>
      _DiscountCampaignDialogState();
}

class _DiscountCampaignDialogState
    extends ConsumerState<_DiscountCampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _headlineKoController;
  late final TextEditingController _headlineEnController;
  late final TextEditingController _offerIdController;
  late String _planCode;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    _nameController = TextEditingController(text: campaign?.name ?? '');
    _headlineKoController =
        TextEditingController(text: campaign?.headlineKo ?? '');
    _headlineEnController =
        TextEditingController(text: campaign?.headlineEn ?? '');
    _offerIdController =
        TextEditingController(text: campaign?.googlePlayOfferId ?? '');
    _planCode =
        BillingPlan.byCode(campaign?.planCode ?? '')?.code ?? 'plus_monthly';
    final today = DateTime.now();
    _startsAt = campaign?.startsAt.toLocal() ??
        DateTime(today.year, today.month, today.day);
    _endsAt = campaign?.endsAt.toLocal() ??
        DateTime(today.year, today.month, today.day + 7, 23, 59, 59);
    _isActive = campaign?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _headlineKoController.dispose();
    _headlineEnController.dispose();
    _offerIdController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startsAt = DateTime(selected.year, selected.month, selected.day);
      } else {
        _endsAt =
            DateTime(selected.year, selected.month, selected.day, 23, 59, 59);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_endsAt.isAfter(_startsAt)) {
      setState(() => _error = '종료일은 시작일보다 뒤여야 합니다.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membershipServiceProvider).saveDiscountCampaign(
            id: widget.campaign?.id,
            name: _nameController.text.trim(),
            headlineKo: _headlineKoController.text.trim(),
            headlineEn: _headlineEnController.text.trim(),
            planCode: _planCode,
            googlePlayOfferId: _offerIdController.text.trim(),
            startsAt: _startsAt,
            endsAt: _endsAt,
            isActive: _isActive,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '할인 행사를 저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: LocalizedText(widget.campaign == null ? '할인 행사 추가' : '할인 행사 수정'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: context.tr('행사 이름')),
                  maxLength: 80,
                  validator: _required,
                ),
                TextFormField(
                  controller: _headlineKoController,
                  decoration:
                      InputDecoration(labelText: context.tr('한국어 안내 문구')),
                  maxLength: 120,
                  validator: _required,
                ),
                TextFormField(
                  controller: _headlineEnController,
                  decoration:
                      InputDecoration(labelText: context.tr('영어 안내 문구')),
                  maxLength: 120,
                  validator: _required,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _planCode,
                  decoration: InputDecoration(labelText: context.tr('적용 상품')),
                  items: [
                    for (final plan in BillingPlan.plans)
                      DropdownMenuItem(
                          value: plan.code, child: LocalizedText(plan.title))
                  ],
                  onChanged: (value) => setState(() => _planCode = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _offerIdController,
                  decoration: InputDecoration(
                    labelText: context.tr('Google Play 혜택 ID'),
                    helperText: context.tr('Play Console에 등록한 혜택 ID와 같아야 합니다.'),
                  ),
                  maxLength: 80,
                  validator: _required,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('시작일'),
                  trailing: Text(DateFormat('yyyy.MM.dd').format(_startsAt)),
                  onTap: () => _pickDate(start: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('종료일'),
                  trailing: Text(DateFormat('yyyy.MM.dd').format(_endsAt)),
                  onTap: () => _pickDate(start: false),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('활성화'),
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

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? context.tr('필수 항목입니다.') : null;
}
