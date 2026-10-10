import '../../../core/format/user_number.dart';
import '../../../core/localization/localized_text.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'chef_unit_field.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../../workspace/presentation/workspace_frame.dart';
import '../data/chef_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/localization/chef_localizations.dart';
import '../../../core/localization/app_localizations.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../data/chef_repository.dart';
import '../domain/chef_recipe.dart';
import 'chef_cost_items.dart';
import '../../shopping/presentation/shopping_cost_import.dart';
import '../../shopping/domain/shopping_cost_import.dart';

class ChefWorkbenchPage extends ConsumerStatefulWidget {
  const ChefWorkbenchPage(
      {super.key, required this.recipeId, this.initialRecipe});
  final String recipeId;
  final Recipe? initialRecipe;
  @override
  ConsumerState<ChefWorkbenchPage> createState() => _ChefWorkbenchPageState();
}

class _ChefWorkbenchPageState extends ConsumerState<ChefWorkbenchPage> {
  final _form = GlobalKey<FormState>();
  ChefRecipe? _document;
  List<ChefVersion> _versions = [];
  int _revision = 0, _epoch = 0, _ingredientSerial = 0;
  bool _loading = true, _saving = false, _dirty = false, _more = false;
  String? _error;
  bool _loadingMore = false;
  int? _older, _newer;
  bool get _paid => ref.read(chefPaidAccessProvider).valueOrNull == true;
  String t(String key) => chefText(context, key);
  ChefRepository get repository => ref.read(chefRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = widget.initialRecipe ??
          await ref
              .read(recipeRepositoryProvider)
              .getCreatorRecipeById(widget.recipeId);
      if (source == null) throw StateError('missing recipe');
      final work = await repository.load(widget.recipeId);
      final versions = await repository.versions(widget.recipeId);
      if (!mounted) return;
      setState(() {
        _document = work?.document ??
            ChefRecipe.seed(source,
                currency:
                    AppLocalizations.of(context).isEnglish ? 'USD' : 'KRW');
        _revision = work?.revision ?? 0;
        _versions = versions;
        _more = versions.length == 20;
        _dirty = work == null;
        _epoch++;
        _older = versions.length > 1 ? versions[1].number : null;
        _newer = versions.isNotEmpty ? versions.first.number : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'loadError');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _update(String key, Object? value) {
    setState(() {
      _document = ChefRecipe.fromJson({
        ..._document!.toJson(),
        key == 'extraCost' ? 'legacyExtraCost' : key: value
      });
      _dirty = true;
    });
  }

  void _items(List<ChefIngredient> values) =>
      _update('ingredients', values.map((item) => item.toJson()).toList());

  Future<bool> _confirmDiscard() async =>
      !_dirty ||
      await showDialog<bool>(
              context: context,
              builder: (ctx) =>
                  AlertDialog(content: Text(t('discard')), actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(t('confirm'))),
                  ])) ==
          true;

