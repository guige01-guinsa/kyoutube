import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/workspace/presentation/workspace_frame.dart';
import '../../features/workspace/presentation/workspace_menu.dart';
import '../../features/workspace/application/workspace_profile_controller.dart';
import '../../features/workspace/domain/workspace_profile.dart';

/// Top-level destinations replace each other instead of growing the back stack.
class ScoutNavigationBar extends ConsumerWidget {
  const ScoutNavigationBar(
      {super.key, required this.selectedIndex, this.enabled = true});
  final int selectedIndex;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (WorkspaceScope.active(context)) return const SizedBox.shrink();
    final profile = ref.watch(workspaceProfileProvider).valueOrNull;
    final mode = profile?.active ?? WorkspaceMode.personal;
    final destinations =
        primaryWorkspaceLinks(mode, profile: profile, compact: true);
    Uri location;
    try {
      location = GoRouterState.of(context).uri;
    } catch (_) {
      location = Uri.parse(switch (selectedIndex) {
        1 => '/my-recipes',
        2 => '/kitchen',
        3 => '/chef',
        _ => '/'
      });
    }
    final match = workspaceDestinationIndex(location, mode,
        profile: profile, compact: true);
    final current = match < 0 ? destinations.length - 1 : match;
    return NavigationBar(
        height: 80 +
            (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) * 48,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: current,
        onDestinationSelected: enabled
            ? (index) {
                final destination = destinations[index].path;
                // A related page can select this section while still needing
                // navigation back to its landing page (for example research).
                if (location == Uri.parse(destination)) return;
                context.go(destination);
              }
            : null,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
                icon: Icon(d.icon),
                tooltip: d.label(context),
                label: d.label(context))
        ]);
  }
}
