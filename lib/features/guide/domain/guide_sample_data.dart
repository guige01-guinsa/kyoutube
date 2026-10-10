import '../../chef/domain/chef_recipe.dart';
import '../../chef/domain/chef_sales.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../suppliers/domain/procurement_plan.dart';
import 'guide_purchase_example.dart';

/// Only fictional training records. No account IDs, remote images or contacts.
class GuideSampleProduct {
  GuideSampleProduct(
      {required this.name,
      required this.image,
      this.content = 1,
      this.unit = 'kg',
      this.price = 10000,
      this.origin = '',
      this.region = '',
      this.category = 'vegetables'});
  String name, image, unit, origin, region, category;
  double content, price;
  Map<String, dynamic> toJson() => {
        'name': name,
        'image': image,
        'content': content,
        'unit': unit,
        'price': price,
        'origin': origin,
        'region': region,
        'category': category
      };
  factory GuideSampleProduct.fromJson(Map<String, dynamic> j) =>
      GuideSampleProduct(
          name: j['name'],
          image: j['image'],
          content: (j['content'] as num).toDouble(),
          unit: j['unit'],
          price: (j['price'] as num).toDouble(),
          origin: j['origin'],
          region: j['region'],
          category: j['category']);
}

class GuideSampleData {
  GuideSampleData._(this.english);
  final bool english;
  static const schema = 1;
  static const imageIds = [
    'carrot',
    'onion',
    'tofu',
    'mushroom',
    'egg',
    'rice'
  ];
  final recipes = <String, ChefRecipe>{};
  final versions = <String, List<ChefRecipe>>{};
  final products = <GuideSampleProduct>[];
  final sales = <ChefSale>[];
  final requests = <SupplierRequest>[];
  GuidePurchaseExample purchase = GuidePurchaseExample();
  String selectedRecipe = 'bowl',
      businessName = '',
      businessRegion = '',
      businessIntro = '',
      buyer = '',
      selectedRequest = '',
      search = '';
  bool shoppingCreated = false,
      draftReviewed = false,
      aiReviewed = false,
      published = false;
  final purchaseUnits = <String, String>{
    'carrot': 'kg',
    'onion': 'kg',
    'tofu': 'kg'
  };
  final bought = <String>{};
  final practiced = <String>{};
  int serial = 20;
  late DateTime anchor;
  String t(String ko, String en) => english ? en : ko;
  String ingredientName(String id) => switch (id) {
        'carrot' => t('당근', 'Carrot'),
        'onion' => t('양파', 'Onion'),
        'tofu' => t('두부', 'Tofu'),
        'mushroom' => t('버섯', 'Mushroom'),
        'egg' => t('달걀', 'Egg'),
        'rice' => t('밥', 'Cooked rice'),
        'noodles' => t('면', 'Noodles'),
        _ => t('닭고기', 'Chicken')
      };
  String supplierName(String id) => switch (id) {
        'A' => t('샘플 A · 한곳 식자재', 'Sample A · One-stop Foods'),
        'B' => t('샘플 B · 들녘 채소', 'Sample B · Field Vegetables'),
        'C' => t('샘플 C · 고소한 두부', 'Sample C · Tofu Kitchen'),
        _ => t('샘플 D · 셰프 셀렉트', 'Sample D · Chef Select')
      };
  ChefRecipe get recipe => recipes[selectedRecipe]!;
  void changeRecipe(Map<String, dynamic> fields) {
    recipes[selectedRecipe] =
        ChefRecipe.fromJson({...recipe.toJson(), ...fields});
  }

  void changeIngredient(int index, ChefIngredient ingredient) {
    final rows = [...recipe.ingredients];
    rows[index] = ingredient;
    changeRecipe({'ingredients': rows.map((r) => r.toJson()).toList()});
  }

  void snapshot() {
    final list = versions.putIfAbsent(selectedRecipe, () => []);
    list.insert(0, ChefRecipe.fromJson(recipe.toJson()));
    if (list.length > 20) list.removeLast();
  }

  ChefSalesTotals totals(ChefSalesPeriod period) {
    final range = ChefSalesRange.forDate(anchor, period);
    final rows = sales.where(
        (s) => !s.date.isBefore(range.from) && s.date.isBefore(range.until));
    return ChefSalesTotals(
        quantity: rows.fold(0, (s, r) => s + r.quantity),
        revenue: rows.fold(0, (s, r) => s + r.revenue),
        cost: rows.fold(0, (s, r) => s + r.quantity * r.unitCost));
  }

