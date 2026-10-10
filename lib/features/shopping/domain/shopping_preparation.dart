import 'dart:convert';
import 'shopping_assistant.dart';
import 'coupang_purchase_plan.dart';

enum ShoppingCategory {
  produce('채소·과일', 'Produce'),
  protein('육류·수산물', 'Meat & seafood'),
  dairy('유제품·달걀', 'Dairy & eggs'),
  beansTofuNuts('콩·두부·견과', 'Beans, tofu & nuts'),
  grains('쌀·잡곡', 'Rice & grains'),
  noodlesFlour('면·가루·베이킹', 'Noodles, flour & baking'),
  seasoning('양념·오일', 'Seasonings & oils'),
  spices('소금·설탕·향신료', 'Salt, sugar & spices'),
  kimchiBanchan('김치·반찬', 'Kimchi & side dishes'),
  processedFrozen('통조림·가공·냉동식품', 'Canned, prepared & frozen foods'),
  bakeryDessert('빵·잼·디저트', 'Bakery, jam & desserts'),
  beverages('음료·차·커피', 'Beverages, tea & coffee'),
  healthSpecialty('건강·특수식', 'Health & specialty foods'),

  /// Retained for existing saved shopping drafts.
  staple('곡류·가공식품', 'Grains & prepared foods'),
  other('기타·분류 확인', 'Other / check category');

  const ShoppingCategory(this.ko, this.en);
  final String ko, en;
}

/// Only explicitly approved identities may merge. Categories never participate
/// in the merge key, and unknown/package units remain separate.
List<ShoppingPurchaseGroup> mergePreparedGroups(
    List<ShoppingPurchaseGroup> groups, Map<String, String> approved) {
  final indexed = {for (final g in groups) preparationIdentity(g): g};
  final buckets = <String, List<ShoppingPurchaseGroup>>{};
  for (final g in groups) {
    final id = preparationIdentity(g);
    final target = approved[id];
    final safe = target != null &&
        indexed.containsKey(target) &&
        indexed[target]!.specification == g.specification &&
        g.neededQuantity != null &&
        const {'g', 'ml', 'ea', 'piece', 'slice', 'clove', 'stalk', 'head'}
            .contains(g.unit);
    final key = safe ? '$target|${g.unit}' : id;
    (buckets[key] ??= []).add(g);
  }
  return [
    for (final bucket in buckets.values)
      if (bucket.length == 1 ||
          bucket.fold<int>(0, (n, g) => n + g.sources.length) > 100)
        ...bucket
      else
        ShoppingPurchaseGroup(
            key: bucket.map((g) => g.key).join('~'),
            name: indexed[approved[preparationIdentity(bucket.first)]]!.name,
            unit: bucket.first.unit,
            sources: List.unmodifiable(bucket.expand((g) => g.sources)))
  ];
}

class ShoppingClassification {
  const ShoppingClassification(this.categories, this.matches);
  final List<ShoppingCategory> categories;
  final List<List<int>> matches;
}

