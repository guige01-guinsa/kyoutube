import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../domain/business_navigation.dart';
import '../domain/business_workspace.dart';
import 'business_workspace_frame.dart';
import 'business_record_list.dart';

class BusinessWorkOverview extends StatelessWidget {
  const BusinessWorkOverview(
      {super.key, required this.business, this.settings = false});
  final BusinessContext business;
  final bool settings;
  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final base = '/business-workspaces/${business.id}';
    var actionIndex = 0;
    Widget link(String ko, String en, String path, IconData icon,
        String detailKo, String detailEn) {
      final primary = !settings && actionIndex++ == 0;
      final theme = Theme.of(context);
      return Card(
          color: primary ? theme.colorScheme.primaryContainer : null,
          child: InkWell(
              onTap: () => context.go(path),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(icon,
                              color: primary
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.primary),
                          const Spacer(),
                          const Icon(Icons.arrow_forward, size: 20)
                        ]),
                        const SizedBox(height: 16),
                        Text(tr(ko, en),
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: primary
                                    ? theme.colorScheme.onPrimaryContainer
                                    : null,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(tr(detailKo, detailEn),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: primary
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant))
                      ]))));
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(tr(settings ? '더보기' : '업무홈',
                settings ? 'Business settings & more' : 'Work home'))),
        body: Center(
            child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (business.isTest)
              Text(tr('연습용 업소 · 실제 주문에 사용하지 마세요.',
                  'Practice business · do not use for real orders.')),
            if (settings) ...[
              if (business.can('finance.read'))
                link(
                    '원가·매출 관리',
                    'Costs & sales',
                    businessSectionPath(
                        business.id, BusinessSection.management),
                    Icons.insights_outlined,
                    '원가와 판매 기록을 확인합니다.',
                    'Review costs and sales records.'),
              link(
                  '업무 요약',
                  'Work overview',
                  base,
                  Icons.dashboard_outlined,
                  '식단·메뉴와 진행할 업무를 확인합니다.',
                  'Review meals, menus and pending work.'),
              if (business.owner)
                link(
                    '직원·권한 관리',
                    'Staff & permissions',
                    '$base/members',
                    Icons.manage_accounts_outlined,
                    '직원 초대와 업무별 접근 권한을 관리합니다.',
                    'Invite staff and manage access to business records.'),
              link(
                  '업소 선택',
                  'Choose business',
                  '/business-workspaces',
                  Icons.swap_horiz,
                  '다른 업소로 전환하거나 초대받은 업소에 참여합니다.',
                  'Switch businesses or join an invitation.'),
              link(
                  '내 계정',
                  'My account',
                  '/account',
                  Icons.account_circle_outlined,
                  '로그인과 계정 정보를 관리합니다.',
                  'Manage your sign-in and account.'),
            ] else ...[
              Text(
                  tr('메뉴에서 구매까지, 같은 업소 자료로 이어가세요.',
                      'Continue from menus to purchasing in one shared business.'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              BusinessWorkflowStrip(business: business),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(tr('업무 흐름 안내', 'How the work flows')),
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(tr(
                            '레시피 개발 → 시험 조리·출시 승인 → 메뉴 등록 → 구매 준비 → 승인·전달 → 입고 확인',
                            'Develop recipes → trial & launch approval → menus → purchase preparation → approval & sharing → receipt')))
                  ]),
              const SizedBox(height: 12),
              _BusinessActionGrid(children: [
                if (business.can('recipes.read'))
                  link(
                      '식단 달력',
                      'Meal calendar',
                      '$base/meals',
                      Icons.calendar_month_outlined,
                      '주간 식단과 인분을 정하고 확정한 식단으로 구매를 준비해요.',
                      'Plan meals and servings, then prepare purchasing from confirmed plans.'),
                if (business.can('purchases.approve'))
                  link(
                      '구매 승인 대기 확인',
                      'Review purchase approvals',
                      '${businessSectionPath(business.id, BusinessSection.purchasing)}&status=review',
                      Icons.fact_check_outlined,
                      '요청 내용을 확인하고 승인하거나 초안으로 돌려보냅니다.',
                      'Review requests, approve or return them to draft.'),
                if (business.can('recipes.write') &&
                    !business.can('purchases.approve'))
                  link(
                      '레시피 개발',
                      'Recipe development',
                      '$base/new/recipe',
                      Icons.science_outlined,
                      '레시피를 연구하고 인분·배합·조리 버전을 관리해요.',
                      'Develop recipes, scale servings and compare cooking versions.'),
                if (business.can('purchasing.write') &&
                    business.can('recipes.read'))
                  link(
                      '판매 메뉴로 빠른 구매',
                      'Quick purchase from menus',
                      '$base/menu-fast',
                      Icons.add_shopping_cart,
                      '판매 메뉴와 인분으로 업체별 초안을 준비합니다. 개발용 구매는 메뉴판 관리에서 진행합니다.',
                      'Prepare supplier drafts from active menus and servings. Use menu management for development purchases.'),
                if (business.can('recipes.read'))
                  link(
                      '판매 메뉴판 관리',
                      'Manage menus',
                      '$base/menus',
                      Icons.restaurant_menu,
                      '승인된 레시피 버전과 판매 메뉴를 연결합니다.',
                      'Link approved recipe revisions to your menus.'),
                if (business.can('purchasing.read'))
                  link(
                      '재고·조리 예약',
                      'Stock & cooking reservations',
                      '$base/inventory',
                      Icons.inventory_2_outlined,
                      '입고·반품·실사·예약·조리 사용량을 함께 확인합니다.',
                      'Review receipts, returns, stock counts, reservations and cooking use.'),
                for (final section in businessSections(business).where((s) =>
                    s != BusinessSection.home && s != BusinessSection.settings))
                  Card(
                      child: ListTile(
                          leading: Icon(businessSectionIcon(section)),
                          title: Text(businessSectionTitle(context, section,
                              businessName: business.name)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context
                              .go(businessSectionPath(business.id, section)))),
              ]),
              const SizedBox(height: 16),
              Text(
                  tr('입고는 담당자가 실제 내용을 확인해 기록합니다. 조리 사용량과 재고는 자동 차감하지 않습니다.',
                      'Record receipts after checking deliveries. Cooking use and stock are not automatically deducted.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ]),
        )));
  }
}

class _BusinessActionGrid extends StatelessWidget {
  const _BusinessActionGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final width =
            twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final child in children) SizedBox(width: width, child: child)
        ]);
      });
}
