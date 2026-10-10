import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/workspace/domain/workspace_profile.dart';
import 'package:k_youtube/features/workspace/presentation/workspace_menu.dart';
import 'workspace_roles_test.dart' show MemoryWorkspaceRepository, pumpRole;

WorkspaceProfile duty(ProfessionalDuty value) => WorkspaceProfile(
    active: WorkspaceMode.professional,
    enabled: const {WorkspaceMode.professional},
    duties: {value},
    dutiesConfigured: true);
void main() {
  test(
      'legacy profiles keep all duties; malformed or unauthorized names never become duties',
      () {
    final legacy = WorkspaceProfile.fromJson({
      'schema': 1,
      'active': 'professional',
      'enabled': ['professional']
    });
    expect(legacy.effectiveDuties, allProfessionalDuties);
    expect(legacy.dutiesConfigured, isFalse);
    final invalid = WorkspaceProfile.fromJson({
      'schema': 1,
      'active': 'professional',
      'enabled': ['professional'],
      'professional': {
        'duties': ['owner', 'admin'],
        'focus': 'owner'
      }
    });
    expect(invalid.effectiveDuty, isNull);
    expect(invalid.effectiveDuties, allProfessionalDuties);
  });
  test(
      'multiple duty preferences round trip and purpose switching retains choices',
      () {
    const value = WorkspaceProfile(
        active: WorkspaceMode.professional,
        enabled: {WorkspaceMode.personal, WorkspaceMode.professional},
        duties: {ProfessionalDuty.culinary, ProfessionalDuty.management},
        focus: ProfessionalDuty.management,
        dutiesConfigured: true);
    final parsed = WorkspaceProfile.fromJson(value.toJson());
    expect(parsed.effectiveDuty, ProfessionalDuty.management);
    expect(
        parsed
            .activate(WorkspaceMode.personal)
            .activate(WorkspaceMode.professional)
            .effectiveDuty,
        ProfessionalDuty.management);
    expect(parsed.focusOn(null).effectiveDuty, isNull);
    expect(
        () => parsed.focusOn(ProfessionalDuty.purchasing), throwsArgumentError);
  });
  test(
      'every single duty has four destinations and correct related-page selection',
      () {
    for (final d in ProfessionalDuty.values) {
      final profile = duty(d);
      final paths =
          primaryWorkspaceLinks(WorkspaceMode.professional, profile: profile)
              .map((l) => l.path)
              .toList();
      expect(paths.length, 4);
      expect(paths.toSet().length, 4);
      for (final path in paths) {
        expect(
            workspaceSectionPath(
                Uri.parse(path).path, WorkspaceMode.professional,
                profile: profile),
            Uri.parse(path).path);
      }
    }
    expect(
        workspaceSectionPath('/chef-sales/record', WorkspaceMode.professional,
            profile: duty(ProfessionalDuty.management)),
        '/workspace-menu');
    expect(
        workspaceSectionPath('/supplier-directory', WorkspaceMode.professional,
            profile: duty(ProfessionalDuty.purchasing)),
        '/shopping');
  });
  test(
      'compact professional navigation retains collection and maps research to the recipe library',
      () {
    final links =
        primaryWorkspaceLinks(WorkspaceMode.professional, compact: true);
    expect(links.map((link) => link.path),
        ['/', '/my-recipes', '/shopping', '/workspace-menu']);
    expect(
        workspaceDestinationIndex(
            Uri.parse('/chef/record'), WorkspaceMode.professional,
            compact: true),
        1);
    expect(
        workspaceDestinationIndex(
            Uri.parse('/ingredient-search'), WorkspaceMode.professional,
            compact: true),
        0);
  });
  for (final locale in ['ko', 'en']) {
    for (final d in ProfessionalDuty.values) {
      testWidgets('$locale ${d.name} fits mobile and 200 percent text',
          (tester) async {
        final repo = MemoryWorkspaceRepository(duty(d));
        await pumpRole(tester, repo,
            locale: locale, width: 390, initial: '/workspace?area=personal');
        final labels = tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .cast<NavigationDestination>()
            .map((v) => v.label)
            .toList();
        expect(labels.length, 4);
        expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .labelBehavior,
            NavigationDestinationLabelBehavior.alwaysShow);
        expect(find.byKey(ValueKey('work-focus-${d.name}')), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('home focus persists and failure retains the old focus',
      (tester) async {
    final repo = MemoryWorkspaceRepository(const WorkspaceProfile(
        active: WorkspaceMode.professional,
        enabled: {WorkspaceMode.professional}));
    await pumpRole(tester, repo, initial: '/workspace?area=personal');
    await tester.tap(find.byKey(const ValueKey('work-focus-culinary')));
    await tester.pumpAndSettle();
    expect(repo.profile.effectiveDuty, ProfessionalDuty.culinary);
    repo.fail = true;
    await tester.tap(find.byKey(const ValueKey('work-focus-management')));
    await tester.pumpAndSettle();
    expect(repo.profile.effectiveDuty, ProfessionalDuty.culinary);
    expect(find.text('업무 화면을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });
}
