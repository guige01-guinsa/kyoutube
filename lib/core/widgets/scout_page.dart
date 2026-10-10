import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A bounded work surface without introducing another scroll controller.
class ScoutPageBody extends StatelessWidget {
  const ScoutPageBody(
      {super.key,
      required this.child,
      this.maxWidth = ScoutStyle.workspaceWidth});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(width: double.infinity, child: child)),
      );
}

/// Shared heading for a destination; actions wrap below text on small screens.
class ScoutPageHeading extends StatelessWidget {
  const ScoutPageHeading(
      {super.key,
      required this.title,
      this.subtitle,
      this.eyebrow,
      this.icon,
      this.trailing});
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final compact =
          box.maxWidth < 560 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final heading =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (eyebrow != null) ...[
          Text(eyebrow!,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: ScoutStyle.forest,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
        ],
        Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineMedium)),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: ScoutStyle.muted)),
        ],
      ]);
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 12 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null && !compact) ...[
              ExcludeSemantics(
                  child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: ScoutStyle.mint,
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, size: 28, color: ScoutStyle.forest))),
              const SizedBox(width: 20),
            ],
            Expanded(child: heading),
            if (!compact && trailing != null) ...[
              const SizedBox(width: 20),
              Flexible(child: trailing!)
            ],
          ]),
          if (compact && trailing != null) ...[
            const SizedBox(height: 16),
            trailing!
          ],
        ]),
      );
    });
  }
}

class ScoutPanel extends StatelessWidget {
  const ScoutPanel({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      );
}

/// Wrap instead of fixed-height grids: translations and large text can grow.
class ScoutAdaptiveGrid extends StatelessWidget {
  const ScoutAdaptiveGrid(
      {super.key,
      required this.children,
      this.minTileWidth = 280,
      this.gap = 16});
  final List<Widget> children;
  final double minTileWidth;
  final double gap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale > 1.3
            ? 1
            : ((box.maxWidth + gap) / (minTileWidth + gap)).floor().clamp(1, 3);
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final child in children) SizedBox(width: width, child: child)
        ]);
      });
}

class ScoutSectionLabel extends StatelessWidget {
  const ScoutSectionLabel(
      {super.key, required this.title, this.number, this.subtitle});
  final String title;
  final String? number;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (number != null) ...[
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: ScoutStyle.mint,
                    borderRadius: BorderRadius.circular(9)),
                child: Text(number!,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: ScoutStyle.forest))),
            const SizedBox(width: 12),
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Semantics(
                    header: true,
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)
                ],
              ])),
        ]),
      );
}
