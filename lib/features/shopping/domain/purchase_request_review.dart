import 'dart:convert';
import 'supplier_request.dart';

/// Only item fields are sent. Buyer, contact, address, certificates, supplier
/// details, notes and product URLs are deliberately excluded.
Map<String, Object?> purchaseReviewInput(
    List<SupplierRequestLine> lines, String currency, String language) {
  if (lines.isEmpty ||
      lines.length > 20 ||
      !['KRW', 'USD'].contains(currency) ||
      !['ko', 'en', 'es'].contains(language) ||
      lines.map((l) => l.id).toSet().length != lines.length) {
    throw const FormatException('Invalid review input');
  }
  for (final l in lines) {
    if (l.id.isEmpty ||
        l.id.length > 80 ||
        l.name.trim().isEmpty ||
        l.name.length > 120 ||
        l.spec.length > 500 ||
        l.unit.length > 30 ||
        (l.quantity != null &&
            (!l.quantity!.isFinite ||
                l.quantity! <= 0 ||
                l.quantity! > 1e12)) ||
        (l.price != null &&
            (!l.price!.isFinite || l.price! < 0 || l.price! > 1e12))) {
      throw const FormatException('Invalid review input');
    }
  }
  final result = <String, Object?>{
    'language': language,
    'currency': currency,
    'lines': [
      for (final l in lines)
        {
          'id': l.id,
          'name': l.name,
          'spec': l.spec,
          'quantity': l.quantity,
          'unit': l.unit,
          'price': l.price,
        }
    ],
  };
  if (utf8.encode(jsonEncode(result)).length > 32768) {
    throw const FormatException('Review input too large');
  }
  return result;
}

String purchaseReviewFingerprint(List<SupplierRequestLine> lines) =>
    jsonEncode(lines.map((l) => l.toJson()).toList());

class PurchaseReviewSuggestion {
  const PurchaseReviewSuggestion(
      {required this.lineId,
      required this.name,
      required this.spec,
      required this.reason});
  final String lineId, name, spec, reason;
}

class PurchaseRequestReview {
  const PurchaseRequestReview(
      {required this.summary, required this.checks, required this.suggestions});
  final String summary;
  final List<String> checks;
  final List<PurchaseReviewSuggestion> suggestions;

  factory PurchaseRequestReview.fromJson(
      Map<String, dynamic> data, List<SupplierRequestLine> lines) {
    bool exact(Map value, List<String> keys) =>
        value.length == keys.length && keys.every(value.containsKey);
    String string(dynamic value, int max, {bool empty = false}) {
      if (value is! String ||
          value.length > max ||
          (!empty && value.trim().isEmpty)) {
        throw const FormatException('Invalid review response');
      }
      return value;
    }

    if (!exact(data, ['summary', 'checks', 'suggestions']) ||
        data['checks'] is! List ||
        (data['checks'] as List).length > 8 ||
        data['suggestions'] is! List ||
        (data['suggestions'] as List).length > lines.length) {
      throw const FormatException('Invalid review response');
    }
    final seen = <String>{};
    final changes = <PurchaseReviewSuggestion>[];
    for (final entry in data['suggestions'] as List) {
      if (entry is! Map ||
          !exact(entry, ['line_id', 'name', 'spec', 'reason'])) {
        throw const FormatException('Invalid review suggestion');
      }
      final id = string(entry['line_id'], 80);
      final line = lines.where((l) => l.id == id).firstOrNull;
      if (!seen.add(id) || line == null) {
        throw const FormatException('Unknown or duplicate review item');
      }
      final suggestion = PurchaseReviewSuggestion(
          lineId: id,
          name: string(entry['name'], 120),
          spec: string(entry['spec'], 500, empty: true),
          reason: string(entry['reason'], 300));
      if (suggestion.name != line.name || suggestion.spec != line.spec) {
        changes.add(suggestion);
      }
    }
    return PurchaseRequestReview(
        summary: string(data['summary'], 500),
        checks: List.unmodifiable(
            (data['checks'] as List).map((v) => string(v, 300))),
        suggestions: List.unmodifiable(changes));
  }

  /// Quantities, units, quoted prices, URLs and shopping links are never AI edits.
  List<SupplierRequestLine> apply(
      List<SupplierRequestLine> original, Set<String> selected) {
    final changes = {
      for (final s in suggestions)
        if (selected.contains(s.lineId)) s.lineId: s
    };
    return List.unmodifiable(original.map((line) {
      final s = changes[line.id];
      if (s == null) return line;
      return SupplierRequestLine(
          id: line.id,
          name: s.name,
          spec: s.spec,
          quantity: line.quantity,
          unit: line.unit,
          price: line.price,
          productUrl: line.productUrl,
          sourceIds: List.unmodifiable(line.sourceIds));
    }));
  }
}