  void _message(String key) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(key))));
  }

  Future<void> _save({bool snapshot = false}) async {
    if (!(_form.currentState?.validate() ?? true)) return;
    String? label;
    var note = '';
    if (snapshot) {
      final key = GlobalKey<FormState>();
      final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(t('snapshot')),
                  scrollable: true,
                  content: Form(
                      key: key,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextFormField(
                            onChanged: (value) => label = value.trim(),
                            maxLength: 80,
                            decoration:
                                InputDecoration(labelText: t('versionLabel')),
                            validator: (s) => s == null || s.trim().isEmpty
                                ? t('required')
                                : null),
                        TextFormField(
                            onChanged: (value) => note = value.trim(),
                            maxLength: 1000,
                            maxLines: 3,
                            decoration:
                                InputDecoration(labelText: t('versionNote'))),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('cancel'))),
                    FilledButton(
                        onPressed: () {
                          if (key.currentState!.validate()) {
                            Navigator.pop(ctx, true);
                          }
                        },
                        child: Text(t('snapshot'))),
                  ]));
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final revision = await repository.save(
          widget.recipeId, _document!, _revision,
          versionLabel: label, versionNote: note);
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _dirty = false;
      });
      if (snapshot) {
        try {
          final versions = await repository.versions(widget.recipeId);
          if (!mounted) return;
          setState(() {
            _versions = versions;
            _more = versions.length == 20;
            _newer = versions.first.number;
            _older = versions.length > 1 ? versions[1].number : null;
          });
        } catch (_) {
          if (mounted) setState(() => _error = 'historyError');
          return;
        }
      }
      if (mounted) _message(snapshot ? 'snapshotSuccess' : 'saveSuccess');
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().contains('CHEF_REVISION_CONFLICT')
                ? 'conflict'
                : error.toString().contains('CHEF_UPGRADE_REQUIRED')
                    ? 'upgradeRequired'
                    : 'saveError');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _money(double? value, {String? currency}) {
    if (value == null) return '—';
    final code = currency ?? _document!.currency;
    return NumberFormat.currency(
            name: code,
            symbol: code == 'KRW' ? '₩' : r'US$',
            decimalDigits: code == 'KRW' ? 0 : 2)
        .format(value);
  }

  Widget _field(String field, String label,
      {bool numeric = false,
      bool required = false,
      int lines = 1,
      int? maxLength,
      double min = 0.001,
      double max = 100000}) {
    final value = _document!.toJson()[field];
    return TextFormField(
      key: ValueKey('chef-$field-$_epoch'),
      initialValue: value == null
          ? ''
          : numeric
              ? chefFormat((value as num).toDouble())
              : value.toString(),
      decoration: InputDecoration(labelText: t(label)),
      maxLines: lines,
      maxLength: maxLength,
      keyboardType:
          numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) {
        if (text == null || text.trim().isEmpty) {
          return required ? t('required') : null;
        }
        if (!numeric) return null;
        final number = parseUserNumber(text);
        return number == null ||
                !number.isFinite ||
                number < min ||
                number > max
            ? t('number')
            : null;
      },
      onChanged: (text) => _update(
          field,
          numeric
              ? (parseUserNumber(text) ?? (field == 'extraCost' ? 0 : null))
              : text),
    );
  }

  Widget _grid(List<Widget> children, {bool metrics = false}) =>
      LayoutBuilder(builder: (_, box) {
        final threshold =
            metrics && MediaQuery.textScalerOf(context).scale(1) <= 1.3
                ? 360
                : 520;
        final width =
            box.maxWidth < threshold ? box.maxWidth : (box.maxWidth - 16) / 2;
        return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList());
      });

  Widget _shoppingAction() => Card(
          child: ListTile(
        leading: const Icon(Icons.shopping_basket_outlined),
        title: Text(workspaceText(context, '장보기 준비', 'Prepare shopping')),
        subtitle: Text(workspaceText(
            context,
            '작업을 저장하고 원본 레시피의 재료에서 구매 수량을 직접 정하세요.',
            'Save this work, then set purchase quantities from the original recipe ingredients.')),
        trailing: const Icon(Icons.chevron_right),
        onTap: _saving || _loading
            ? null
            : () async {
                if (_dirty) await _save();
                if (!mounted || _dirty || _error != null) return;
                context.push(Uri(path: '/shopping-review', queryParameters: {
                  'source': 'creator:${widget.recipeId}'
                }).toString());
              },
      ));

  Widget _section(String title, List<Widget> children, {String? hint}) => Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t(title), style: Theme.of(context).textTheme.titleLarge),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(t(hint), style: Theme.of(context).textTheme.bodySmall)
            ],
            const SizedBox(height: 20),
            ...children,
          ])));

  Widget _metric(String label, String value) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xffe8f0e8),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t(label), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ]));

  Future<void> _editIngredient(
      [ChefIngredient? original, bool priceOnly = false]) async {
    if (original == null && _document!.ingredients.length >= 200) {
      _message('limit');
      return;
    }
    final ingredient = original ??
        ChefIngredient(
            id: 'i-${DateTime.now().microsecondsSinceEpoch}-${_ingredientSerial++}',
            name: '');
    final values = ingredient.toJson();
    final key = GlobalKey<FormState>();
    var unit = ingredient.unit;
    var purchaseUnit = ingredient.purchaseUnit;
    var purchaseImportEpoch = 0;
    final result = await showDialog<ChefIngredient>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, updateDialog) {
              Widget number(String field,
                      {bool mandatory = false,
                      double min = 0.000001,
                      double max = 1e9}) =>
                  Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                          key: ValueKey('$field-$purchaseImportEpoch'),
                          initialValue: values[field] == null
                              ? ''
                              : chefFormat((values[field] as num).toDouble()),
                          decoration: InputDecoration(labelText: t(field)),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (s) {
                            if (s == null || s.isEmpty) {
                              return mandatory ? t('required') : null;
                            }
                            final n = chefInputNumber(s);
                            return n == null ||
                                    !n.isFinite ||
                                    n < min ||
                                    n > max
                                ? t('number')
                                : null;
                          },
                          onChanged: (s) =>
                              values[field] = chefInputNumber(s)));
              Widget units(String label, ChefUnit current,
                      ValueChanged<ChefUnit> onChanged) =>
                  ChefUnitField(
                      key: ValueKey(
                          'chef-unit-$label${purchaseImportEpoch == 0 ? '' : '-$purchaseImportEpoch'}'),
                      label: t(label),
                      value: current,
                      onChanged: (u) => updateDialog(() {
                            if (u != current) {
                              values['purchaseUnitInUsageUnits'] = null;
                            }
                            onChanged(u);
                          }));
              return AlertDialog(
                  title: Text(t(priceOnly
                      ? 'editPrice'
                      : original == null
                          ? 'add'
                          : 'edit')),
                  scrollable: true,
                  content: SizedBox(
                      width: 440,
                      child: Form(
                          key: key,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (priceOnly) Text(ingredient.name),
                                if (!priceOnly) ...[
                                  TextFormField(
                                      initialValue: ingredient.name,
                                      maxLength: 250,
                                      decoration:
                                          InputDecoration(labelText: t('name')),
                                      validator: (s) =>
                                          s == null || s.trim().isEmpty
                                              ? t('required')
                                              : null,
                                      onChanged: (s) => updateDialog(
                                          () => values['name'] = s.trim())),
                                  number('quantity'),
                                  units('unit', unit, (u) => unit = u),
                                  number('yieldPercent',
                                      mandatory: true, min: 0.001, max: 100),
                                  Text(t('yieldHint'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  const SizedBox(height: 16),
                                ],
                                if (_paid) ...[
                                  ShoppingCostImportButton(
                                      ingredientName: values['name'] as String,
                                      currency: _document!.currency,
                                      onSelected: (record) => updateDialog(() {
                                            final imported =
                                                chefIngredientWithPurchase(
                                                    ChefIngredient.fromJson({
                                                      ...values,
                                                      'unit': unit.name,
                                                      'purchaseUnit':
                                                          purchaseUnit.name
                                                    }),
                                                    record,
                                                    _document!.currency);
                                            values.addAll(imported.toJson());
                                            purchaseUnit =
                                                imported.purchaseUnit;
                                            purchaseImportEpoch++;
                                          })),
                                  number('purchaseQuantity'),
                                  units('purchaseUnit', purchaseUnit,
                                      (u) => purchaseUnit = u),
                                  number('purchasePrice', min: 0, max: 1e12),
                                  Text(_document!.currency),
                                  const SizedBox(height: 8),
                                  if (unit.convert(1, purchaseUnit) ==
                                      null) ...[
                                    LocalizedText(
                                        Localizations.localeOf(ctx)
                                                    .languageCode ==
                                                'en'
                                            ? 'Add a conversion to calculate cost: 1 ${purchaseUnit.displayLabel(true)} = how many ${unit.displayLabel(true)}?'
                                            : '원가 계산을 위한 환산 기준을 입력해 주세요. 구매 1${purchaseUnit.displayLabel(false)} = 사용량 몇 ${unit.displayLabel(false)}인가요?',
                                        style:
                                            Theme.of(ctx).textTheme.bodySmall),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      key: ValueKey(
                                          'conversion-${unit.name}-${purchaseUnit.name}${purchaseImportEpoch == 0 ? '' : '-$purchaseImportEpoch'}'),
                                      initialValue: values[
                                                  'purchaseUnitInUsageUnits'] ==
                                              null
                                          ? ''
                                          : chefFormat(
                                              (values['purchaseUnitInUsageUnits']
                                                      as num)
                                                  .toDouble()),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                          labelText:
                                              t('purchaseUnitInUsageUnits'),
                                          suffixText: unit.displayLabel(
                                              Localizations.localeOf(ctx)
                                                      .languageCode ==
                                                  'en')),
                                      validator: (s) {
                                        if (s == null || s.trim().isEmpty) {
                                          return null;
                                        }
                                        final n = chefInputNumber(s);
                                        return n == null ||
                                                !n.isFinite ||
                                                n < 0.000001 ||
                                                n > 1e9
                                            ? t('number')
                                            : null;
                                      },
                                      onChanged: (s) =>
                                          values['purchaseUnitInUsageUnits'] =
                                              chefInputNumber(s),
                                    ),
                                    LocalizedText(
                                        Localizations.localeOf(ctx)
                                                    .languageCode ==
                                                'en'
                                            ? 'Example: 1 pack = 400 g → enter 400. Until supplied, cost remains incomplete. Changing either unit clears this conversion.'
                                            : '예: 1팩=400g이면 400을 입력하세요. 미입력 시 원가는 미완성으로 표시됩니다. 단위를 바꾸면 기준을 다시 입력해 주세요.',
                                        style:
                                            Theme.of(ctx).textTheme.bodySmall),
                                  ],
                                ],
                              ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('cancel'))),
                    FilledButton(
                        onPressed: () {
                          if (!key.currentState!.validate()) return;
                          values['unit'] = unit.name;
                          values['purchaseUnit'] = purchaseUnit.name;
                          Navigator.pop(ctx, ChefIngredient.fromJson(values));
                        },
                        child: Text(t('confirm'))),
                  ]);
            }));
    if (result == null || !mounted) return;
    final items = [..._document!.ingredients];
    final index = items.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      items.add(result);
    } else {
      items[index] = result;
    }
    _items(items);
  }

  Future<void> _copy() async {
    final doc = _document!;
    if (doc.ratio == null ||
        doc.ingredients.any((item) => item.quantity == null)) {
      _message('copyReview');
      return;
    }
    final lines = [
      doc.title,
      '${t('target')}: ${chefFormat(doc.targetServings)}',
      for (final item in doc.ingredients)
        '${item.name} ${chefFormat(item.quantity! * doc.ratio!)} ${item.unit.displayLabel(Localizations.localeOf(context).languageCode != 'ko')}'
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) _message('copied');
  }

  Widget _desktopFormula() {
    final doc = _document!;
    final english = AppLocalizations.of(context).isEnglish;
    return Form(
        key: _form,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: ListView(children: [
                _section(
                    'formula',
                    [
                      _field('title', 'title', required: true, maxLength: 120),
                      const SizedBox(height: 18),
                      _grid([
                        _field('baseServings', 'base', numeric: true),
                        _field('targetServings', 'target', numeric: true)
                      ]),
                    ],
                    hint: 'baseHint'),
                _section(
                    'ingredients',
                    [
                      if (doc.ingredients.isEmpty) Text(t('emptyIngredients')),
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            key: const ValueKey('desktop-chef-ingredients'),
                            columnSpacing: 18,
                            horizontalMargin: 8,
                            dataRowMinHeight: 56,
                            dataRowMaxHeight: 86,
                            headingTextStyle:
                                Theme.of(context).textTheme.labelLarge,
                            columns: [
                              DataColumn(label: Text(t('ingredients'))),
                              DataColumn(label: Text(t('edible'))),
                              DataColumn(label: Text(t('purchase'))),
                              if (_paid)
                                DataColumn(
                                    label: Text(t('lineCost')), numeric: true),
                              DataColumn(label: Text(t('edit'))),
                            ],
                            rows: [
                              for (final item in doc.ingredients)
                                DataRow(cells: [
                                  DataCell(SizedBox(
                                      width: 132,
                                      child: Text(item.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis))),
                                  DataCell(LocalizedText(
                                      '${chefFormat(doc.ratio == null || item.quantity == null ? null : item.quantity! * doc.ratio!)} ${item.unit.displayLabel(english)}')),
                                  DataCell(LocalizedText(
                                      '${chefFormat(doc.ratio == null ? null : item.neededPurchaseUnits(doc.ratio!))} ${item.purchaseUnit.displayLabel(english)}')),
                                  if (_paid)
                                    DataCell(Text(_money(doc.ratio == null
                                        ? null
                                        : item.cost(doc.ratio!)))),
                                  DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_paid)
                                          IconButton(
                                              tooltip: t('editPrice'),
                                              icon: const Icon(
                                                  Icons.price_change_outlined,
                                                  size: 20),
                                              onPressed: () =>
                                                  _editIngredient(item, true)),
                                        IconButton(
                                            tooltip: t('edit'),
                                            icon: const Icon(Icons.tune,
                                                size: 20),
                                            onPressed: () =>
                                                _editIngredient(item)),
                                        IconButton(
                                            tooltip: t('remove'),
                                            icon: const Icon(
                                                Icons.remove_circle_outline,
                                                size: 20),
                                            onPressed: () => _items(doc
                                                .ingredients
                                                .where((x) => x.id != item.id)
                                                .toList())),
                                      ])),
                                ])
                            ],
                          )),
                      const SizedBox(height: 14),
                      Wrap(spacing: 12, children: [
                        OutlinedButton.icon(
                            onPressed: _editIngredient,
                            icon: const Icon(Icons.add),
                            label: Text(t('add'))),
                        TextButton.icon(
                            onPressed: _copy,
                            icon: const Icon(Icons.copy_outlined),
                            label: Text(t('copy'))),
                      ]),
                      if (_paid)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: LocalizedText(
                                '${t('knownCost')}: ${_money(doc.knownBaseCost)}')),
                    ],
                    hint: 'ingredientHint'),
                _shoppingAction(),
                if (_paid)
                  _section(
                      'costItems',
                      [
                        ChefCostItems(
                            document: doc,
                            money: _money,
                            onItemsChanged: (items) => _update('costItems',
                                items.map((item) => item.toJson()).toList()),
                            onLegacyChanged: (value) =>
                                _update('extraCost', value)),
                      ],
                      hint: 'extraHint'),
                _section(
                    'weights',
                    [
                      _grid([
                        _field('inputWeight', 'inputWeight',
                            numeric: true, max: 1e9),
                        _field('outputWeight', 'outputWeight',
                            numeric: true, max: 1e9)
                      ]),
                      const SizedBox(height: 16),
                      _grid([
                        _metric('yield', '${chefFormat(doc.productionYield)}%'),
                        if (_paid) _metric('cost100', _money(doc.costPer100g))
                      ]),
                    ],
                    hint: 'weightHint'),
                _section('steps', [
                  _field('steps', 'steps', lines: 6, maxLength: 30000),
                  const SizedBox(height: 14),
                  _field('notes', 'notes', lines: 3, maxLength: 4000)
                ]),
                Text(t('sourceHint'),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
              ])),
              const SizedBox(width: 22),
              SizedBox(
                  width: 300,
                  child: ListView(children: [
                    Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: const Color(0xff69445f),
                            borderRadius: BorderRadius.circular(20)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LocalizedText('KITCHEN STANDARD',
                                  style: TextStyle(
                                      color: Color(0xfff5ddba),
                                      letterSpacing: 1.6,
                                      fontSize: 10)),
                              const SizedBox(height: 14),
                              Text(
                                  workspaceText(context, '조리의 기준,\n한눈에 확인하세요.',
                                      'Your kitchen standards,\nat a glance.'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4)),
                            ])),
                    const SizedBox(height: 18),
                    if (!_paid) const ChefPaidNotice(),
                    if (_paid) ...[
                      _metric('portionCost', _money(doc.portionCost)),
                      const SizedBox(height: 12),
                      _metric('batchCost', _money(doc.batchCost)),
                      const SizedBox(height: 12),
                      if (doc.incompleteCosts > 0)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: LocalizedText(
                                '${t('incomplete')}\n${t('unknown')}: ${doc.incompleteCosts}')),
                      _section(
                          'pricing',
                          [
                            LocalizedText(
                                '${t('markupPercent')}: ${chefFormat(doc.markupPercent)}%'),
                            Slider(
                                value: doc.markupPercent,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                label: '${chefFormat(doc.markupPercent)}%',
                                onChanged: (value) =>
                                    _update('markupPercent', value)),
                            _metric('sellingPrice', _money(doc.sellingPrice)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                                onPressed: () async {
                                  await _save();
                                  if (!mounted || _dirty || _error != null) {
                                    return;
                                  }
                                  context.push(
                                      '/chef-sales/${Uri.encodeComponent(widget.recipeId)}');
                                },
                                icon: const Icon(Icons.bar_chart),
                                label: Text(t('saveAndSales'))),
                          ],
                          hint: 'pricingHint'),
                      TextButton(
                          onPressed: () => _changeDesktopCurrency(),
                          child: LocalizedText('${t('currency')}: ${doc.currency}')),
                    ],
                    const SizedBox(height: 14),
                    Text(
                        workspaceText(
                            context,
                            '작업 저장 후 같은 계정의 다른 기기에서 확인할 수 있습니다. 조리 완료로 재고를 자동 차감하지 않습니다.',
                            'Save to access this work on another device with the same account. Cooking does not automatically deduct stock.'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 24),
                  ])),
            ])));
  }

  Future<void> _changeDesktopCurrency() async {
    final code = _document!.currency == 'KRW' ? 'USD' : 'KRW';
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: LocalizedText('${t('currency')}: $code'),
                content: Text(t('currencyConfirm')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(t('confirm')))
                ]));
    if (mounted && accepted == true) {
      _update('currency', code);
      setState(() => _epoch++);
    }
  }

  Widget _formula() {
    final doc = _document!;
    return Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                      colors: [Color(0xff69445f), Color(0xff936d83)])),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText('CULINARY WORKSPACE',
                        style: TextStyle(
                            color: Color(0xffefd7ac),
                            letterSpacing: 2,
                            fontSize: 11)),
                    const SizedBox(height: 12),
                    Text(t('intro'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(t('subtitle'),
                        style: const TextStyle(color: Colors.white)),
                  ])),
          if (!_paid) const ChefPaidNotice(),
          if (_paid)
            _grid([
              _metric('portionCost', _money(doc.portionCost)),
              _metric('batchCost', _money(doc.batchCost))
            ], metrics: true),
          const SizedBox(height: 16),
          if (_paid && doc.incompleteCosts > 0)
            Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: LocalizedText(
                    '${t('incomplete')}\n${t('unknown')}: ${doc.incompleteCosts}')),
          _section(
              'formula',
              [
                _field('title', 'title', required: true, maxLength: 120),
                const SizedBox(height: 12),
                _grid([
                  _field('baseServings', 'base', numeric: true),
                  _field('targetServings', 'target', numeric: true)
                ]),
              ],
              hint: 'baseHint'),
          _section(
              'ingredients',
              [
                if (doc.ingredients.isEmpty) Text(t('emptyIngredients')),
                for (final item in doc.ingredients)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xffdce5dd)),
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(item.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 10),
                                    LocalizedText(
                                        '${t('edible')}: ${chefFormat(doc.ratio == null || item.quantity == null ? null : item.quantity! * doc.ratio!)} ${item.unit.displayLabel(Localizations.localeOf(context).languageCode != 'ko')}'),
                                    LocalizedText(
                                        '${t('purchase')}: ${chefFormat(doc.ratio == null ? null : item.neededPurchaseUnits(doc.ratio!))} ${item.purchaseUnit.displayLabel(Localizations.localeOf(context).languageCode != 'ko')}'),
                                    if (_paid)
                                      LocalizedText(
                                          '${t('lineCost')}: ${_money(doc.ratio == null ? null : item.cost(doc.ratio!))}'),
                                    if (_paid &&
                                        item.unit.convert(
                                                1, item.purchaseUnit) ==
                                            null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: LocalizedText(
                                              item.purchaseUnitInUsageUnits ==
                                                      null
                                                  ? t('conversionNeeded')
                                                  : '${t('purchaseUnitInUsageUnits')}: 1 ${item.purchaseUnit.displayLabel(Localizations.localeOf(context).languageCode != 'ko')} = ${chefFormat(item.purchaseUnitInUsageUnits)} ${item.unit.displayLabel(Localizations.localeOf(context).languageCode != 'ko')}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall)),
                                    Wrap(spacing: 8, children: [
                                      if (_paid)
                                        TextButton.icon(
                                            onPressed: () =>
                                                _editIngredient(item, true),
                                            icon: const Icon(
                                                Icons.price_change_outlined),
                                            label: Text(t('editPrice'))),
                                      TextButton.icon(
                                          onPressed: () =>
                                              _editIngredient(item),
                                          icon: const Icon(Icons.tune),
                                          label: Text(t('edit'))),
                                      IconButton(
                                          tooltip: t('remove'),
                                          icon: const Icon(
                                              Icons.remove_circle_outline),
                                          onPressed: () => _items(doc
                                              .ingredients
                                              .where((x) => x.id != item.id)
                                              .toList())),
                                    ]),
                                  ])))),
                OutlinedButton.icon(
                    onPressed: _editIngredient,
                    icon: const Icon(Icons.add),
                    label: Text(t('add'))),
                const SizedBox(height: 12),
                if (_paid)
                  LocalizedText('${t('knownCost')}: ${_money(doc.knownBaseCost)}'),
                TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(t('copy'))),
              ],
              hint: 'ingredientHint'),
          _shoppingAction(),
          if (_paid)
            _section(
                'costItems',
                [
                  DropdownButtonFormField<String>(
                      initialValue: doc.currency,
                      isExpanded: true,
                      key: ValueKey('currency-$_epoch'),
                      decoration: InputDecoration(labelText: t('currency')),
                      items: ['KRW', 'USD']
                          .map((code) =>
                              DropdownMenuItem(value: code, child: Text(code)))
                          .toList(),
                      onChanged: (code) async {
                        if (code == null || code == doc.currency) return;
                        final accepted = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    content: Text(t('currencyConfirm')),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(t('cancel'))),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(t('confirm'))),
                                    ]));
                        if (!mounted) return;
                        if (accepted == true) _update('currency', code);
                        setState(() => _epoch++);
                      }),
                  const SizedBox(height: 16),
                  ChefCostItems(
                      document: doc,
                      money: _money,
                      onItemsChanged: (items) => _update('costItems',
                          items.map((item) => item.toJson()).toList()),
                      onLegacyChanged: (value) => _update('extraCost', value)),
                ],
                hint: 'extraHint'),
          if (_paid)
            _section(
                'pricing',
                [
                  LocalizedText(
                      '${t('markupPercent')}: ${chefFormat(doc.markupPercent)}%'),
                  Slider(
                      value: doc.markupPercent,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${chefFormat(doc.markupPercent)}%',
                      onChanged: (value) => _update('markupPercent', value)),
                  _metric('sellingPrice', _money(doc.sellingPrice)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                      onPressed: () async {
                        await _save();
                        if (!mounted || _dirty || _error != null) return;
                        context.push(Uri(pathSegments: [
                          '',
                          'chef-sales',
                          widget.recipeId
                        ]).toString());
                      },
                      icon: const Icon(Icons.bar_chart),
                      label: Text(t('saveAndSales'))),
                ],
                hint: 'pricingHint'),
          _section(
              'weights',
              [
                _grid([
                  _field('inputWeight', 'inputWeight', numeric: true, max: 1e9),
                  _field('outputWeight', 'outputWeight',
                      numeric: true, max: 1e9)
                ]),
                const SizedBox(height: 16),
                _grid([
                  _metric('yield', '${chefFormat(doc.productionYield)}%'),
                  if (_paid) _metric('cost100', _money(doc.costPer100g))
                ]),
              ],
              hint: 'weightHint'),
          _section('steps', [
            _field('steps', 'steps', lines: 6, maxLength: 30000),
            const SizedBox(height: 12),
            _field('notes', 'notes', lines: 3, maxLength: 4000)
          ]),
          Text(t('sourceHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
        ]));
  }

  Widget _versionSelector(
          String label, int? value, ValueChanged<int?> onChanged) =>
      DropdownButtonFormField<int>(
          key: ValueKey('$label-${value?.toString() ?? ''}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: t(label)),
          items: _versions
              .map((version) => DropdownMenuItem(
                  value: version.number,
                  child: LocalizedText('v${version.number} · ${version.label}',
                      overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged);

  String _diffValue(Object? value, String field) => value is String &&
          const {'unit', 'purchaseUnit'}.contains(field)
      ? ChefUnit.parse(value)
          .displayLabel(Localizations.localeOf(context).languageCode != 'ko')
      : value is num
          ? chefFormat(value.toDouble())
          : value?.toString() ?? '—';

  Widget _history(BuildContext tabContext) {
    final older =
        _versions.where((version) => version.number == _older).firstOrNull;
    final newer =
        _versions.where((version) => version.number == _newer).firstOrNull;
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (older != null && newer != null) _comparison(older, newer),
      _section('versions', [
        Text(t('versionHint')),
        const SizedBox(height: 16),
        if (_versions.isEmpty) Text(t('noVersions')),
        for (final version in _versions)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LocalizedText('v${version.number} · ${version.label}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(DateFormat('yyyy-MM-dd HH:mm')
                            .format(version.createdAt.toLocal())),
                        if (version.note.isNotEmpty) Text(version.note),
                        LocalizedText(
                            '${t('portionCost')}: ${_money(version.document.portionCost, currency: version.document.currency)}'),
                        TextButton.icon(
                            onPressed: () async {
                              if (!await _confirmDiscard() || !mounted) return;
                              setState(() {
                                _document = version.document;
                                _dirty = true;
                                _epoch++;
                              });
                              if (tabContext.mounted) {
                                DefaultTabController.of(tabContext)
                                    .animateTo(0);
                              }
                            },
                            icon: const Icon(Icons.restore),
                            label: Text(t('restore'))),
                      ]))),
        if (_more)
          TextButton(
              onPressed: _loadingMore
                  ? null
                  : () async {
                      setState(() => _loadingMore = true);
                      try {
                        final more = await repository.versions(widget.recipeId,
                            beforeVersion: _versions.last.number);
                        if (!mounted) return;
                        setState(() {
                          _versions = [..._versions, ...more];
                          _more = more.length == 20;
                        });
                      } catch (_) {
                        if (mounted) _message('loadError');
                      } finally {
                        if (mounted) setState(() => _loadingMore = false);
                      }
                    },
              child: Text(t('more'))),
      ]),
    ]);
  }

  Widget _comparison(ChefVersion older, ChefVersion newer) {
    final changes = older.document
        .compare(newer.document)
        .where((change) =>
            _paid ||
            !const {
              'purchasePrice',
              'purchaseQuantity',
              'purchaseUnit',
              'currency',
              'markupPercent',
              'extraCost',
              'costItem',
              'costName',
              'costAmount'
            }.contains(change.field))
        .toList();
    return _section('compare', [
      _grid([
        _versionSelector('older', _older, (v) => setState(() => _older = v)),
        _versionSelector('newer', _newer, (v) => setState(() => _newer = v))
      ]),
      const SizedBox(height: 20),
      if (_paid) Text(t('portionCost')),
      const SizedBox(height: 8),
      if (_paid)
        _grid([
          _metric(
              'before',
              _money(older.document.portionCost,
                  currency: older.document.currency)),
          _metric(
              'after',
              _money(newer.document.portionCost,
                  currency: newer.document.currency)),
        ], metrics: true),
      const SizedBox(height: 20),
      if (changes.isEmpty) Text(t('noChanges')),
      for (final change in changes)
        Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      (change.ingredient == null
                              ? ''
                              : '${change.ingredient!} · ') +
                          t(change.field),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  LocalizedText(
                      '${t('before')}: ${_diffValue(change.before, change.field)}'),
                  LocalizedText(
                      '${t('after')}: ${_diffValue(change.after, change.field)}'),
                ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chefPaidAccessProvider);
    return DefaultTabController(
        length: 2,
        child: Builder(
            builder: (tabContext) => PopScope(
                canPop: !_dirty && !_saving,
                onPopInvokedWithResult: (didPop, _) async {
                  if (didPop ||
                      _saving ||
                      !await _confirmDiscard() ||
                      !mounted) {
                    return;
                  }
                  setState(() => _dirty = false);
                  await WidgetsBinding.instance.endOfFrame;
                  if (context.mounted) context.pop();
                },
                child: WorkspaceEditGuard(
                    dirty: _dirty,
                    busy: _saving,
                    confirmLeave: _confirmDiscard,
                    child: Scaffold(
                      appBar: AppBar(
                          title: Text(t('studio')),
                          actions: [
                            GuideHelpButton(
                                lesson: 'pro-scale', enabled: !_saving)
                          ],
                          bottom: _document == null
                              ? null
                              : TabBar(tabs: [
                                  Tab(text: t('formula')),
                                  Tab(text: t('versions')),
                                ])),
                      body: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _document == null
                              ? Center(
                                  child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(t(_error ?? 'loadError')),
                                            TextButton(
                                                onPressed: _load,
                                                child: Text(t('reload'))),
                                          ])))
                              : Column(children: [
                                  if (_error != null)
                                    Material(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .errorContainer,
                                        child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(children: [
                                              Text(t(_error!)),
                                              TextButton(
                                                  onPressed: _saving
                                                      ? null
                                                      : () async {
                                                          if (await _confirmDiscard() &&
                                                              mounted) {
                                                            _load();
                                                          }
                                                        },
                                                  child: Text(t('reload'))),
                                            ]))),
                                  Expanded(
                                      child: AbsorbPointer(
                                          absorbing: _saving,
                                          child: Center(
                                              child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          maxWidth: 1440),
                                                  child: TabBarView(children: [
                                                    LayoutBuilder(
                                                        builder: (_, box) => box
                                                                        .maxWidth >=
                                                                    1000 &&
                                                                MediaQuery.textScalerOf(
                                                                            context)
                                                                        .scale(
                                                                            1) <=
                                                                    1.3
                                                            ? _desktopFormula()
                                                            : _formula()),
                                                    _history(tabContext)
                                                  ]))))),
                                ]),
                      bottomNavigationBar: _document == null
                          ? null
                          : SafeArea(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(t(_dirty ? 'unsaved' : 'saved'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                        const SizedBox(height: 6),
                                        Wrap(
                                            spacing: 10,
                                            runSpacing: 6,
                                            alignment: WrapAlignment.center,
                                            children: [
                                              OutlinedButton.icon(
                                                  onPressed: _saving || _loading
                                                      ? null
                                                      : () => _save(),
                                                  icon: const Icon(
                                                      Icons.save_outlined),
                                                  label: Text(t('save'))),
                                              FilledButton.icon(
                                                  onPressed: _saving || _loading
                                                      ? null
                                                      : () =>
                                                          _save(snapshot: true),
                                                  icon: _saving
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2))
                                                      : const Icon(Icons
                                                          .add_box_outlined),
                                                  label: Text(t('snapshot'))),
                                            ]),
                                      ]))),
                    )))));
  }
}
