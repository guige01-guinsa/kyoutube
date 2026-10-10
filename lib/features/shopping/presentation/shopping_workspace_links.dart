import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'shopping_assistant_dialogs.dart';
import '../../../core/router/app_router.dart';

/// Always visible above lists, including when the first list is still empty.
class ShoppingWorkspaceLinks extends StatelessWidget {
  const ShoppingWorkspaceLinks({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in [
          (
            Icons.shopping_bag_outlined,
            shopText(context, '장보기', 'Shopping'),
            '/shopping'
          ),
          (
            Icons.storefront_outlined,
            shopText(context, '거래처', 'Suppliers'),
            AppRoutes.shoppingStores
          ),
        ])
          OutlinedButton.icon(
            onPressed: enabled ? () => context.push(item.$3) : null,
            icon: Icon(item.$1, size: 20),
            label: Text(item.$2),
          ),
      ]);
}
