import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'membership_features_card.dart';

import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_providers.dart';
import '../application/membership_providers.dart';
import '../data/membership_service.dart';
import '../domain/membership.dart';
import '../domain/billing_plan.dart';
import 'package:url_launcher/url_launcher.dart';

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  MembershipProducts? _products;
  bool _loadingStore = true;
  bool _processing = false;
  bool _annual = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final service = ref.read(membershipServiceProvider);
    _purchaseSubscription = service.purchaseUpdates.listen(
      _handlePurchaseUpdates,
      onError: (_) => _setMessage('Google Play 결제 상태를 확인하지 못했습니다.'),
    );
    unawaited(_loadProducts());
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ref.read(membershipServiceProvider).loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loadingStore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingStore = false;
        _message = 'Google Play 상품을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (!MembershipService.productIds.contains(purchase.productID)) continue;
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() {
            _processing = false;
            _message = '결제 승인 대기 중입니다. Google Play에서 진행 상태를 확인해 주세요.';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) {
          setState(() {
            _processing = false;
            _message = '결제가 취소되었습니다.';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _processing = false;
            _message = purchase.error?.message ?? '결제를 완료하지 못했습니다.';
          });
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          await ref.read(membershipServiceProvider).verifyPurchase(purchase);
          ref.invalidate(membershipInfoProvider);
          ref.invalidate(membershipFeaturesProvider);
          if (mounted) {
            setState(() {
              _processing = false;
              _message = 'Google Play 구독이 확인되었습니다.';
            });
          }
        } on MembershipException catch (error) {
          if (mounted) {
            setState(() {
              _processing = false;
              _message = error.message;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _processing = false;
              _message = '구독 확인 중 오류가 발생했습니다.';
            });
          }
        }
      }
    }
  }

  Future<void> _purchase(String planCode) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }
    final product = _products?.forPlan(planCode);
    if (product == null) {
      _setMessage('Play Console에서 구독 상품을 활성화한 후 구매할 수 있습니다.');
      return;
    }
    final info = ref.read(membershipInfoProvider).valueOrNull;
    if (info == null) return;
    if (info.isPaid) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: LocalizedText(
                      Localizations.localeOf(context).languageCode != 'ko'
                          ? 'Change subscription'
                          : '구독 변경'),
                  content: LocalizedText(Localizations.localeOf(context).languageCode ==
                          'en'
                      ? 'Your new plan starts at the next billing date. Current benefits stay available until then. Review the price and date in Google Play.'
                      : '새 요금제는 다음 결제일부터 적용됩니다. 그때까지 현재 기능을 이용합니다. Google Play에서 가격과 적용일을 확인해 주세요.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const LocalizedText('취소')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const LocalizedText('확인'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _processing = true;
      _message = null;
    });
    try {
      await ref.read(membershipServiceProvider).startPurchase(
            product: product,
            applicationUserName: user.id,
            currentPlanCode: info.isPaid ? info.planCode : null,
          );
    } on MembershipException catch (error) {
      if (mounted) {
        ref.invalidate(membershipInfoProvider);
        ref.invalidate(membershipFeaturesProvider);
        setState(() {
          _processing = false;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _processing = false;
          _message = 'Google Play 결제 화면을 열지 못했습니다.';
        });
      }
    }
  }

  Future<void> _restore() async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    setState(() {
      _processing = true;
      _message = '구독 내역을 확인하고 있습니다.';
    });
    try {
      await ref.read(membershipServiceProvider).restorePurchases(user.id);
      if (mounted) setState(() => _processing = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _processing = false;
          _message = '구독 복원을 시작하지 못했습니다.';
        });
      }
    }
  }

  void _setMessage(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(membershipInfoProvider);
    final planPolicies =
        ref.watch(activeMembershipPlanPoliciesProvider).valueOrNull ??
            const <MembershipPlanPolicy>[];
    final english = Localizations.localeOf(context).languageCode != 'ko';

    return Scaffold(
      appBar: AppBar(title: const LocalizedText('회원 및 구독 관리')),
      body: ScoutPageBody(
          maxWidth: 1000,
          child: Stack(
            children: <Widget>[
              RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(membershipInfoProvider);
                  ref.invalidate(membershipFeaturesProvider);
                  ref.invalidate(activeDiscountCampaignsProvider);
                  ref.invalidate(activeMembershipPlanPoliciesProvider);
                  await ref.read(membershipInfoProvider.future);
                  await _loadProducts();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    membership.when(
                      data: (info) => _CurrentMembershipCard(info: info),
                      loading: () => const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                      error: (_, __) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const LocalizedText('회원 정보를 불러오지 못했습니다.'),
                          trailing: IconButton(
                            onPressed: () =>
                                ref.invalidate(membershipInfoProvider),
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const MembershipFeaturesCard(),
                    const SizedBox(height: 20),
                    _MembershipPolicyCard(policies: planPolicies),
                    const SizedBox(height: 20),
                    if (kIsWeb) ...[
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: LocalizedText(
                              '웹에서는 기존 회원권을 사용할 수 있습니다. 신규 결제는 준비 중입니다.'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    LocalizedText('구독 상품',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                              value: false,
                              label: LocalizedText(english ? 'Monthly' : '월간')),
                          ButtonSegment(
                              value: true,
                              label: LocalizedText(english ? 'Annual' : '연간')),
                        ],
                        selected: {
                          _annual
                        },
                        onSelectionChanged: _processing
                            ? null
                            : (values) =>
                                setState(() => _annual = values.single)),
                    const SizedBox(height: 12),
                    for (final plan in BillingPlan.plans
                        .where((p) => p.annual == _annual)) ...[
                      _PlanCard(
                        title: english
                            ? (plan.business ? 'Chef Business' : 'Recipe Plus')
                            : (plan.business ? '셰프 비즈니스' : '레시피 플러스'),
                        price: _products?.forPlan(plan.code)?.price ??
                            (english
                                ? 'Store price unavailable'
                                : '스토어 가격 확인 중'),
                        allowance: english
                            ? 'AI drafts ${plan.ai}/month · Video analysis ${plan.video}/month'
                            : 'AI 초안 월 ${plan.ai}회 · 영상 분석 월 ${plan.video}회',
                        description: english
                            ? 'Stores ${plan.suppliers} · ${plan.requests == null ? 'No monthly request cap' : 'New requests ${plan.requests}/month'} · PDF included${plan.business ? '\nCosts, pricing and sales included' : '\nCosts and sales require Business'}'
                            : '구매처 ${plan.suppliers}개 · 새 요청서 월 ${plan.requests == null ? '제한 없음' : '${plan.requests}건'} · PDF 제공${plan.business ? '\n원가·판매가·매출 제공' : '\n원가·매출은 비즈니스에서 제공'}',
                        selected: membership.valueOrNull?.planCode == plan.code,
                        enabled: !kIsWeb &&
                            !_loadingStore &&
                            !_processing &&
                            membership.hasValue &&
                            !membership.isLoading &&
                            !membership.hasError &&
                            (!membership.requireValue.isPaid ||
                                BillingPlan.byCode(
                                        membership.requireValue.planCode) !=
                                    null) &&
                            _products?.forPlan(plan.code) != null,
                        onPressed: () => _purchase(plan.code),
                      ),
                      const SizedBox(height: 12),
                    ],
                    LocalizedText(english
                        ? 'Annual plans are charged once per year. Monthly limits are the same for monthly and annual plans. Video analysis: up to 20 minutes per video; starting analysis counts toward the video limit. Saved data remains after expiry. Request storage: up to 1,000 records.'
                        : '연간 요금은 1년치가 한 번에 결제됩니다. 같은 등급은 월간·연간의 월 사용 한도가 같습니다. 영상은 최대 20분이며 분석 시작 시 횟수가 차감됩니다. 만료 후에도 저장 데이터는 보관됩니다. 요청서는 최대 1,000건까지 보관합니다.'),
                    if (_loadingStore) ...<Widget>[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (!kIsWeb &&
                        (_products?.errorMessage != null ||
                            (_products?.notFoundIds.isNotEmpty ??
                                false))) ...<Widget>[
                      const SizedBox(height: 12),
                      LocalizedText(
                        'Play Console 상품이 아직 활성화되지 않았거나 현재 계정에서 '
                        '구매할 수 없습니다.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Card(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: LocalizedText(_message!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!kIsWeb)
                      OutlinedButton.icon(
                        onPressed: _processing ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: const LocalizedText('Google Play 구독 복원'),
                      ),
                    TextButton.icon(
                        onPressed: () => launchUrl(
                            Uri.parse(
                                'https://play.google.com/store/account/subscriptions?package=com.kyoutube.app'),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new),
                        label: LocalizedText(english
                            ? 'Manage or cancel in Google Play'
                            : 'Google Play에서 구독 관리·해지')),
                    if (membership.valueOrNull?.isAdmin ?? false) ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push(AppRoutes.membershipAdmin),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const LocalizedText('회원 관리자 화면'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const LocalizedText(
                      '구독은 Google Play에서 자동 갱신됩니다. 해지해도 이미 결제한 '
                      '기간이 끝날 때까지 이용할 수 있습니다. 구매 확정 전에는 유료 '
                      '권한이 부여되지 않습니다.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (_processing)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          )),
    );
  }
}

class _MembershipPolicyCard extends StatelessWidget {
  const _MembershipPolicyCard({required this.policies});

  final List<MembershipPlanPolicy> policies;

  @override
  Widget build(BuildContext context) {
    final free = _policyFor('free');
    final monthly = _policyFor('plus_monthly');
    final annual = _policyFor('business_monthly');
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.info_outline_rounded),
        title: const LocalizedText('요금 및 AI 사용 안내'),
        subtitle: const LocalizedText('무료·유료 한도와 차감 기준을 확인하세요.'),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PolicyLine(
            title: '무료',
            value: free?.allowanceLabelFor(
                  Localizations.localeOf(context).languageCode,
                ) ??
                context.tr('1회/일 · 5회/주 · 10회/월'),
          ),
          _PolicyLine(
            title: 'Recipe Plus',
            value: monthly?.allowanceLabelFor(
                  Localizations.localeOf(context).languageCode,
                ) ??
                (Localizations.localeOf(context).languageCode != 'ko'
                    ? '5/day · 25/week · 50/month'
                    : '5회/일 · 25회/주 · 50회/월'),
          ),
          _PolicyLine(
            title: 'Chef Business',
            value: annual?.allowanceLabelFor(
                  Localizations.localeOf(context).languageCode,
                ) ??
                context.tr('10회/일 · 50회/주 · 100회/월'),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            '성공적으로 만들어진 AI 초안만 차감됩니다. 일·주·월 한도 중 '
            '하나라도 모두 사용하면 해당 기간이 갱신될 때까지 생성이 '
            '제한됩니다. AI가 정리한 분량과 조리법은 저장 전에 확인해 주세요.',
          ),
        ],
      ),
    );
  }

  MembershipPlanPolicy? _policyFor(String code) {
    for (final policy in policies) {
      if (policy.code == code) return policy;
    }
    return null;
  }
}

class _PolicyLine extends StatelessWidget {
  const _PolicyLine({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 94,
            child: LocalizedText(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: LocalizedText(value)),
        ],
      ),
    );
  }
}

class _CurrentMembershipCard extends StatelessWidget {
  const _CurrentMembershipCard({required this.info});

  final MembershipInfo info;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(info.isPaid
                    ? Icons.workspace_premium
                    : Icons.person_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: LocalizedText(
                    info.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: LocalizedText(info.isPaid ? '유료' : '무료')),
              ],
            ),
            const SizedBox(height: 16),
            _UsageLine(
              label: '오늘',
              used: info.dailyUsed,
              limit: info.dailyLimit,
            ),
            _UsageLine(
              label: '이번 주',
              used: info.weeklyUsed,
              limit: info.weeklyLimit,
            ),
            _UsageLine(
              label: '이번 달',
              used: info.monthlyUsed,
              limit: info.monthlyLimit,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageLine extends StatelessWidget {
  const _UsageLine({
    required this.label,
    required this.used,
    required this.limit,
  });

  final String label;
  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final value = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(width: 64, child: LocalizedText(label)),
          Expanded(child: LinearProgressIndicator(value: value)),
          const SizedBox(width: 10),
          LocalizedText('$used/$limit'),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.allowance,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String price;
  final String allowance;
  final String description;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LocalizedText(title,
                style: Theme.of(context).textTheme.titleMedium),
            if (!kIsWeb) ...[
              const SizedBox(height: 6),
              LocalizedText(price,
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
            const SizedBox(height: 10),
            LocalizedText(allowance),
            const SizedBox(height: 4),
            LocalizedText(description,
                style: Theme.of(context).textTheme.bodySmall),
            if (!kIsWeb || selected) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected || !enabled ? null : onPressed,
                  child: LocalizedText(selected ? '이용 중' : 'Google Play에서 구독'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
