class ShoppingUnit {
  const ShoppingUnit({
    required this.code,
    required this.label,
    required this.category,
  });

  final String code;
  final String label;
  final String category;
}

/// Canonical purchase units saved for a shopping item.
///
/// Recipe/cooking wording stays in `ingredientText`; these units describe
/// what the shopper will buy. No quantity conversion is performed.
const List<ShoppingUnit> shoppingUnits = <ShoppingUnit>[
  ShoppingUnit(code: 'g', label: 'g', category: '무게'),
  ShoppingUnit(code: 'kg', label: 'kg', category: '무게'),
  ShoppingUnit(code: 'oz', label: 'oz', category: '무게'),
  ShoppingUnit(code: 'lb', label: 'lb', category: '무게'),
  ShoppingUnit(code: 'ml', label: 'ml', category: '부피'),
  ShoppingUnit(code: 'l', label: 'L', category: '부피'),
  ShoppingUnit(code: 'tsp', label: 'tsp (작은술)', category: '부피'),
  ShoppingUnit(code: 'tbsp', label: 'tbsp (큰술)', category: '부피'),
  ShoppingUnit(code: 'cup', label: 'cup', category: '부피'),
  ShoppingUnit(code: 'fl_oz', label: 'fl oz', category: '부피'),
  ShoppingUnit(code: 'pint', label: 'pint', category: '부피'),
  ShoppingUnit(code: 'quart', label: 'quart', category: '부피'),
  ShoppingUnit(code: 'gallon', label: 'gallon', category: '부피'),
  ShoppingUnit(code: 'ea', label: '개', category: '개수'),
  ShoppingUnit(code: 'piece', label: '조각', category: '개수'),
  ShoppingUnit(code: 'slice', label: '장', category: '개수'),
  ShoppingUnit(code: 'clove', label: '쪽', category: '개수'),
  ShoppingUnit(code: 'stalk', label: '줄기', category: '개수'),
  ShoppingUnit(code: 'head', label: '통', category: '개수'),
  ShoppingUnit(code: 'dozen', label: 'dozen (12개)', category: '개수'),
  ShoppingUnit(code: 'pack', label: '팩', category: '포장'),
  ShoppingUnit(code: 'bag', label: '봉지', category: '포장'),
  ShoppingUnit(code: 'bottle', label: '병', category: '포장'),
  ShoppingUnit(code: 'jar', label: '유리병', category: '포장'),
  ShoppingUnit(code: 'can', label: '캔', category: '포장'),
  ShoppingUnit(code: 'carton', label: '카톤', category: '포장'),
  ShoppingUnit(code: 'box', label: '상자', category: '포장'),
  ShoppingUnit(code: 'case', label: '박스/케이스', category: '포장'),
  ShoppingUnit(code: 'bundle', label: '묶음', category: '포장'),
  ShoppingUnit(code: 'bunch', label: '다발', category: '포장'),
  ShoppingUnit(code: 'net', label: '망', category: '포장'),
  ShoppingUnit(code: 'container', label: '용기', category: '포장'),
  ShoppingUnit(code: 'sachet', label: '포', category: '포장'),
  ShoppingUnit(code: 'pouch', label: '파우치', category: '포장'),
  ShoppingUnit(code: 'tube', label: '튜브', category: '포장'),
  ShoppingUnit(code: 'tray', label: '트레이', category: '포장'),
  ShoppingUnit(code: 'roll', label: '롤', category: '포장'),
];

const List<String> shoppingUnitCategories = <String>[
  '무게',
  '부피',
  '개수',
  '포장',
];

/// Cooking measures remain readable for older records and Chef recipes.
/// New purchasing forms use physical quantities or packaging units instead.
const cookingMeasureUnits = <String>{'tsp', 'tbsp', 'cup'};
final List<ShoppingUnit> purchaseUnits = List.unmodifiable(
  shoppingUnits.where((unit) => !cookingMeasureUnits.contains(unit.code)),
);

bool isPurchaseUnit(String? unit) =>
    isSupportedShoppingUnit(unit) && !cookingMeasureUnits.contains(unit);

/// Converts purchase amounts only. Package sizes/densities must be supplied
/// explicitly by the user; cooking measures never enter this calculation.
double? convertPurchaseQuantity(double quantity, String from, String to,
    {double? unitsPerOne}) {
  if (!quantity.isFinite ||
      quantity <= 0 ||
      !isPurchaseUnit(from) ||
      !isPurchaseUnit(to)) {
    return null;
  }
  if (from == to) return quantity;
  const standard = <String, (String, double)>{
    'g': ('mass', 1),
    'kg': ('mass', 1000),
    'ml': ('volume', 1),
    'l': ('volume', 1000),
    'ea': ('count', 1),
    'dozen': ('count', 12),
  };
  final left = standard[from];
  final right = standard[to];
  final factor = left != null && right != null && left.$1 == right.$1
      ? left.$2 / right.$2
      : unitsPerOne;
  if (factor == null || !factor.isFinite || factor <= 0) return null;
  final converted = quantity * factor;
  return converted.isFinite && converted > 0 ? converted : null;
}

bool isSupportedShoppingUnit(String? unit) =>
    unit != null &&
    shoppingUnits.any((ShoppingUnit value) => value.code == unit);

String shoppingUnitLabel(String? unit) {
  for (final ShoppingUnit value in shoppingUnits) {
    if (value.code == unit) {
      return value.label;
    }
  }
  return unit ?? '';
}
