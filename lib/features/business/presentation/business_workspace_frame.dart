import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_desktop_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../data/business_repository.dart';
import '../domain/business_navigation.dart';
import '../domain/business_workspace.dart';

String businessSectionTitle(BuildContext c, BusinessSection section,
        {String? businessName}) =>
    switch (section) {
      BusinessSection.home => workspaceText(c, '업무홈', 'Work home'),
      BusinessSection.collection => workspaceText(c, '레시피 찾기', 'Find recipes'),
      BusinessSection.recipes => workspaceText(c, '레시피 보관함', 'Recipe library'),
      BusinessSection.purchasing => workspaceText(c, '장보기', 'Shopping'),
      BusinessSection.management => workspaceText(c, '경영관리', 'Management'),
      BusinessSection.settings => workspaceText(c, '더보기', 'More'),
    };

IconData businessSectionIcon(BusinessSection section) => switch (section) {
      BusinessSection.home => Icons.home_outlined,
      BusinessSection.collection => Icons.search,
      BusinessSection.recipes => Icons.restaurant_menu,
      BusinessSection.purchasing => Icons.shopping_bag_outlined,
      BusinessSection.management => Icons.insights_outlined,
      BusinessSection.settings => Icons.more_horiz,
    };

String businessAccessLabel(BuildContext c, BusinessContext business) {
  if (business.owner) return workspaceText(c, '업소 책임자', 'Owner');
  final labels = [
    if (business.can('recipes.write'))
      workspaceText(c, '조리·연구', 'Recipe development'),
    if (business.can('purchasing.write'))
      workspaceText(c, '구매·입고', 'Purchasing'),
    if (business.can('finance.read')) workspaceText(c, '경영관리', 'Management'),
    if (business.can('purchases.approve'))
      workspaceText(c, '구매 승인', 'Purchase approval'),
  ];
  return labels.isEmpty
      ? workspaceText(c, '조회 권한', 'Read access')
      : labels.join(' · ');
}

/// Shared pages always use the actual business context, never a purpose preference.
class BusinessWorkspaceFrame extends ConsumerWidget {
  const BusinessWorkspaceFrame(
      {super.key, required this.location, required this.child});
  final Uri location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = location.pathSegments[1];
    final data = ref.watch(businessContextProvider(id));
    String tr(String ko, String en) => workspaceText(context, ko, en);
    return data.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: true,
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
          body: Center(
              child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('업소 접근 권한과 연결 상태를 확인해 주세요.',
              'Check business access and your connection.')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () => ref.invalidate(businessContextProvider(id)),
              child: Text(tr('다시 확인', 'Retry'))),
          TextButton(
              onPressed: () => context.go('/business-workspaces'),
              child: Text(tr('업소 선택', 'Choose business'))),
        ]),
      ))),
      data: (business) {
        final sections = businessSections(business);
        final parts = location.pathSegments;
        final record = parts.length == 4 &&
                ['records', 'edit'].contains(parts[2])
            ? ref
                .watch(businessRecordProvider((workspace: id, id: parts[3])))
                .asData
                ?.value
            : null;
        final selected = record == null
            ? businessLocationSection(location)
            : businessRecordSection(record.kind);
        final index = sections.indexOf(selected);
        final mobileSections = sections;
        final mobileIndex = sections.indexOf(selected);
        void openMobile(int value) =>
            context.go(businessSectionPath(id, sections[value]));
        final wide =
            MediaQuery.sizeOf(context).width >= ScoutStyle.desktopBreakpoint &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.5;
        void open(int value) =>
            context.go(businessSectionPath(id, sections[value]));
        final content = Column(children: [
          Material(
              color: ScoutStyle.mint,
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      if (!wide)
                        Expanded(
                            child: WorkspaceModeButton(
                                businessId: id, businessName: business.name)),
                      if (wide)
                        Expanded(
                            child: Text(business.name,
                                key: const Key('business-data-owner'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                      Flexible(
                          child: Text(tr('업소 공유 자료', 'Shared business records'),
                              key: wide
                                  ? null
                                  : const Key('business-data-owner'),
                              style: Theme.of(context).textTheme.bodySmall)),
                    ]),
                  ))),
          Expanded(child: child),
        ]);
        return Scaffold(
          body: wide
              ? Column(children: [
                  ScoutDesktopHeader(
                    title: tr('업소·전문가', 'Business & professional'),
                    actions: [
                      WorkspaceModeButton(
                          businessId: id, businessName: business.name)
                    ],
                    navigation: [
                      for (var i = 0; i < sections.length; i++)
                        ScoutDesktopDestination(
                            key: ValueKey('business-nav-${sections[i].name}'),
                            label: businessSectionTitle(context, sections[i],
                                businessName: business.name),
                            icon: businessSectionIcon(sections[i]),
                            selected:
                                (index < 0 ? sections.length - 1 : index) == i,
                            onTap: () => open(i)),
                    ],
                  ),
                  Expanded(child: content),
                ])
              : content,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  height: 80 +
                      (MediaQuery.textScalerOf(context).scale(1) - 1)
                              .clamp(0, 2) *
                          48,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex:
                      mobileIndex < 0 ? mobileSections.length - 1 : mobileIndex,
                  onDestinationSelected: openMobile,
                  destinations: [
                    for (final section in mobileSections)
                      NavigationDestination(
                          icon: Icon(businessSectionIcon(section)),
                          tooltip: businessSectionTitle(context, section,
                              businessName: business.name),
                          label: businessSectionTitle(context, section,
                              businessName: business.name))
                  ],
                ),
        );
      },
    );
  }
}
