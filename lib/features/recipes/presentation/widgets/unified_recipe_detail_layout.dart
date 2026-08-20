import 'package:flutter/material.dart';

import '../../domain/recipe.dart';

class UnifiedRecipeDetailLayout extends StatelessWidget {
  const UnifiedRecipeDetailLayout({
    super.key,
    required this.recipe,
    required this.appBarTitle,
    this.appBarActions = const <Widget>[],
    this.primaryActions = const <Widget>[],
    this.extraSections = const <Widget>[],
    this.footer,
  });

  final Recipe recipe;
  final String appBarTitle;
  final List<Widget> appBarActions;
  final List<Widget> primaryActions;
  final List<Widget> extraSections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: appBarActions,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if ((recipe.imageUrl ?? '').trim().isNotEmpty) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  recipe.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return const ColoredBox(
                      color: Color(0x11000000),
                      child: Center(
                        child: Text(
                            '\uC774\uBBF8\uC9C0\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.'),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            recipe.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            (recipe.summary ?? '').trim().isEmpty
                ? '\uC694\uC57D \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
                : recipe.summary!,
          ),
          if (primaryActions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: primaryActions,
            ),
          ],
          const SizedBox(height: 24),
          const _UnifiedRecipeSectionTitle(
            title: '\uC7AC\uB8CC',
            icon: Icons.soup_kitchen_outlined,
          ),
          const SizedBox(height: 8),
          if (recipe.ingredients.isEmpty)
            const Text(
                '\uB4F1\uB85D\uB41C \uC7AC\uB8CC \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.')
          else
            ...recipe.ingredients.map(
              (String item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('\u2022 $item'),
              ),
            ),
          const SizedBox(height: 24),
          const _UnifiedRecipeSectionTitle(
            title: '\uC870\uB9AC \uC21C\uC11C',
            icon: Icons.format_list_numbered,
          ),
          const SizedBox(height: 8),
          if (recipe.steps.isEmpty)
            const Text(
                '\uB4F1\uB85D\uB41C \uC870\uB9AC \uC21C\uC11C\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.')
          else
            ...recipe.steps.asMap().entries.map(
                  (MapEntry<int, String> entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${entry.key + 1}. ${entry.value}'),
                  ),
                ),
          if (extraSections.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            ...extraSections,
          ],
          if (footer != null) ...<Widget>[
            const SizedBox(height: 28),
            footer!,
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UnifiedRecipeSectionTitle extends StatelessWidget {
  const _UnifiedRecipeSectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