// Exact names only: unknown foods remain editable rather than being guessed
// from a substring (e.g. chicken stock must not become fresh chicken).
ShoppingCategory shoppingCategory(String name) {
  const names = <ShoppingCategory, String>{
    ShoppingCategory.produce:
        '대파,쪽파,양파,마늘,감자,당근,애호박,오이,배추,무,버섯,시금치,상추,고추,토마토,사과,바나나,onion,garlic,carrot,potato,tomato,scallion,apple,banana,cebolla,ajo,zanahoria,papa,patata,tomate,jitomate,cebollín,manzana,plátano,banana,pepino,calabacín,espinaca,lechuga,champiñón',
    ShoppingCategory.protein:
        '소고기,돼지고기,닭고기,삼겹살,새우,오징어,고등어,연어,참치,beef,pork,chicken,shrimp,salmon,carne de res,carne de cerdo,pollo,camarón,camarones,salmón,atún,calamar',
    ShoppingCategory.dairy:
        '우유,치즈,버터,요거트,달걀,계란,milk,cheese,butter,yogurt,egg,eggs,leche,queso,mantequilla,yogur,huevo,huevos',
    ShoppingCategory.beansTofuNuts:
        '두부,콩,두유,땅콩,아몬드,호두,tofu,bean,soybean,nut,frijol,almendra',
    ShoppingCategory.grains: '쌀,현미,보리,귀리,잡곡,rice,arroz,oats',
    ShoppingCategory.noodlesFlour:
        '국수,소면,라면,우동,파스타,당면,밀가루,부침가루,빵가루,이스트,베이킹파우더,noodles,pasta,fideos,flour,harina,yeast',
    ShoppingCategory.seasoning:
        '간장,진간장,국간장,소금,설탕,후추,고추장,된장,고춧가루,참기름,들기름,식용유,올리브유,식초,salt,sugar,pepper,soy sauce,sesame oil,olive oil,sal,azúcar,pimienta,salsa de soya,salsa de soja,aceite de sésamo,aceite de oliva,vinagre',
    ShoppingCategory.spices:
        '소금,설탕,후추,고춧가루,카레가루,다시다,미원,salt,sugar,pepper,spice,sal,azúcar,pimienta',
    ShoppingCategory.kimchiBanchan: '김치,배추김치,깍두기,장아찌,반찬,kimchi',
    ShoppingCategory.processedFrozen:
        '만두,볶음밥,즉석밥,카레,찌개,냉동식품,참치캔,옥수수캔,통조림,김,미역,다시마,멸치,frozen,dumpling,canned,seaweed',
    ShoppingCategory.bakeryDessert:
        '빵,식빵,잼,꿀,초콜릿,쿠키,bread,jam,honey,chocolate,pan',
    ShoppingCategory.beverages: '물,주스,커피,차,탄산수,음료,water,juice,coffee,tea',
    ShoppingCategory.healthSpecialty: '단백질파우더,프로틴,영양식,저당,글루텐프리,protein powder',
  };
  final key = shoppingNameKey(name);
  return names.entries
          .where((e) => e.value.split(',').contains(key))
          .firstOrNull
          ?.key ??
      ShoppingCategory.other;
}

/// Includes source revisions and quantities so an old confirmation cannot be
/// applied to a new list or a changed amount, even when the name is unchanged.
String preparationIdentity(ShoppingPurchaseGroup group) {
  final sources = group.sources
      .map((s) => [
            s.item.listId,
            s.item.id,
            s.item.revision,
            s.item.quantity,
            s.item.unit,
            s.item.needsReview,
            s.item.ingredientText,
            s.item.purchaseSpecification
          ])
      .toList()
    ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  return jsonEncode([group.name, group.unit, sources]);
}

/// Only additions may retain checks on unchanged groups. Stock, date, source
/// revisions, removals or renames require a fresh review. Confirmation is never
/// carried across a fingerprint change.
bool preparationHasOnlyAdditions(String previous, String current) {
  try {
    final a = jsonDecode(previous) as List, b = jsonDecode(current) as List;
    if (a.length != 3 ||
        b.length != 3 ||
        a[2] != b[2] ||
        jsonEncode(a[1]) != jsonEncode(b[1])) {
      return false;
    }
    Set<String> sources(dynamic identities) =>
        (identities as List).expand((id) {
          final group = jsonDecode(id as String) as List;
          return (group[2] as List)
              .map((source) => jsonEncode([group[0], source]));
        }).toSet();
    final oldSources = sources(a[0]), newSources = sources(b[0]);
    return newSources.length > oldSources.length &&
        newSources.containsAll(oldSources);
  } catch (_) {
    return false;
  }
}

class PreparedPurchase {
  const PreparedPurchase(
      {required this.category,
      required this.stock,
      required this.quantity,
      this.coupang,
      this.included = true});
  final ShoppingCategory category;
  final double stock;
  final double? quantity;
  final bool included;
  final CoupangPurchasePlan? coupang;
  double? get purchaseQuantity => coupang?.total ?? quantity;
  bool get ready =>
      !included ||
      (quantity != null &&
          quantity!.isFinite &&
          quantity! >= 0 &&
          quantity! <= 1e9 &&
          stock.isFinite &&
          stock >= 0 &&
          stock <= 1e9);

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'stock': stock,
        'quantity': quantity,
        if (coupang != null) 'coupang': coupang!.toJson(),
        'included': included
      };

  factory PreparedPurchase.fromJson(Map<String, dynamic> json) {
    final stock = (json['stock'] as num).toDouble();
    final quantity = (json['quantity'] as num?)?.toDouble();
    if (!stock.isFinite ||
        stock < 0 ||
        stock > 1e9 ||
        (quantity != null &&
            (!quantity.isFinite || quantity < 0 || quantity > 1e9))) {
      throw const FormatException('Invalid preparation quantity');
    }
    return PreparedPurchase(
        category: ShoppingCategory.values.byName(json['category'] as String),
        stock: stock,
        quantity: quantity,
        coupang: CoupangPurchasePlan.parse(json['coupang']),
        included: json['included'] as bool);
  }
}
