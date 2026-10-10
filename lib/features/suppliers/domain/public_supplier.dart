class PublicSupplier {
  const PublicSupplier(
      {this.id = '',
      this.name = '',
      this.website = '',
      this.phone = '',
      this.products = '',
      this.categories = const [],
      this.deliveryRegions = const [],
      this.shippingNote = '',
      this.businessKind = 'store',
      this.sourceUrls = const [],
      this.checkedOn = '',
      this.status = 'candidate',
      this.revision = 0});
  final String id,
      name,
      website,
      phone,
      products,
      shippingNote,
      businessKind,
      checkedOn,
      status;
  final List<String> categories, deliveryRegions, sourceUrls;
  final int revision;
  factory PublicSupplier.fromJson(Map<String, dynamic> j) => PublicSupplier(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      website: j['website'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      products: j['products'] as String? ?? '',
      categories: List<String>.from(j['categories'] as List? ?? []),
      deliveryRegions: List<String>.from(j['delivery_regions'] as List? ?? []),
      shippingNote: j['shipping_note'] as String? ?? '',
      businessKind: j['business_kind'] as String? ?? 'store',
      sourceUrls: List<String>.from(j['source_urls'] as List? ?? []),
      checkedOn: j['checked_on'] as String? ?? '',
      status: j['status'] as String? ?? 'candidate',
      revision: (j['revision'] as num?)?.toInt() ?? 0);
  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'website': website,
        'phone': phone,
        'products': products,
        'categories': categories,
        'delivery_regions': deliveryRegions,
        'shipping_note': shippingNote,
        'business_kind': businessKind,
        'source_urls': sourceUrls,
        'checked_on': checkedOn,
        'status': status
      };
}

/// Use saved identity/details for known sites; research never overwrites edits.
List<PublicSupplier> matchPublicSupplierCandidates(
    List<PublicSupplier> candidates, List<PublicSupplier> saved) {
  String host(String url) =>
      Uri.parse(url).host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final byHost = {for (final row in saved) host(row.website): row};
  return candidates.map((row) => byHost[host(row.website)] ?? row).toList();
}
