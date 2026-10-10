import '../../shopping/domain/supplier_request.dart';

const supplierCategories = <String, (String, String, List<String>)>{
  'produce': ('농산물', 'Produce', ['vegetables', 'fruit', 'grains', 'mushrooms']),
  'seafood': (
    '수산물',
    'Seafood',
    ['fish', 'shellfish', 'seaweed', 'dried_seafood']
  ),
  'meat': ('육류', 'Meat', ['beef', 'pork', 'poultry', 'other_meat']),
  'dairy': ('달걀·유제품', 'Eggs & dairy', ['eggs', 'milk', 'cheese']),
  'processed': (
    '가공식품',
    'Prepared foods',
    ['frozen', 'noodles', 'tofu', 'prepared']
  ),
  'pantry': ('양념·기타', 'Pantry', ['sauces', 'oils', 'spices', 'other']),
};
const supplierSubcategories = <String, (String, String)>{
  'vegetables': ('채소', 'Vegetables'),
  'fruit': ('과일', 'Fruit'),
  'grains': ('곡물', 'Grains'),
  'mushrooms': ('버섯', 'Mushrooms'),
  'fish': ('생선', 'Fish'),
  'shellfish': ('조개·갑각류', 'Shellfish'),
  'seaweed': ('해조류', 'Seaweed'),
  'dried_seafood': ('건어물', 'Dried seafood'),
  'beef': ('소고기', 'Beef'),
  'pork': ('돼지고기', 'Pork'),
  'poultry': ('닭·오리', 'Poultry'),
  'other_meat': ('기타 육류', 'Other meat'),
  'eggs': ('달걀', 'Eggs'),
  'milk': ('우유·유제품', 'Milk & dairy'),
  'cheese': ('치즈', 'Cheese'),
  'frozen': ('냉동식품', 'Frozen foods'),
  'noodles': ('면', 'Noodles'),
  'tofu': ('두부·콩가공품', 'Tofu & soy'),
  'prepared': ('반조리·가공품', 'Prepared'),
  'sauces': ('소스·장류', 'Sauces'),
  'oils': ('식용유', 'Oils'),
  'spices': ('향신료', 'Spices'),
  'other': ('기타', 'Other'),
};
const supplierRegions = [
  '전국',
  '서울',
  '부산',
  '대구',
  '인천',
  '광주',
  '대전',
  '울산',
  '세종',
  '경기',
  '강원',
  '충북',
  '충남',
  '전북',
  '전남',
  '경북',
  '경남',
  '제주'
];
String supplierCategoryLabel(String code, bool en) =>
    supplierCategories.containsKey(code)
        ? (en ? supplierCategories[code]!.$2 : supplierCategories[code]!.$1)
        : (en
                ? supplierSubcategories[code]?.$2
                : supplierSubcategories[code]?.$1) ??
            code;

String supplierRegionLabel(String region, bool english) => english
    ? const {
          '전국': 'Nationwide',
          '서울': 'Seoul',
          '부산': 'Busan',
          '대구': 'Daegu',
          '인천': 'Incheon',
          '광주': 'Gwangju',
          '대전': 'Daejeon',
          '울산': 'Ulsan',
          '세종': 'Sejong',
          '경기': 'Gyeonggi',
          '강원': 'Gangwon',
          '충북': 'North Chungcheong',
          '충남': 'South Chungcheong',
          '전북': 'North Jeolla',
          '전남': 'South Jeolla',
          '경북': 'North Gyeongsang',
          '경남': 'South Gyeongsang',
          '제주': 'Jeju',
        }[region] ??
        region
    : region;

