part of 'business_pages.dart';

class _StockActionForm extends ConsumerStatefulWidget {
  const _StockActionForm(
      {required this.workspace,
      required this.action,
      this.item,
      this.source,
      this.receiving,
      required this.items,
      this.onCreated});
  final String workspace, action;
  final BusinessStockItem? item;
  final Map<String, dynamic>? source;
  final BusinessReceiving? receiving;
  final List<BusinessStockItem> items;
  final void Function(BusinessStockItem)? onCreated;
  @override
  ConsumerState<_StockActionForm> createState() => _StockActionFormState();
}

class _StockActionFormState extends ConsumerState<_StockActionForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _spec = TextEditingController(),
      _unit = TextEditingController();
  final _quantity = TextEditingController(),
      _factor = TextEditingController(),
      _reason = TextEditingController();
  late final String? _account = ref.read(activeAccountIdProvider);
  String _token = newShoppingId();
  String? _itemId, _error;
  bool _busy = false, _confirmed = false;
  Map<String, dynamic>? _pending;
  late final List<BusinessStockItem> _items = List.of(widget.items);
  bool get _current =>
      mounted &&
      _account != null &&
      _account == ref.read(activeAccountIdProvider);
  bool get _locked => _busy || _pending != null;
  BusinessStockItem? get _selected {
    for (final i in _items) {
      if (i.id == _itemId) return i;
    }
    return widget.item;
  }

  @override
  void initState() {
    super.initState();
    if (widget.action == 'item') {
      _name.text = widget.source?['name'] as String? ?? '';
      _spec.text = widget.source?['spec'] as String? ?? '';
    }
    _itemId = widget.source?['mapped_item'] as String?;
    if (widget.source?['mapped_factor'] != null) {
      _factor.text =
          menuNumber((widget.source!['mapped_factor'] as num).toDouble());
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _spec, _unit, _quantity, _factor, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _numberError(String? value, {bool signed = false}) =>
      stockQuantityValid(shoppingInput(value ?? ''), signed: signed)
          ? null
          : bt(context, '0이 아닌 수량을 소수 6자리 이내로 입력하세요.',
              'Enter a nonzero quantity with up to 6 decimal places.');
  Map<String, dynamic> _payload() => switch (widget.action) {
        'item' => {
            'name': _name.text.trim(),
            'spec': _spec.text.trim(),
            'unit': _unit.text.trim()
          },
        'adjust' || 'reserve' => {
            'item': widget.item!.id,
            'quantity': double.parse(_quantity.text.trim()),
            'reason': _reason.text.trim()
          },
        'release' || 'consume' => {
            'reservation': widget.source!['id'],
            'revision': widget.source!['revision'],
            if (widget.action == 'consume')
              'quantity': double.parse(_quantity.text.trim()),
            'reason': _reason.text.trim()
          },
        'receive' => {
            'request': widget.receiving!.request,
            'revision': widget.receiving!.revision,
            'line': widget.source!['id'],
            'item': _itemId,
            'quantity': double.parse(_quantity.text.trim()),
            'factor': double.parse(_factor.text.trim()),
            'confirmed': _confirmed,
            'reason': _reason.text.trim()
          },
        'return' => {
            'receipt': widget.source!['id'],
            'quantity': double.parse(_quantity.text.trim()),
            'reason': _reason.text.trim()
          },
        'close' => {
            'request': widget.receiving!.request,
            'revision': widget.receiving!.revision,
            'shortage_accepted': _confirmed,
            'reason': _reason.text.trim()
          },
        _ => throw StateError('BUSINESS_INVALID'),
      };
  Future<void> _save() async {
    if (_busy || !_current || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    if ((widget.action == 'receive' ||
            (widget.action == 'close' && widget.receiving!.hasShortage)) &&
        !_confirmed) {
      setState(() => _error =
          bt(context, '확인 항목을 체크해 주세요.', 'Check the confirmation box.'));
      return;
    }
    final payload = _pending ?? _payload();
    setState(() {
      _busy = true;
      _error = null;
      _pending = payload;
    });
    try {
      final result = await ref
          .read(businessInventoryRepositoryProvider)
          .action(widget.workspace, _token, widget.action, payload);
      if (mounted && _current) {
        if (widget.action == 'item') {
          widget.onCreated?.call(BusinessStockItem.fromJson(
              {...result, 'on_hand': 0, 'reserved': 0, 'available': 0}));
        }
        Navigator.pop(context);
      }
    } catch (e) {
      if (!_current) return;
      // A PostgreSQL error confirms rollback; a transport failure may have committed.
      // Keep the exact action ID and frozen payload for a safe retry in that case.
      final rolledBack = e is PostgrestException &&
          e.code != null &&
          RegExp(r'^[0-9A-Z]{5}$').hasMatch(e.code!);
      setState(() {
        if (rolledBack) {
          _pending = null;
          _token = newShoppingId();
        }
        _error = businessError(context, e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addItem() async {
    final created = await _stockDialog(context, ref, widget.workspace, 'item',
        source: widget.source);
    if (!_current || created == null) return;
    setState(() {
      _items.removeWhere((i) => i.id == created.id);
      _items.add(created);
      _itemId = created.id;
      _factor.clear();
      _confirmed = false;
      final plan = CoupangPurchasePlan.parse(widget.source?['coupang']);
      final factor = plan?.pack.quantityIn(created.unit);
      if (factor != null) _factor.text = menuNumber(factor);
    });
  }

  Widget _field(TextEditingController c, String label,
          {int max = 120,
          bool required = false,
          bool number = false,
          bool signed = false,
          bool readOnly = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              enabled: !_locked,
              readOnly: readOnly,
              maxLength: number ? 24 : max,
              keyboardType: number
                  ? TextInputType.numberWithOptions(
                      decimal: true, signed: signed)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: label, counterText: ''),
              onChanged: (_) => setState(() {
                    if (c == _quantity || c == _factor) _confirmed = false;
                  }),
              validator: (v) => number
                  ? _numberError(v, signed: signed)
                  : required && (v?.trim().isEmpty ?? true)
                      ? bt(context, '필수 입력입니다.', 'This field is required.')
                      : null));
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(businessContextProvider(widget.workspace));
    final b = c.asData?.value;
    final write = b != null &&
        b.can('purchasing.read') &&
        (b.can('purchasing.write') ||
            (['reserve', 'consume', 'release'].contains(widget.action) &&
                b.can('recipes.write')));
    final unit = widget.action == 'return'
        ? ((widget.source?['snapshot'] as Map?)?['line']?['unit'] ?? '')
            .toString()
        : widget.action == 'receive'
            ? widget.source!['unit'] as String
            : widget.item?.unit ?? '';
    final quantity = shoppingInput(_quantity.text),
        factor = shoppingInput(_factor.text);
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
            scrollable: true,
            title: Text(_stockActionLabel(context, widget.action)),
            content: SizedBox(
                width: 560,
                child: !write
                    ? Text(c.isLoading
                        ? bt(context, '권한 확인 중', 'Checking access')
                        : businessError(context, StateError('BUSINESS_DENIED')))
                    : Form(
                        key: _form,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.item != null) ...[
                                Text(widget.item!.label),
                                _stockBalance(context, widget.item!,
                                    inDialog: true),
                                const SizedBox(height: 12)
                              ],
                              if (widget.action == 'item') ...[
                                Text(bt(
                                    context,
                                    '재료명·규격·재고 단위가 같으면 기존 품목을 사용합니다. 실제 관리 단위로 등록하세요. 소유자는 환산 영향을 확인한 뒤 단위를 변경할 수 있습니다.',
                                    'Matching names, specifications and units reuse an existing item. Choose the unit you track. Owners can change units after reviewing the conversion.')),
                                _field(_name,
                                    bt(context, '재료명', 'Ingredient name'),
                                    required: true),
                                _field(
                                    _spec, bt(context, '규격', 'Specification')),
                                _field(
                                    _unit, bt(context, '재고 단위', 'Stock unit'),
                                    required: true, max: 30),
                              ] else ...[
                                if (widget.action == 'adjust')
                                  Text(bt(
                                      context,
                                      '현재고에 더하거나 뺄 차이 수량을 입력합니다. 기초 재고·실사 차이·폐기 등 사유를 남기세요. 예약량보다 현재고를 낮출 수 없습니다.',
                                      'Enter the quantity to add or subtract, with a reason such as opening count, count discrepancy or waste. On-hand stock cannot fall below reservations.')),
                                if (widget.action == 'reserve')
                                  Text(bt(
                                      context,
                                      '메뉴·조리 일정 등 용도를 적고 필요한 양을 예약하세요. 실제 조리한 뒤 사용량을 별도로 기록합니다.',
                                      'Describe the menu or cooking schedule and reserve the quantity needed. Record actual use after cooking.')),
                                if (['release', 'consume']
                                    .contains(widget.action))
                                  LocalizedText(
                                      '${widget.source!['purpose']} · ${bt(context, '남은 예약', 'Remaining reservation')}: ${menuNumber((widget.source!['remaining'] as num).toDouble())} $unit'),
                                if (widget.action == 'return')
                                  LocalizedText(
                                      '${(widget.source?['snapshot'] as Map?)?['line']?['name'] ?? ''}\n${bt(context, '이 입고 기록에서 실제 반품한 양을 입력하세요. 이미 반품한 양과 예약 재고를 제외한 범위만 기록할 수 있습니다.', 'Enter the quantity actually returned from this receipt. Previous returns and reserved stock limit the available return quantity.')}'),
                                if (widget.action == 'return')
                                  LocalizedText(
                                      '${bt(context, '이 입고에서 반품 가능한 잔량', 'Remaining returnable quantity from this receipt')}: ${menuNumber((widget.source!['returnable'] as num? ?? 0).toDouble())} $unit'),
                                if (widget.action == 'receive') ...[
                                  if (_items.isEmpty)
                                    Text(bt(
                                        context,
                                        '입고를 기록하려면 재고 품목을 먼저 등록해 주세요.',
                                        'Add a stock item to record this receipt.')),
                                  if (widget.source?['mapped_item'] == null)
                                    TextButton.icon(
                                        onPressed: _locked ? null : _addItem,
                                        icon: const Icon(Icons.add),
                                        label: Text(bt(context, '재고 품목 등록 후 계속',
                                            'Add stock item & continue'))),
                                  LocalizedText(
                                      '${widget.source!['name']} · ${bt(context, '미입고', 'Outstanding')}: ${menuNumber((widget.source!['outstanding'] as num).toDouble())} $unit'),
                                  DropdownButtonFormField<String>(
                                      initialValue: _itemId,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: bt(context, '반영할 재고 품목',
                                              'Stock item to update')),
                                      items: [
                                        for (final i in _items)
                                          DropdownMenuItem(
                                              value: i.id,
                                              child: Text(i.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged: _locked ||
                                              widget.source?['mapped_item'] !=
                                                  null
                                          ? null
                                          : (v) => setState(() {
                                                _itemId = v;
                                                _factor.clear();
                                                final plan = CoupangPurchasePlan
                                                    .parse(widget
                                                        .source?['coupang']);
                                                final factor = plan?.pack
                                                    .quantityIn(
                                                        _selected?.unit ?? '');
                                                if (factor != null) {
                                                  _factor.text =
                                                      menuNumber(factor);
                                                }
                                                _confirmed = false;
                                              }),
                                      validator: (v) => v == null
                                          ? bt(context, '재고 품목을 선택해 주세요.',
                                              'Select a stock item.')
                                          : null),
                                  const SizedBox(height: 12),
                                  _field(_factor,
                                      '${bt(context, '구매 1단위당 재고량', 'Stock quantity per purchase unit')} (1 $unit → ${_selected?.unit ?? ''})',
                                      number: true,
                                      readOnly:
                                          widget.source?['mapped_factor'] !=
                                              null),
                                ],
                                if (widget.action == 'receive' &&
                                    _selected != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: LocalizedText(
                                          '${bt(context, '단위 환산', 'Unit conversion')}: 1 $unit = ${_factor.text.isEmpty ? '?' : _factor.text} ${_selected!.unit}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                if (!['release', 'close']
                                    .contains(widget.action))
                                  _field(_quantity,
                                      '${bt(context, '이번 수량', 'Quantity this time')} ($unit)',
                                      number: true,
                                      signed: widget.action == 'adjust'),
                                if (widget.action == 'receive') ...[
                                  if (quantity != null &&
                                      factor != null &&
                                      _selected != null &&
                                      (quantity * factor).isFinite)
                                    LocalizedText(
                                        '${bt(context, '재고 증가량', 'Stock increase')}: ${menuNumber(quantity * factor)} ${_selected!.unit}'),
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _confirmed,
                                      onChanged: _locked
                                          ? null
                                          : (v) => setState(
                                              () => _confirmed = v == true),
                                      title: Text(bt(
                                          context,
                                          '실제 품목·수량·단위 환산을 확인했습니다.',
                                          'I verified the actual item, quantity and unit conversion.'))),
                                ],
                                if (widget.action == 'close') ...[
                                  for (final l in widget.receiving!.lines)
                                    if ((l['outstanding'] as num) > 0)
                                      LocalizedText(
                                          '${l['name']}: ${bt(context, '미입고', 'Outstanding')} ${menuNumber((l['outstanding'] as num).toDouble())} ${l['unit']}'),
                                  Text(bt(
                                      context,
                                      '마감 후에는 이 요청에 추가 입고할 수 없습니다. 반품은 기존 입고 이력에서 기록하며, 교환·추가 납품은 새 요청서로 관리합니다.',
                                      'After closing, this request cannot receive further deliveries. Record returns against existing receipts and use a new request for replacements or additional deliveries.')),
                                  if (widget.receiving!.hasShortage)
                                    CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        value: _confirmed,
                                        onChanged: _locked
                                            ? null
                                            : (v) => setState(
                                                () => _confirmed = v == true),
                                        title: Text(bt(
                                            context,
                                            '미입고 잔량을 확인하고 마감합니다.',
                                            'I accept the outstanding quantity and close receiving.'))),
                                ],
                                _field(_reason,
                                    bt(context, '용도·사유', 'Purpose / reason'),
                                    required: true, max: 500),
                              ],
                              if (_error != null)
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              if (_pending != null && !_busy)
                                Text(bt(
                                    context,
                                    '저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 저장하면 중복 기록되지 않습니다.',
                                    'The save result is uncertain. Retrying the same content will not create a duplicate.')),
                              if (_busy) const LinearProgressIndicator(),
                            ]))),
            actions: [
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(bt(context, '닫기', 'Close'))),
              FilledButton(
                  onPressed: _busy || !write ? null : _save,
                  child: Text(bt(context, '기록 저장', 'Save record'))),
            ]));
  }
}
