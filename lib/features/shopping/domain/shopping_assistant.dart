import '../../../core/format/user_number.dart';
import 'dart:math' as math;
import 'dart:convert';

import '../../kitchen/domain/kitchen_models.dart';
import '../../kitchen/domain/shopping_units.dart';

String shoppingNameKey(String name) => name.trim().toLowerCase();

String shoppingBaseUnit(String? unit) => switch (unit) {
      'kg' => 'g',
      'l' => 'ml',
      _ => unit ?? '',
    };

double shoppingBaseQuantity(double quantity, String? unit) =>
    const {'kg', 'l'}.contains(unit) ? quantity * 1000 : quantity;

/// Only unambiguous metric pairs are converted. Cups, packages and custom
/// units require the shopper to supply a quantity in the displayed unit.
double? shoppingConvert(double quantity, String from, String to) =>
    shoppingBaseUnit(from) == shoppingBaseUnit(to)
        ? shoppingBaseQuantity(quantity, from) / shoppingBaseQuantity(1, to)
        : null;

String shoppingNumber(double? value) => value == null
    ? '—'
    : value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

double? shoppingInput(String value) => parseUserNumber(value);

/// User-provided links open externally and are never fetched with credentials.
Uri? shoppingProductUri(String input) {
  final value = input.trim();
  if (value.length > 2048 || RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$')
          .hasMatch(host) ||
      host.contains('..') ||
      host.endsWith('.local') ||
      host.endsWith('.localhost') ||
      host.endsWith('.internal')) {
    return null;
  }
  return uri;
}

enum ShoppingSearchStore { naver, coupang, web }