  void recordSale(int quantity) {
    if (quantity < 1 ||
        quantity > 10000 ||
        recipe.sellingPrice == null ||
        recipe.portionCost == null) {
      throw const FormatException('Invalid sample sale');
    }
    sales.add(ChefSale(
        id: ++serial,
        date: anchor,
        title: recipe.title,
        quantity: quantity,
        unitPrice: recipe.sellingPrice!,
        unitCost: recipe.portionCost!,
        currency: 'KRW'));
  }

  void createRequests() {
    final plan = purchase.compare();
    if (plan == null) {
      throw const FormatException('Select ingredients and candidates');
    }
    final ids = <String>[];
    for (final id in plan.supplierIds) {
      final source = plan.draftFor(id,
          ShoppingSupplier(id: 'sample-supplier-$id', name: supplierName(id)),
          english: english);
      final request = SupplierRequest(
          id: 'sample-${++serial}',
          supplier: source.supplier,
          buyer: buyer,
          address: t('샘플 업소 · 연습용 납품 장소',
              'Sample kitchen · practice delivery address'),
          deliveryDate: chefDate(anchor.add(const Duration(days: 1))),
          deliveryWindow: '09:00–11:00',
          createdAt: anchor,
          notes:
              '${t('연습용 · 실제 주문 아님', 'PRACTICE ONLY · NOT AN ORDER')}\n${source.notes}',
          lines: source.lines
              .map((r) => SupplierRequestLine(
                  id: 'sample-line-${++serial}',
                  name: ingredientName(r.name),
                  quantity: r.quantity,
                  unit: r.unit,
                  price: r.price,
                  spec: r.spec.replaceAll(r.name, ingredientName(r.name))))
              .toList());
      requests.insert(0, request);
      ids.add(request.id);
    }
    selectedRequest = ids.first;
    if (requests.length > 50) requests.removeRange(50, requests.length);
  }

  SupplierRequest get request => requests
      .firstWhere((r) => r.id == selectedRequest, orElse: () => requests.first);
  static Map<String, dynamic> requestJson(SupplierRequest r) => {
        'id': r.id,
        'data': r.data,
        'status': r.status,
        'revision': r.revision,
        'created_at': r.createdAt?.toIso8601String()
      };
  void updateRequest(SupplierRequest r,
      {Map<String, dynamic> fields = const {}, String? status}) {
    final index = requests.indexWhere((v) => v.id == r.id);
    if (index < 0 || !r.id.startsWith('sample-')) {
      throw const FormatException('Not a sample');
    }
    requests[index] = SupplierRequest.fromJson({
      ...requestJson(r),
      'data': {...r.data, ...fields},
      'status': status ?? r.status,
      'revision': r.revision + 1
    });
  }

  void repeatRequest(SupplierRequest source) {
    final repeated = source.repeat();
    final r = SupplierRequest.fromJson({
      ...requestJson(repeated),
      'id': 'sample-${++serial}',
      'created_at': anchor.toIso8601String()
    });
    requests.insert(0, r);
    selectedRequest = r.id;
    if (requests.length > 50) requests.removeLast();
  }

  bool get publishable =>
      businessName.trim().isNotEmpty &&
      businessRegion.trim().isNotEmpty &&
      products.isNotEmpty &&
      products.every((p) =>
          p.name.trim().isNotEmpty &&
          imageIds.contains(p.image) &&
          p.content.isFinite &&
          p.content > 0 &&
          p.price.isFinite &&
          p.price >= 0 &&
          p.unit.trim().isNotEmpty);

