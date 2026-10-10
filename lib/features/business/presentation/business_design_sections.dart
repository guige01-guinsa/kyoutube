part of 'business_pages.dart';

/// A wrapping workflow summary. Selection describes the saved state, never an
/// implied approval or an action that has not actually happened.
class BusinessWorkflowSteps extends StatelessWidget {
  const BusinessWorkflowSteps({super.key, required this.labels, this.current});
  final List<String> labels;
  final int? current;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            selected: current == i,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: current == i ? colors.primaryContainer : colors.surface,
                border: Border.all(
                    color:
                        current == i ? colors.primary : colors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: LocalizedText('${i + 1}  ${labels[i]}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: current == i
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant)),
            ),
          ),
      ]),
    );
  }
}

class _BusinessWorkHeader extends StatelessWidget {
  const _BusinessWorkHeader(
      {required this.workspace,
      required this.title,
      required this.subtitle,
      required this.icon});
  final String workspace, title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: ScoutPageHeading(
            eyebrow: workspace, title: title, subtitle: subtitle, icon: icon),
      );
}
