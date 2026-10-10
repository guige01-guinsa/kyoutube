import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'scout_brand_mark.dart';

/// A light, wrapping desktop header. Features retain ownership of routing.
class ScoutDesktopHeader extends StatelessWidget {
  const ScoutDesktopHeader(
      {super.key,
      required this.navigation,
      required this.actions,
      this.title = 'RECIPE SCOUT'});
  final String title;
  final List<Widget> navigation;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Material(
        color: ScoutStyle.cream,
        child: SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: ScoutStyle.line))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const ScoutBrandMark(
                          size: 36, excludeFromSemantics: true),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      letterSpacing: 1.2,
                                      color: ScoutStyle.plum))),
                      ...actions,
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: navigation),
                  ]),
            )),
      );
}

class ScoutDesktopDestination extends StatelessWidget {
  const ScoutDesktopDestination(
      {super.key,
      required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: selected ? Colors.white : ScoutStyle.muted,
            backgroundColor: selected ? ScoutStyle.plum : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(icon, size: 19),
          label: Text(label),
        ),
      );
}
