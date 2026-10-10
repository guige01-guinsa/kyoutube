import 'business_workspace.dart';

enum BusinessSection {
  home,
  collection,
  recipes,
  purchasing,
  management,
  settings
}

BusinessSection businessSection(String? value) =>
    BusinessSection.values
        .where((section) => section.name == value)
        .firstOrNull ??
    BusinessSection.home;

String businessSectionPath(String workspace, BusinessSection section) => Uri(
        path: '/business-workspaces/$workspace',
        queryParameters:
            section == BusinessSection.home ? null : {'section': section.name})
    .toString();

List<BusinessSection> businessSections(BusinessContext business) => [
      BusinessSection.collection,
      if (business.can('recipes.read')) BusinessSection.recipes,
      if (business.can('purchasing.read')) BusinessSection.purchasing,
      BusinessSection.settings,
    ];

List<String> businessSectionKinds(BusinessSection section) => switch (section) {
      BusinessSection.recipes => ['recipe', 'meal'],
      BusinessSection.purchasing => ['purchase'],
      BusinessSection.management => ['cost', 'sale'],
      _ => [],
    };

BusinessSection businessLocationSection(Uri location) {
  final parts = location.pathSegments;
  if (parts.length == 2) {
    return businessSection(location.queryParameters['section']);
  }
  return switch (parts.length > 2 ? parts[2] : '') {
    'menus' || 'meals' => BusinessSection.recipes,
    'menu-fast' ||
    'menu-purchase' ||
    'coupang' ||
    'suppliers' ||
    'inventory' ||
    'receiving' =>
      BusinessSection.purchasing,
    'sales' => BusinessSection.management,
    'members' => BusinessSection.settings,
    'new' => switch (parts.last) {
        'recipe' || 'meal' => BusinessSection.recipes,
        'purchase' => BusinessSection.purchasing,
        'cost' || 'sale' => BusinessSection.management,
        _ => BusinessSection.home,
      },
    _ => BusinessSection.home,
  };
}

BusinessSection businessRecordSection(String kind) => switch (kind) {
      'recipe' || 'meal' => BusinessSection.recipes,
      'purchase' => BusinessSection.purchasing,
      'cost' || 'sale' => BusinessSection.management,
      _ => BusinessSection.home,
    };
