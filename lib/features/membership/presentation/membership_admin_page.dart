import '../../../core/localization/app_localizations.dart';
import '../domain/billing_plan.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../application/membership_providers.dart';
import '../domain/membership.dart';

class MembershipAdminPage extends ConsumerStatefulWidget {
  const MembershipAdminPage({super.key});

  @override
  ConsumerState<MembershipAdminPage> createState() =>
      _MembershipAdminPageState();
}

class _MembershipAdminPageState extends ConsumerState<MembershipAdminPage> {
  String _query = '';
  String? _processingUserId;

  Future<void> _setPlan(ManagedMembership member, String planCode) async {
    setState(() => _processingUserId = member.userId);
    try {
      await ref.read(membershipServiceProvider).setManagedMembership(
            userId: member.userId,
            planCode: planCode,
          );
      ref.invalidate(managedMembershipsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('회원 등급을 변경했습니다.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('회원 등급을 변경하지 못했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) =>
        AppLocalizations.of(context).bilingual(ko, en);
    final account = ref.watch(activeAccountIdProvider);
    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('관리자 홈', 'Admin home'))),
        body: Center(
            child: FilledButton.icon(
          onPressed: () => context.push(AppRoutes.login),
          icon: const Icon(Icons.login),
          label: Text(t('로그인이 필요합니다', 'Sign in required')),
        )),
      );
    }
    final access = ref.watch(membershipInfoProvider);
    if (access.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('관리자 홈', 'Admin home'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (access.hasError || access.valueOrNull?.isAdmin != true) {
      return Scaffold(
        appBar: AppBar(title: Text(t('관리자 홈', 'Admin home'))),
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 36),
            const SizedBox(height: 16),
            Text(
                access.hasError
                    ? t('관리자 권한을 확인하지 못했습니다.', 'Could not verify admin access.')
                    : t('관리자만 이용할 수 있습니다.', 'This area is for administrators.'),
                textAlign: TextAlign.center),
            if (access.hasError) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(membershipInfoProvider),
                icon: const Icon(Icons.refresh),
                label: Text(t('다시 불러오기', 'Reload')),
              ),
            ],
          ]),
        )),
      );
    }
    final members = ref.watch(managedMembershipsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('관리자 홈', 'Admin home'))),
      body: ScoutPageBody(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(managedMembershipsProvider);
            await ref.read(managedMembershipsProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ScoutPageHeading(
                          title: t('서비스를 관리하는 공간', 'Manage your service'),
                          eyebrow: t('관리자 전용', 'ADMIN WORKSPACE'),
                          subtitle: t('상품 공개부터 회원과 운영 현황까지, 필요한 업무를 선택하세요.',
                              'Choose a task to manage products, members and service operations.'),
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                        const SizedBox(height: 24),
                        ScoutSectionLabel(
                            title: t('관리 업무', 'Management tasks'),
                            number: '01'),
                        ScoutAdaptiveGrid(children: [
                          _task(
                              context,
                              Icons.playlist_add_check,
                              t('상품 등록·공개 도우미', 'Product publishing assistant'),
                              t('미완료 항목 확인부터 실제 구매 화면 확인까지',
                                  'Review unfinished steps and check the live purchase screen'),
                              AppRoutes.shoppingAffiliateWorkflow),
                          _task(
                              context,
                              Icons.link,
                              '제휴 상품 관리',
                              t('상품 등록·검토·공개와 변경 이력',
                                  'Add, review and publish products; view history'),
                              AppRoutes.shoppingAffiliateAdmin),
                          _task(
                              context,
                              Icons.manage_search,
                              '공개 업체 자료 관리',
                              t('식자재 업체 자료와 검색 정보 정리',
                                  'Maintain supplier records and search information'),
                              AppRoutes.publicSupplierAdmin),
                          _task(
                              context,
                              Icons.monitor_heart_outlined,
                              '서비스 운영 현황',
                              t('요청·오류·사용량과 비용 확인',
                                  'Review requests, errors, usage and costs'),
                              AppRoutes.operations),
                          _task(
                              context,
                              Icons.tune,
                              '요금제 정책 관리',
                              t('이용 등급과 제공 범위 관리',
                                  'Manage membership plans and allowances'),
                              AppRoutes.membershipPolicyAdmin),
                          _task(
                              context,
                              Icons.local_offer_outlined,
                              '할인 행사 관리',
                              t('할인 정책과 진행 중인 행사 관리',
                                  'Manage discounts and active offers'),
                              AppRoutes.membershipDiscountAdmin),
                          _task(
                              context,
                              Icons.science_outlined,
                              t('업소 테스트 관리', 'Business tests'),
                              t('업소의 서비스 체험과 테스트 관리',
                                  'Manage business trials and testing'),
                              '/membership/admin/business-tests'),
                        ]),
                        const SizedBox(height: 24),
                        ScoutSectionLabel(
                            title: t('회원 관리', 'Members'),
                            number: '02',
                            subtitle: t('이름이나 이메일로 찾고 회원 등급을 변경하세요.',
                                'Find a member by name or email and manage their plan.')),
                        TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: context.tr('이메일 또는 이름 검색'),
                          ),
                          onChanged: (value) =>
                              setState(() => _query = value.trim()),
                        ),
                        const SizedBox(height: 16),
                      ]),
                ),
              ),
              members.when(
                loading: () => const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()))),
                error: (_, __) => SliverToBoxAdapter(
                    child: Center(
                  child: FilledButton.icon(
                    onPressed: () => ref.invalidate(managedMembershipsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const LocalizedText('다시 불러오기'),
                  ),
                )),
                data: (items) {
                  final query = _query.toLowerCase();
                  final filtered = items
                      .where((member) =>
                          query.isEmpty ||
                          member.email.toLowerCase().contains(query) ||
                          member.displayName.toLowerCase().contains(query))
                      .toList(growable: false);
                  if (filtered.isEmpty) {
                    return const SliverToBoxAdapter(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child:
                                Center(child: LocalizedText('표시할 회원이 없습니다.'))));
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final member = filtered[index];
                        final processing = _processingUserId == member.userId;
                        return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              leading: CircleAvatar(
                                  child: LocalizedText(member.email.isEmpty
                                      ? '?'
                                      : member.email.characters.first
                                          .toUpperCase())),
                              title: Text(member.email),
                              subtitle: LocalizedText(
                                '${_planLabel(member.planCode)} · 이번 달 AI ${member.monthlyUsed}회'
                                '${member.validUntil == null ? '' : '\n만료 ${DateFormat('yyyy.MM.dd').format(member.validUntil!.toLocal())}'}',
                              ),
                              isThreeLine: member.validUntil != null,
                              trailing: processing
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : PopupMenuButton<String>(
                                      tooltip: t(
                                          '회원 등급 변경', 'Change membership plan'),
                                      onSelected: (plan) =>
                                          _setPlan(member, plan),
                                      itemBuilder: (_) =>
                                          <PopupMenuEntry<String>>[
                                        const PopupMenuItem(
                                            value: 'free',
                                            child: LocalizedText('무료 회원')),
                                        for (final plan in BillingPlan.plans)
                                          PopupMenuItem(
                                              value: plan.code,
                                              child: LocalizedText(plan.title)),
                                      ],
                                    ),
                            ));
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _task(BuildContext context, IconData icon, String title,
          String subtitle, String route) =>
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const Spacer(),
                const Icon(Icons.arrow_forward, size: 18)
              ]),
              const SizedBox(height: 16),
              LocalizedText(title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );

  String _planLabel(String code) {
    return BillingPlan.byCode(code)?.title ?? '무료';
  }
}
