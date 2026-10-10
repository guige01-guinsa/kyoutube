import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_desktop_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../application/workspace_profile_controller.dart';
import '../domain/workspace_profile.dart';
import 'workspace_menu.dart';
import 'workspace_data_notice.dart';
import '../../business/presentation/business_workspace_frame.dart';
export 'workspace_menu.dart' show workspaceText;

class WorkspaceScope extends InheritedWidget {
  const WorkspaceScope(
      {super.key, required super.child, this.handlesNavigation = true});
  final bool handlesNavigation;
  static bool hasFrame(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>() != null;
  static bool active(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceScope>()
          ?.handlesNavigation ??
      false;
  @override
  bool updateShouldNotify(WorkspaceScope oldWidget) =>
      handlesNavigation != oldWidget.handlesNavigation;
}

class WorkspaceFrame extends ConsumerWidget {
  const WorkspaceFrame(
      {super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = Uri.parse(location);
    final path = uri.path;
    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'business-workspaces') {
      return WorkspaceScope(
          child: BusinessWorkspaceFrame(location: uri, child: child));
    }
    final profile = ref.watch(workspaceProfileProvider).valueOrNull;
    final mode = profile?.active ?? WorkspaceMode.personal;
    final supplier = path == '/supplier-business';
    final content = supplier
        ? Column(children: [
            WorkspaceDataNotice(supplier: supplier),
            Expanded(child: child),
          ])
        : child;
    if (MediaQuery.sizeOf(context).width < ScoutStyle.desktopBreakpoint ||
        MediaQuery.textScalerOf(context).scale(1) > 1.5) {
      const framePages = {
        '/purchases',
        '/supplier-requests',
        '/shopping-stores',
        '/supplier-directory',
        '/supplier-business',
        '/chef-sales',
        '/supplier-request-ledger'
      };
      final ownsBar = framePages.contains(path);
      return WorkspaceScope(
          handlesNavigation: ownsBar,
          child: Scaffold(
            body: Column(children: [
              const SafeArea(
                  bottom: false,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: WorkspaceModeButton())),
              Expanded(child: content),
            ]),
            bottomNavigationBar: ownsBar ? const _FrameNavigation() : null,
          ));
    }
    final destinations = primaryWorkspaceLinks(mode, profile: profile);
    return WorkspaceScope(
      child: Scaffold(
          body: Column(children: [
        ScoutDesktopHeader(
          actions: const [WorkspaceModeButton()],
          navigation: [
            for (final d in destinations)
              ScoutDesktopDestination(
                  key: ValueKey('workspace-nav-${d.path}'),
                  label: d.label(context),
                  icon: d.icon,
                  selected:
                      workspaceDestinationIndex(uri, mode, profile: profile) ==
                          destinations.indexOf(d),
                  onTap: () => context.go(d.path)),
          ],
        ),
        Expanded(child: content),
      ])),
    );
  }
}

/// The frame owns the bar; page-local bars remain suppressed by WorkspaceScope.
class _FrameNavigation extends StatelessWidget {
  const _FrameNavigation();
  @override
  Widget build(BuildContext context) => const WorkspaceScope(
      handlesNavigation: false, child: ScoutNavigationBar(selectedIndex: 0));
}
