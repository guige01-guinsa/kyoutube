import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import 'shopping_assistant_dialogs.dart';

/// Selecting a name changes only the name; callers own quantity/plan invalidation.
class PurchaseNameField extends ConsumerStatefulWidget {
  const PurchaseNameField(
      {super.key,
      this.controller,
      this.initialValue = '',
      this.workspace,
      required this.decoration,
      required this.onChanged,
      this.enabled = true,
      this.maxLength = 250,
      this.validator});
  final TextEditingController? controller;
  final String initialValue;
  final String? workspace;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final int maxLength;
  final FormFieldValidator<String>? validator;
  @override
  ConsumerState<PurchaseNameField> createState() => _PurchaseNameFieldState();
}

class _PurchaseNameFieldState extends ConsumerState<PurchaseNameField> {
  late final _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue);
  Timer? _timer;
  String _query = '';
  int _offset = 0;
  String? _owner;
  String t(String ko, String en) => shopText(context, ko, en);
  void _search() {
    _timer?.cancel();
    if (!widget.enabled) {
      return;
    }
    setState(() {
      _owner = ref.read(activeAccountIdProvider);
      _query = _controller.text.trim();
      _offset = 0;
    });
  }

  void _changed(String value) {
    _timer?.cancel();
    setState(() => _query = ''); // Never show a previous query's results.
    widget.onChanged(value);
    final owner = ref.read(activeAccountIdProvider);
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && ref.read(activeAccountIdProvider) == owner) _search();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountIdProvider);
    final show = widget.enabled &&
        account != null &&
        account == _owner &&
        _query.isNotEmpty &&
        _query == _controller.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
          controller: _controller,
          enabled: widget.enabled,
          maxLength: widget.maxLength,
          validator: widget.validator,
          decoration: widget.decoration.copyWith(
              suffixIcon: IconButton(
                  tooltip: t('품명 후보 찾기', 'Find matching names'),
                  onPressed: widget.enabled ? _search : null,
                  icon: const Icon(Icons.search))),
          onChanged: _changed),
      if (show)
        ref
            .watch(purchaseNamesProvider(
                (query: _query, offset: _offset, workspace: widget.workspace)))
            .when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Wrap(children: [
                      Text(t('후보를 불러오지 못했습니다. 직접 입력하거나 다시 조회해 주세요.',
                          'Could not load suggestions. Enter a name or retry.')),
                      TextButton(
                          onPressed: () => ref.invalidate(
                                  purchaseNamesProvider((
                                query: _query,
                                offset: _offset,
                                workspace: widget.workspace
                              ))),
                          child: Text(t('다시 조회', 'Retry')))
                    ]),
                data: (rows) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (rows.isEmpty)
                            Text(t('일치하는 등록 품명이 없습니다. 입력한 이름을 그대로 사용할 수 있습니다.',
                                'No registered names match. You can use the name you entered.')),
                          for (final row in rows.take(5))
                            ListTile(
                                dense: true,
                                title: Text(row.name),
                                subtitle: Text(row.exampleTitle),
                                trailing:
                                    const Icon(Icons.north_west, size: 18),
                                onTap: () {
                                  if (ref.read(activeAccountIdProvider) !=
                                          _owner ||
                                      !widget.enabled) {
                                    return;
                                  }
                                  _timer?.cancel();
                                  _controller.value = TextEditingValue(
                                      text: row.name,
                                      selection: TextSelection.collapsed(
                                          offset: row.name.length));
                                  setState(() => _query = '');
                                  widget.onChanged(row.name);
                                }),
                          Wrap(children: [
                            if (_offset > 0)
                              TextButton(
                                  onPressed: () => setState(() => _offset -= 5),
                                  child: Text(t('이전 결과', 'Previous'))),
                            if (rows.length > 5)
                              TextButton(
                                  onPressed: () => setState(() => _offset += 5),
                                  child: Text(t('다음 결과', 'More results'))),
                            TextButton(
                                onPressed: () => setState(() => _query = ''),
                                child:
                                    Text(t('입력한 이름 사용', 'Use entered name'))),
                          ]),
                        ])),
    ]);
  }
}
