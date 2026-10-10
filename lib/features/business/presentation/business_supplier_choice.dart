part of 'business_pages.dart';

class BusinessSupplierChoice<T> extends StatefulWidget {
  const BusinessSupplierChoice(
      {super.key,
      required this.title,
      this.future,
      this.load,
      required this.label,
      required this.detail,
      this.notice,
      this.onCreate,
      this.createLabel})
      : assert(future != null || load != null);
  final String title;
  final String? notice, createLabel;
  final Future<List<T>>? future;
  final Future<List<T>> Function()? load;
  final Future<T?> Function()? onCreate;
  final String Function(T) label, detail;
  @override
  State<BusinessSupplierChoice<T>> createState() =>
      _BusinessSupplierChoiceState<T>();
}

class _BusinessSupplierChoiceState<T> extends State<BusinessSupplierChoice<T>> {
  final _search = TextEditingController();
  late Future<List<T>> _future = widget.load?.call() ?? widget.future!;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await widget.onCreate!();
      if (!mounted) return;
      if (row != null) {
        Navigator.pop(context, row);
        return;
      }
      if (widget.load != null) {
        setState(() {
          _future = widget.load!();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
            width: 550,
            height: 420,
            child: Column(children: [
              if (widget.notice != null) Text(widget.notice!),
              TextField(
                  controller: _search,
                  enabled: !_busy,
                  decoration: InputDecoration(
                      labelText: bt(context, '검색', 'Search'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                          tooltip: bt(context, '검색 지우기', 'Clear search'))),
                  onChanged: (_) => setState(() {})),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                  child: FutureBuilder<List<T>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(businessError(context, snapshot.error!)),
                                if (widget.load != null)
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                                _future = widget.load!();
                                              }),
                                      child: Text(
                                          bt(context, '다시 불러오기', 'Reload'))),
                              ]));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final rows = snapshot.data!
                            .where((s) => productSearchMatches(
                                '${widget.label(s)} ${widget.detail(s)}',
                                _search.text))
                            .toList();
                        return ListView(children: [
                          if (rows.isEmpty)
                            Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(snapshot.data!.isEmpty
                                    ? bt(context, '등록된 항목이 없습니다.',
                                        'No registered items.')
                                    : bt(
                                        context,
                                        '검색 결과가 없습니다. 검색어를 바꾸거나 지워 주세요.',
                                        'No matches. Change or clear the search.'))),
                          for (final row in rows)
                            ListTile(
                                title: Text(widget.label(row)),
                                subtitle: Text(widget.detail(row)),
                                onTap: _busy
                                    ? null
                                    : () => Navigator.pop(context, row)),
                        ]);
                      })),
            ])),
        actions: [
          if (widget.onCreate != null)
            FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: Text(
                    widget.createLabel ?? bt(context, '새로 등록', 'Add new'))),
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(bt(context, '취소', 'Cancel'))),
        ],
      ));
}
