import 'dart:convert';
import 'shopping_affiliate.dart';

/// A verified sale option. amount is per inner package, unitsPerOrder is the
/// number of inner packages received when ordering ONE sale unit.
class CoupangPack {
  const CoupangPack(
      this.amount, this.unit, this.unitsPerOrder, this.label, this.option);
  final double amount;
  final String unit, label, option;
  final int unitsPerOrder;
  static CoupangPack? parse(Object? value) {
    if (value is! Map) return null;
    final amount = value['amount'], count = value['units_per_order'];
    if (amount is! num ||
        !amount.isFinite ||
        amount < 0.000001 ||
        (amount - double.parse(amount.toStringAsFixed(6))).abs() > 1e-12 ||
        amount > 1e6 ||
        count is! num ||
        !count.isFinite ||
        count < 1 ||
        count > 10000 ||
        count != count.roundToDouble() ||
        !const ['g', 'kg', 'ml', 'l', 'ea'].contains(value['unit']) ||
        value['label'] is! String ||
        (value['label'] as String).trim().isEmpty ||
        (value['label'] as String).length > 30 ||
        value['option'] is! String ||
        (value['option'] as String).trim().isEmpty ||
        (value['option'] as String).length > 160) {
      return null;
    }
    final p = CoupangPack(amount.toDouble(), value['unit'] as String,
        count.toInt(), value['label'] as String, value['option'] as String);
    return p.quantityIn(p.unit) == null ? null : p;
  }

  static String canonical(String unit) => switch (unit.trim().toLowerCase()) {
        '그램' => 'g',
        '킬로그램' => 'kg',
        '밀리리터' => 'ml',
        '리터' => 'l',
        '개' || 'each' || 'pcs' => 'ea',
        final v => v,
      };
  double? quantityIn(String target) {
    const factors = {'g': 1.0, 'kg': 1000.0, 'ml': 1.0, 'l': 1000.0, 'ea': 1.0};
    String dimension(String u) => switch (u) {
          'g' || 'kg' => 'mass',
          'ml' || 'l' => 'volume',
          'ea' => 'count',
          _ => '',
        };
    final to = canonical(target);
    if (dimension(to).isEmpty || dimension(unit) != dimension(to)) return null;
    final n = amount * unitsPerOrder * factors[unit]! / factors[to]!;
    final rounded = double.parse(n.toStringAsFixed(6));
    return n.isFinite && n <= 1e9 && rounded > 0 && (rounded - n).abs() < 1e-9
        ? rounded
        : null;
  }

  int? suggest(double? needed, String target) {
    final size = quantityIn(target);
    if (size == null ||
        needed == null ||
        !needed.isFinite ||
        needed <= 0 ||
        needed > 1e9) {
      return null;
    }
    final micros = (needed * 1000000).round();
    final pack = (size * 1000000).round();
    final count = (micros + pack - 1) ~/ pack;
    return count > 0 && count <= 1000000 && size * count <= 1e9 ? count : null;
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'unit': unit,
        'units_per_order': unitsPerOrder,
        'label': label,
        'option': option
      };
}

class CoupangPurchasePlan {
  const CoupangPurchasePlan(
      {required this.offer,
      required this.count,
      required this.needed,
      required this.unit});
  final ShoppingAffiliate offer;
  final int count;
  final double needed;
  final String unit;
  CoupangPack get pack => CoupangPack.parse(offer.data['purchase_pack'])!;
  double get total =>
      double.parse((pack.quantityIn(unit)! * count).toStringAsFixed(6));
  double get difference => double.parse((total - needed).toStringAsFixed(6));
  bool matches(ShoppingAffiliate current) =>
      offer.id == current.id &&
      offerFingerprint(offer) == offerFingerprint(current);
  static String offerFingerprint(ShoppingAffiliate o) => jsonEncode([
        o.program,
        o.title,
        o.specification,
        o.uri.toString(),
        o.data['revision'],
        CoupangPack.parse(o.data['purchase_pack'])?.toJson()
      ]);
  CoupangPurchasePlan withCount(int value) => CoupangPurchasePlan(
      offer: offer, count: value, needed: needed, unit: unit);
  Map<String, dynamic> toJson() =>
      {'offer': offer.data, 'count': count, 'needed': needed, 'unit': unit};
  static CoupangPurchasePlan? parse(Object? data) {
    try {
      if (data is! Map || data['offer'] is! Map) return null;
      final offer =
          ShoppingAffiliate(Map<String, dynamic>.from(data['offer'] as Map));
      final count = data['count'], need = data['needed'], unit = data['unit'];
      final size = CoupangPack.parse(offer.data['purchase_pack']);
      if (offer.program != 'coupang' ||
          offer.uri == null ||
          size == null ||
          count is! num ||
          !count.isFinite ||
          count < 1 ||
          count > 1000000 ||
          count != count.roundToDouble() ||
          need is! num ||
          !need.isFinite ||
          need <= 0 ||
          need > 1e9 ||
          unit is! String ||
          size.quantityIn(unit) == null ||
          size.quantityIn(unit)! * count > 1e9) {
        return null;
      }
      return CoupangPurchasePlan(
          offer: offer,
          count: count.toInt(),
          needed: need.toDouble(),
          unit: unit);
    } catch (_) {
      return null;
    }
  }
}