/// Only shopper-entered product terms are sent to stores. Total recipe needs
/// are context, not a package size or an inferred cooking-unit conversion.
String shoppingSearchQuery(String ingredient, {String specification = ''}) {
  String clean(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
  final name = clean(ingredient);
  final detail = clean(specification);
  if (name.isEmpty || name.length > 250 || detail.length > 120) {
    throw const FormatException('Invalid product search');
  }
  return [name, if (detail.isNotEmpty) detail].join(' ');
}

Uri shoppingSearchUri(ShoppingSearchStore store, String ingredient,
    {String specification = '',
    String languageCode = 'ko',
    bool mobile = false}) {
  final query = shoppingSearchQuery(ingredient, specification: specification);
  if (store == ShoppingSearchStore.coupang) {
    // Ordinary search only. Issued affiliate links are opened separately,
    // unchanged, by ShoppingAffiliatePanel.
    return Uri.https('www.coupang.com', '/np/search', {'q': query});
  }
  return store == ShoppingSearchStore.naver
      ? Uri.https(
          mobile ? 'msearch.shopping.naver.com' : 'search.shopping.naver.com',
          '/search/all',
          {'query': query})
      : Uri.https('www.google.com', '/search', {
          'q': query,
          'tbm': 'shop',
          'hl': switch (languageCode) {
            'es' => 'es-419',
            'en' => 'en',
            _ => 'ko',
          },
        });
}

class ShoppingSourceItem {
  const ShoppingSourceItem(this.item, this.listTitle);
  final KitchenShoppingItem item;
  final String listTitle;
}

class ShoppingPurchaseGroup {
  const ShoppingPurchaseGroup(
      {required this.key,
      required this.name,
      required this.unit,
      required this.sources});
  final String key, name, unit;
  final List<ShoppingSourceItem> sources;
  String get specification =>
      sources.isEmpty ? '' : sources.first.item.purchaseSpecification;

  double? get neededQuantity {
    if (sources.any((s) =>
        s.item.needsReview ||
        s.item.quantity == null ||
        !s.item.quantity!.isFinite ||
        s.item.quantity! <= 0 ||
        !isPurchaseUnit(s.item.unit))) {
      return null;
    }
    return sources.fold<double>(0,
        (sum, s) => sum + shoppingBaseQuantity(s.item.quantity!, s.item.unit));
  }

  double? knownStock(List<KitchenIngredient> inventory) {
    final matches = inventory
        .where((i) => shoppingNameKey(i.name) == shoppingNameKey(name))
        .toList();
    // Multiple lots or incompatible units must be inspected by the user.
    if (matches.length != 1 ||
        matches.single.quantity == null ||
        matches.single.unit == null ||
        matches.single.quantity! < 0 ||
        !matches.single.quantity!.isFinite) {
      return null;
    }
    return shoppingConvert(
        matches.single.quantity!, matches.single.unit!, unit);
  }

  double? toBuy(double confirmedStock) => neededQuantity == null
      ? null
      : math.max(0, neededQuantity! - confirmedStock);

  int? packs(double confirmedStock, double? packQuantity) {
    final remaining = toBuy(confirmedStock);
    if (remaining == null ||
        packQuantity == null ||
        !packQuantity.isFinite ||
        packQuantity < 0.000001) {
      return null;
    }
    final count = remaining / packQuantity;
    if (!count.isFinite || count > 1e9) return null;
    return math.max(0, (count - 1e-10).ceil());
  }

  /// Split received quantity across source lists without adding the same stock
  /// twice. Original cooking text stays untouched. Remainder goes to last item.
  List<Map<String, dynamic>> allocations(double received, double stock) {
    if (!received.isFinite ||
        received < 0 ||
        received > 1e9 ||
        !stock.isFinite ||
        stock < 0 ||
        stock > 1e9 ||
        sources.isEmpty ||
        sources.length > 100) {
      throw const FormatException('Invalid purchase allocation');
    }
    var remainingStock = stock;
    final weights = <double>[];
    for (final source in sources) {
      final amount = neededQuantity == null
          ? 1.0
          : shoppingBaseQuantity(source.item.quantity!, source.item.unit);
      final used = math.min(remainingStock, amount);
      weights.add(amount - used);
      remainingStock -= used;
    }
    var totalWeight = weights.fold<double>(0, (a, b) => a + b);
    if (totalWeight == 0) {
      weights[0] = 1;
      totalWeight = 1;
    }
    final last = weights.lastIndexWhere((w) => w > 0);
    // Preserve purchase conversions to the database's six decimal places.
    final totalMicros = (received * 1000000).round();
    var left = totalMicros;
    return [
      for (var i = 0; i < sources.length; i++)
        (() {
          final micros = i == last
              ? left
              : math.min(
                  left, (totalMicros * weights[i] / totalWeight).floor());
          left -= micros;
          return <String, dynamic>{
            'id': sources[i].item.id,
            'revision': sources[i].item.revision,
            'quantity': micros / 1000000
          };
        })()
    ];
  }
}

List<ShoppingPurchaseGroup> shoppingPurchaseGroups(
    List<KitchenShoppingList> lists,
    {String? listId}) {
  final grouped = <String, List<ShoppingSourceItem>>{};
  final units = <String, String>{};
  for (final list in lists) {
    if (list.status != 'active' || (listId != null && list.id != listId)) {
      continue;
    }
    for (final item in list.items) {
      if (item.status != KitchenShoppingItemStatus.pending) continue;
      final unit = shoppingBaseUnit(item.unit);
      final merge = !item.needsReview &&
          item.quantity != null &&
          item.quantity!.isFinite &&
          item.quantity! > 0 &&
          const {'g', 'ml', 'ea', 'piece', 'slice', 'clove', 'stalk', 'head'}
              .contains(unit);
      final key = jsonEncode([
        shoppingNameKey(item.name),
        unit,
        item.purchaseSpecification.trim(),
        if (!merge) item.id
      ]);
      (grouped[key] ??= []).add(ShoppingSourceItem(item, list.title));
      units[key] = unit;
    }
  }
  return [
    for (final entry in grouped.entries)
      for (var start = 0; start < entry.value.length; start += 100)
        ShoppingPurchaseGroup(
            key: '${entry.key}|$start',
            name: entry.value.first.item.name,
            unit: units[entry.key]!,
            sources: List.unmodifiable(entry.value.skip(start).take(100)))
  ];
}

class ShoppingFavorite {
  const ShoppingFavorite(
      {required this.id,
      required this.ingredientName,
      required this.unit,
      required this.productName,
      required this.url,
      this.packQuantity});
  final String id, ingredientName, unit, productName, url;
  final double? packQuantity;
  bool matches(ShoppingPurchaseGroup group) =>
      shoppingNameKey(ingredientName) == shoppingNameKey(group.name) &&
      unit == group.unit;
  factory ShoppingFavorite.fromJson(Map<String, dynamic> json) =>
      ShoppingFavorite(
          id: json['id'] as String,
          ingredientName: json['ingredient_name'] as String,
          unit: json['unit'] as String,
          productName: json['product_name'] as String,
          url: json['product_url'] as String,
          packQuantity: (json['pack_quantity'] as num?)?.toDouble());
}

class ShoppingPurchaseRecord {
  const ShoppingPurchaseRecord(
      {required this.id,
      required this.name,
      required this.quantity,
      required this.unit,
      required this.currency,
      required this.createdAt,
      this.amount,
      this.productName = ''});
  final String id, name, unit, currency, productName;
  final double quantity;
  final double? amount;
  final DateTime createdAt;
  factory ShoppingPurchaseRecord.fromJson(Map<String, dynamic> json) =>
      ShoppingPurchaseRecord(
          id: json['id'] as String,
          name: json['ingredient_name'] as String,
          quantity: (json['quantity'] as num).toDouble(),
          unit: json['unit'] as String,
          amount: (json['paid_amount'] as num?)?.toDouble(),
          currency: json['currency'] as String,
          productName: json['product_name'] as String? ?? '',
          createdAt: DateTime.parse(json['created_at'] as String));
}