  factory GuideSampleData.seed({required bool english, DateTime? now}) {
    final d = GuideSampleData._(english);
    final today = now ?? DateTime.now();
    d.anchor = DateTime(today.year, today.month, today.day);
    d.businessName = d.t('샘플 들녘 식자재', 'Sample Field Foods');
    d.businessRegion = d.t('전국 (샘플)', 'Nationwide (sample)');
    d.businessIntro = d.t('매일 준비하는 채소와 두부. 모든 정보는 체험용입니다.',
        'Vegetables and tofu for daily service. All information is fictional.');
    d.buyer = d.t('샘플 한끼 식당', 'Sample One Meal Kitchen');
    final titles = {
      'bowl': d.t('채소 두부 비빔밥', 'Vegetable & tofu rice bowl'),
      'stew': d.t('두부 버섯찌개', 'Tofu & mushroom stew'),
      'fried-rice': d.t('달걀 볶음밥', 'Egg fried rice'),
      'chicken': d.t('닭고기 덮밥', 'Chicken rice bowl'),
      'noodles': d.t('버섯 볶음면', 'Mushroom noodles')
    };
    for (final e in titles.entries) {
      final main = e.key == 'chicken'
          ? 'chicken'
          : e.key == 'fried-rice'
              ? 'egg'
              : e.key == 'noodles'
                  ? 'mushroom'
                  : 'tofu';
      d.recipes[e.key] = ChefRecipe(
          title: e.value,
          baseServings: 4,
          targetServings: 4,
          markupPercent: 50,
          notes: d.t('연습용 표준 레시피입니다. 실제 조리 기준은 사용자가 검토합니다.',
              'A practice standard recipe. Review your own cooking instructions before real use.'),
          steps: d.t('재료를 손질합니다.\n재료를 충분히 익혀 완성합니다.\n4인분으로 나눕니다.',
              'Prepare the ingredients.\nCook the ingredients thoroughly.\nDivide into 4 servings.'),
          costItems: [
            ChefCostItem(
                id: 'sample-pack',
                name: d.t('포장 및 소모품', 'Packaging & supplies'),
                amount: 200)
          ],
          ingredients: [
            ChefIngredient(
                id: main,
                name: d.ingredientName(main),
                quantity: 800,
                unit: ChefUnit.g,
                purchaseQuantity: 1,
                purchaseUnit: ChefUnit.kg,
                purchasePrice: main == 'chicken' ? 12000 : 6000,
                yieldPercent: 80),
            ChefIngredient(
                id: 'carrot',
                name: d.ingredientName('carrot'),
                quantity: 200,
                unit: ChefUnit.g,
                purchaseQuantity: 1,
                purchaseUnit: ChefUnit.kg,
                purchasePrice: 2000,
                yieldPercent: 90),
            ChefIngredient(
                id: 'onion',
                name: d.ingredientName('onion'),
                quantity: 300,
                unit: ChefUnit.g,
                purchaseQuantity: 1,
                purchaseUnit: ChefUnit.kg,
                purchasePrice: 2000,
                yieldPercent: 90)
          ]);
      var ingredients = [...d.recipes[e.key]!.ingredients];
      if (e.key == 'fried-rice') {
        ingredients[0] = ChefIngredient(
            id: 'egg',
            name: d.ingredientName('egg'),
            quantity: 4,
            unit: ChefUnit.each,
            purchaseQuantity: 10,
            purchaseUnit: ChefUnit.each,
            purchasePrice: 4000);
      }
      if (e.key == 'stew') {
        ingredients[1] = ChefIngredient(
            id: 'mushroom',
            name: d.ingredientName('mushroom'),
            quantity: 200,
            unit: ChefUnit.g,
            purchaseQuantity: 1,
            purchaseUnit: ChefUnit.kg,
            purchasePrice: 8000);
      } else {
        final staple = e.key == 'noodles' ? 'noodles' : 'rice';
        ingredients.add(ChefIngredient(
            id: staple,
            name: d.ingredientName(staple),
            quantity: e.key == 'noodles' ? 400 : 600,
            unit: ChefUnit.g,
            purchaseQuantity: 1,
            purchaseUnit: ChefUnit.kg,
            purchasePrice: 5000));
      }
      d.recipes[e.key] = ChefRecipe.fromJson({
        ...d.recipes[e.key]!.toJson(),
        'ingredients': ingredients.map((r) => r.toJson()).toList()
      });
      final recipe = d.recipes[e.key]!;
      d.versions[e.key] = [
        recipe,
        ChefRecipe.fromJson({...recipe.toJson(), 'markupPercent': 30})
      ];
    }
    for (var i = 0; i < imageIds.length; i++) {
      final id = imageIds[i];
      d.products.add(GuideSampleProduct(
          name: d.ingredientName(id),
          image: id,
          content: 1,
          price: [2000.0, 2000.0, 6000.0, 8000.0, 4000.0, 5000.0][i],
          category: i < 2
              ? 'vegetables'
              : i == 2
                  ? 'tofu'
                  : i == 3
                      ? 'mushrooms'
                      : i == 4
                          ? 'eggs'
                          : 'grains',
          origin: d.t('국산 (샘플)', 'Domestic (sample)'),
          region: d.businessRegion));
    }
    for (var i = 0; i < 8; i++) {
      d.sales.add(ChefSale(
          id: i + 1,
          date:
              d.anchor.subtract(Duration(days: [0, 0, 1, 2, 3, 7, 14, 21][i])),
          title: titles.values.elementAt(i % 5),
          quantity: 10 + i,
          unitPrice: 6000,
          unitCost: 4000,
          currency: 'KRW'));
    }
    d.createRequests();
    final first = d.requests.first;
    for (final status in ['accepted', 'received']) {
      d.requests.add(SupplierRequest.fromJson({
        ...requestJson(first),
        'id': 'sample-${++d.serial}',
        'status': status
      }));
    }
    return d;
  }
  Map<String, dynamic> toJson() => {
        'schema': schema,
        'english': english,
        'anchor': chefDate(anchor),
        'recipes': recipes.map((k, v) => MapEntry(k, v.toJson())),
        'versions': versions
            .map((k, v) => MapEntry(k, v.map((r) => r.toJson()).toList())),
        'products': products.map((p) => p.toJson()).toList(),
        'sales': sales
            .map((s) => {
                  'id': s.id,
                  'sale_date': chefDate(s.date),
                  'recipe_title': s.title,
                  'quantity': s.quantity,
                  'unit_price': s.unitPrice,
                  'unit_cost': s.unitCost,
                  'currency': s.currency
                })
            .toList(),
        'requests': requests.map(requestJson).toList(),
        'serial': serial,
        'selectedRecipe': selectedRecipe,
        'businessName': businessName,
        'businessRegion': businessRegion,
        'businessIntro': businessIntro,
        'buyer': buyer,
        'selectedRequest': selectedRequest,
        'search': search,
        'shoppingCreated': shoppingCreated,
        'draftReviewed': draftReviewed,
        'aiReviewed': aiReviewed,
        'published': published,
        'bought': bought.toList(),
        'purchaseUnits': purchaseUnits,
        'practiced': practiced.toList(),
        'purchase': {
          'quantities': purchase.quantities,
          'selected': purchase.selected.toList(),
          'favorites': purchase.favorites.toList(),
          'candidates':
              purchase.candidates.map((k, v) => MapEntry(k, v.toList())),
          'priority': purchase.priority.name
        }
      };
  factory GuideSampleData.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != schema) {
      throw const FormatException('Unsupported sample schema');
    }
    final d = GuideSampleData._(j['english'] as bool);
    d.anchor = DateTime.parse(j['anchor']);
    for (final e in (j['recipes'] as Map).entries) {
      d.recipes[e.key] =
          ChefRecipe.fromJson(Map<String, dynamic>.from(e.value));
    }
    for (final e in (j['versions'] as Map).entries) {
      d.versions[e.key] = (e.value as List)
          .map((r) => ChefRecipe.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }
    d.products.addAll((j['products'] as List)
        .map((p) => GuideSampleProduct.fromJson(Map<String, dynamic>.from(p))));
    d.sales.addAll((j['sales'] as List)
        .map((s) => ChefSale.fromJson(Map<String, dynamic>.from(s))));
    d.requests.addAll((j['requests'] as List)
        .map((r) => SupplierRequest.fromJson(Map<String, dynamic>.from(r))));
    d.serial = j['serial'];
    d.selectedRecipe = j['selectedRecipe'];
    d.businessName = j['businessName'];
    d.businessRegion = j['businessRegion'];
    d.businessIntro = j['businessIntro'];
    d.buyer = j['buyer'];
    d.selectedRequest = j['selectedRequest'];
    d.search = j['search'];
    d.shoppingCreated = j['shoppingCreated'];
    d.draftReviewed = j['draftReviewed'];
    d.aiReviewed = j['aiReviewed'];
    d.published = j['published'];
    if (j['purchaseUnits'] is Map) {
      for (final id in d.purchaseUnits.keys) {
        final unit = j['purchaseUnits'][id];
        if (unit != 'kg' && unit != 'g') {
          throw const FormatException('Invalid purchase unit');
        }
        d.purchaseUnits[id] = unit;
      }
    }
    d.bought.addAll(List<String>.from(j['bought']));
    d.practiced.addAll(List<String>.from(j['practiced']));
    final p = Map<String, dynamic>.from(j['purchase']);
    for (final item in d.purchase.quantities.keys) {
      d.purchase.quantity(item, (p['quantities'][item] as num).toDouble());
      final ids = List<String>.from(p['candidates'][item]);
      if (ids.length > 3 ||
          ids.toSet().length != ids.length ||
          ids.any((id) => !d.purchase.available(item).contains(id))) {
        throw const FormatException('Invalid sample candidates');
      }
      d.purchase.candidates[item]!
        ..clear()
        ..addAll(ids);
    }
    d.purchase.selected
      ..clear()
      ..addAll(List<String>.from(p['selected']));
    d.purchase.favorites
      ..clear()
      ..addAll(List<String>.from(p['favorites']));
    d.purchase.priority = ProcurementPriority.values.byName(p['priority']);
    if (!d.recipes.containsKey(d.selectedRecipe) ||
        d.requests.isEmpty ||
        d.requests.length > 50 ||
        d.requests.any((r) => !r.id.startsWith('sample-')) ||
        d.products.length != 6 ||
        d.products.any((p) => !imageIds.contains(p.image)) ||
        d.purchase.selected
            .any((id) => !d.purchase.quantities.containsKey(id))) {
      throw const FormatException('Invalid sample data');
    }
    return d;
  }
}