class CatalogSupplier {
  const CatalogSupplier(
      {required this.id,
      required this.name,
      this.contact = '',
      this.phone = '',
      this.region = '',
      this.deliveryRegions = const [],
      this.address = '',
      this.website = '',
      this.description = '',
      this.published = false,
      this.verified = false,
      this.shippingFee,
      this.freeShippingFrom,
      this.minimumOrder = 0,
      this.currency = 'KRW',
      this.rating,
      this.reviewCount = 0,
      this.revision = 0});
  final String id,
      name,
      contact,
      phone,
      region,
      address,
      website,
      description,
      currency;
  final List<String> deliveryRegions;
  final bool published, verified;
  final double? shippingFee, freeShippingFrom, rating;
  final double minimumOrder;
  final int reviewCount, revision;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'contact': contact,
        'phone': phone,
        'region': region,
        'delivery_regions': deliveryRegions,
        'address': address,
        'website': website,
        'description': description,
        'published': published,
        'shipping_fee': shippingFee,
        'free_shipping_from': freeShippingFrom,
        'minimum_order': minimumOrder,
        'currency': currency
      };
  factory CatalogSupplier.fromJson(Map<String, dynamic> j) => CatalogSupplier(
      id: j['id'],
      name: j['name'],
      contact: j['contact'] ?? '',
      phone: j['phone'] ?? '',
      region: j['region'] ?? '',
      deliveryRegions: List<String>.from(j['delivery_regions'] ?? []),
      address: j['address'] ?? '',
      website: j['website'] ?? '',
      description: j['description'] ?? '',
      published: j['published'] ?? false,
      verified: j['verified'] ?? false,
      shippingFee: (j['shipping_fee'] as num?)?.toDouble(),
      freeShippingFrom: (j['free_shipping_from'] as num?)?.toDouble(),
      minimumOrder: (j['minimum_order'] as num?)?.toDouble() ?? 0,
      currency: j['currency'] ?? 'KRW',
      rating: (j['rating'] as num?)?.toDouble(),
      reviewCount: j['review_count'] ?? 0,
      revision: j['revision'] ?? 0);
  ShoppingSupplier requestSupplier(String personalId) => ShoppingSupplier(
      id: personalId,
      name: name,
      contact: contact,
      phone: phone,
      address: address,
      website: website);
}

class CatalogProduct {
  const CatalogProduct(
      {required this.id,
      required this.supplierId,
      required this.name,
      this.category = 'produce',
      this.subcategory = 'vegetables',
      this.aliases = '',
      this.brand = '',
      this.origin = 'domestic',
      this.country = '',
      this.storage = 'ambient',
      this.description = '',
      this.imagePath = '',
      this.saleUnit = 'pack',
      this.contentQuantity = 1,
      this.contentUnit = 'kg',
      this.minimumPacks = 1,
      this.price,
      this.priceValidUntil,
      this.tax = 'included',
      this.active = true,
      this.revision = 0});
  final String id,
      supplierId,
      name,
      category,
      subcategory,
      aliases,
      brand,
      origin,
      country,
      storage,
      description,
      imagePath,
      saleUnit,
      contentUnit,
      tax;
  final double contentQuantity;
  final int minimumPacks, revision;
  final double? price;
  final DateTime? priceValidUntil;
  final bool active;

  /// A copied specification is a new stopped product, never a live old quote.
  CatalogProduct draftCopy(String newId) => CatalogProduct.fromJson({
        ...toJson(),
        'id': newId,
        'revision': 0,
        'active': false,
        'price': null,
        'price_valid_until': null,
      });
  bool priceCurrent(DateTime now) =>
      price != null &&
      price!.isFinite &&
      price! >= 0 &&
      priceValidUntil != null &&
      !DateTime.utc(now.year, now.month, now.day).isAfter(DateTime.utc(
          priceValidUntil!.year, priceValidUntil!.month, priceValidUntil!.day));
  Map<String, dynamic> toJson() => {
        'id': id,
        'supplier_id': supplierId,
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'aliases': aliases,
        'brand': brand,
        'origin': origin,
        'country': country,
        'storage': storage,
        'description': description,
        'image_path': imagePath,
        'sale_unit': saleUnit,
        'content_quantity': contentQuantity,
        'content_unit': contentUnit,
        'minimum_packs': minimumPacks,
        'price': price,
        'price_valid_until':
            priceValidUntil?.toIso8601String().substring(0, 10),
        'tax': tax,
        'active': active
      };
  factory CatalogProduct.fromJson(Map<String, dynamic> j) => CatalogProduct(
      id: j['id'],
      supplierId: j['supplier_id'],
      name: j['name'],
      category: j['category'],
      subcategory: j['subcategory'],
      aliases: j['aliases'] ?? '',
      brand: j['brand'] ?? '',
      origin: j['origin'],
      country: j['country'] ?? '',
      storage: j['storage'] ?? 'ambient',
      description: j['description'] ?? '',
      imagePath: j['image_path'] ?? '',
      saleUnit: j['sale_unit'],
      contentQuantity: (j['content_quantity'] as num).toDouble(),
      contentUnit: j['content_unit'],
      minimumPacks: j['minimum_packs'],
      price: (j['price'] as num?)?.toDouble(),
      priceValidUntil: DateTime.tryParse(j['price_valid_until'] ?? ''),
      tax: j['tax'],
      active: j['active'] ?? true,
      revision: j['revision'] ?? 0);
}

class SupplierOffer {
  const SupplierOffer(this.supplier, this.product);
  final CatalogSupplier supplier;
  final CatalogProduct product;
  factory SupplierOffer.fromJson(Map<String, dynamic> j) => SupplierOffer(
      CatalogSupplier.fromJson(Map<String, dynamic>.from(j['supplier'])),
      CatalogProduct.fromJson(Map<String, dynamic>.from(j['product'])));
}
