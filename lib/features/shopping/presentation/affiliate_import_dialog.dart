import 'dart:async';
import 'dart:math';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/localized_text.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import '../domain/affiliate_import.dart';
import 'shopping_assistant_dialogs.dart';

class AffiliateImportDialog extends ConsumerStatefulWidget {
  const AffiliateImportDialog({super.key});
  @override
  ConsumerState<AffiliateImportDialog> createState() =>
      _AffiliateImportDialogState();
}

class _AffiliateImportDialogState extends ConsumerState<AffiliateImportDialog> {
  final _text = TextEditingController();
  List<AffiliateImportRow> _rows = [];
  List<AffiliateImportRow>? _retryRows;
  static const _timeout = Duration(seconds: 30);
  final _existing = <int, Map<String, dynamic>>{}, _results = <int, String>{};
  final _selected = <int>{};
  bool _busy = false, _ready = false;
  int _saved = 0, _saveTotal = 0;
  String? _error;
  String _filename = '';
  late final _account = ref.read(activeAccountIdProvider);
  bool get _same =>
      mounted &&
      _account != null &&
      ref.read(activeAccountIdProvider) == _account;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _retryRows = null;
    _ready = false;
    _rows = [];
    _selected.clear();
    _existing.clear();
    _results.clear();
    _saved = 0;
    _saveTotal = 0;
    _error = null;
  }

  String _importError(Object error, {required bool parsed}) {
    if (error is PostgrestException) {
      if (error.message == 'ADMIN_MFA_REQUIRED') {
        return '2단계 인증을 완료해 주세요.';
      }
      if (error.message == 'ADMIN_REQUIRED' || error.code == '42501') {
        return '관리자 권한이 필요합니다. 권한이 변경됐다면 다시 확인해 주세요.';
      }
      if (error.code == 'PGRST301' || error.code == 'PGRST303') {
        return '로그인 후 계속할 수 있습니다.';
      }
    }
    if (parsed) {
      return '목록은 읽었지만 서버에서 중복 확인을 완료하지 못했습니다. 연결을 확인하고 미리보기를 다시 실행해 주세요.';
    }
    if (error is FormatException) {
      switch (error.message) {
        case 'empty':
          return '가져올 상품이 없습니다. 제목 행과 상품 목록을 함께 입력해 주세요.';
        case 'encoding':
          return '이 CSV는 한글 CP949 형식입니다. 엑셀에서 CSV UTF-8로 저장하거나 XLSX 파일을 선택해 주세요. 표를 제목 행과 함께 복사해 붙여넣어도 됩니다.';
        case 'size':
        case 'file_size':
          return '파일이나 붙여넣은 내용이 너무 큽니다. 2MB 이하로 나누어 가져와 주세요.';
        case 'row_limit':
          return '한 번에 상품 2,000개까지 가져올 수 있습니다. 목록을 나누어 주세요.';
        case 'headers':
          return '첫 행의 상품명·제휴 링크 제목을 확인해 주세요. 같은 제목의 열은 한 번만 사용합니다.';
        case 'quotes':
          return 'CSV의 따옴표가 맞지 않습니다. 엑셀에서 CSV UTF-8로 다시 저장하거나 표를 복사해 붙여넣어 주세요.';
      }
    }
    return '파일이나 표를 읽지 못했습니다. XLSX 또는 CSV UTF-8 파일을 사용하거나 제목 행을 포함한 표를 붙여넣어 주세요.';
  }

  Future<void> _file() async {
    if (_busy || !_same) return;
    var parsed = false;
    var reading = false;
    setState(() => _busy = true);
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'Catalog', extensions: [
          'txt',
          'csv',
          'tsv',
          'xlsx'
        ], mimeTypes: [
          'text/plain',
          'text/csv',
          'text/tab-separated-values',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        ], uniformTypeIdentifiers: [
          'public.text',
          'public.comma-separated-values-text',
          'org.openxmlformats.spreadsheetml.sheet'
        ])
      ]);
      if (!_same || file == null) return;
      setState(() {
        _clear();
        _filename = file.name;
      });
      reading = true;
      if (await file.length().timeout(_timeout) > AffiliateImport.maxBytes) {
        throw const FormatException('size');
      }
      final bytes = await file.readAsBytes().timeout(_timeout);
      if (!_same) return;
      reading = false;
      final rows = AffiliateImport.file(file.name, bytes);
      _text.clear();
      parsed = true;
      await _preview(rows);
    } catch (error) {
      if (_same) {
        setState(() => _error = reading && error is! FormatException
            ? '선택한 파일을 읽지 못했습니다. 파일을 다시 선택하거나 표를 복사해 목록 입력란에 붙여넣어 주세요.'
            : _importError(error, parsed: parsed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    if (_busy || !_same) return;
    var parsed = false;
    setState(() {
      _busy = true;
      _clear();
      _filename = '';
    });
    try {
      final rows = AffiliateImport.text(_text.text);
      parsed = true;
      await _preview(rows);
    } catch (error) {
      if (_same) {
        setState(() => _error = _importError(error, parsed: parsed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clipboard() async {
    if (_busy || !_same) return;
    setState(() => _busy = true);
    try {
      final data =
          await Clipboard.getData(Clipboard.kTextPlain).timeout(_timeout);
      if (!_same) return;
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        setState(() => _error = '클립보드가 비어 있습니다. 엑셀 표나 상품 목록을 먼저 복사해 주세요.');
        return;
      }
      setState(() {
        _clear();
        _filename = '';
        _text.text = text;
      });
    } catch (_) {
      if (_same) {
        setState(() =>
            _error = '클립보드를 읽지 못했습니다. 목록 입력란을 누르고 Ctrl+V 또는 붙여넣기를 사용해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(List<AffiliateImportRow> rows) async {
    setState(() {
      _rows = rows;
      _retryRows = rows;
    });
    final existing = <int, Map<String, dynamic>>{};
    final indices = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].error == null) i
    ];
    for (var start = 0; start < indices.length; start += 100) {
      if (!_same) return;
      final group = indices.sublist(start, min(start + 100, indices.length));
      final result = await ref
          .read(shoppingAffiliateRepositoryProvider)
          .preview(group.map((i) => rows[i].data).toList())
          .timeout(_timeout);
      if (result.length != group.length) throw const FormatException('preview');
      for (var j = 0; j < group.length; j++) {
        existing[group[j]] = result[j];
      }
    }
    if (!_same) return;
    setState(() {
      _rows = rows;
      _existing.addAll(existing);
      _ready = true;
      _retryRows = null;
      for (final i in indices) {
        if (existing[i]?.isEmpty == true) _selected.add(i);
      }
    });
  }

  Future<void> _retryPreview() async {
    final rows = _retryRows;
    if (_busy || !_same || rows == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preview(rows);
    } catch (error) {
      if (_same) setState(() => _error = _importError(error, parsed: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_ready || _selected.isEmpty || !_same) return;
    final indices = _selected.toList()..sort();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: const LocalizedText('선택 항목 등록'),
                    content: const LocalizedText(
                        '선택한 항목만 초안으로 저장합니다. 기존 상품을 선택했다면 해당 내용을 교체하고 공개를 중단합니다.'),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const LocalizedText('취소')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LocalizedText('저장'))
                ])));
    if (confirmed != true || !_same) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = 0;
      _saveTotal = indices.length;
    });
    try {
      for (var start = 0; start < indices.length; start += 100) {
        if (!_same) return;
        final group = indices.sublist(start, min(start + 100, indices.length));
        final batch = [
          for (final i in group)
            {
              'action': _existing[i]?.isNotEmpty == true ? 'update' : 'create',
              'data': {
                ..._rows[i].data,
                if (_existing[i]?.isNotEmpty == true) ...{
                  'id': _existing[i]!['id'],
                  'revision': _existing[i]!['revision']
                }
              }
            }
        ];
        final results = await ref
            .read(shoppingAffiliateRepositoryProvider)
            .importRows(batch)
            .timeout(_timeout);
        if (!_same) return;
        if (results.length != group.length) {
          throw const FormatException('results');
        }
        setState(() {
          _saved += group.length;
          for (var j = 0; j < group.length; j++) {
            _results[group[j]] = results[j]['status'] as String;
            _selected.remove(group[j]);
          }
        });
      }
    } catch (_) {
      if (_same) {
        setState(() {
          _error = '응답을 확인하지 못했습니다. 목록을 다시 불러와 저장 여부를 확인한 뒤 재시도하세요.';
          _ready = false;
          _selected.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_same) ref.invalidate(shoppingAffiliatesProvider);
  }

  String _status(int i) {
    if (_results.containsKey(i)) {
      return switch (_results[i]) {
        'saved' => '저장 완료',
        'duplicate' => '중복 링크',
        'stale' => '수정 충돌',
        'deleted' => '휴지통 상품',
        _ => '입력 오류'
      };
    }
    if (_rows[i].error != null) {
      return _rows[i].error == 'duplicate' ? '목록 내 중복' : '입력 오류';
    }
    if (!_ready) return '중복 확인 필요';
    if (_existing[i]?['deleted'] == true) return '휴지통 상품';
    return _existing[i]?.isNotEmpty == true ? '기존 상품 수정' : '신규 등록';
  }

  bool _canSelect(int i) =>
      _ready &&
      _rows[i].error == null &&
      _existing[i]?['deleted'] != true &&
      !_results.containsKey(i);
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        title: const LocalizedText('목록 가져오기'),
        content: SizedBox(
            width: 760,
            height: MediaQuery.sizeOf(context).height * .65,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    const LocalizedText(
                        'TXT·CSV·TSV·XLSX, 최대 2MB·2,000행. 엑셀은 첫 번째 시트를 읽습니다.'),
                    const LocalizedText(
                        '상품명과 제휴 링크는 필수입니다. 같은 링크는 중복 확인하며 기존 상품은 직접 선택해야 수정됩니다.'),
                    const LocalizedText(
                        '재료가 비어 있으면 상품명을 사용합니다. 엑셀 표는 제목 행부터 복사해 붙여넣을 수 있습니다.'),
                    const SelectableText(
                        'source_code,category,title,specification,brand,ingredients,link'),
                    const SizedBox(height: 12),
                    const LocalizedText(
                        'CSV를 만들기 어렵다면 아래에 한 줄씩 붙여넣으세요. 재료명 | 상품명 | 제휴 링크 순서이며, 상품명 | 제휴 링크만 입력해도 됩니다.'),
                    TextField(
                        controller: _text,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 6,
                        decoration:
                            InputDecoration(labelText: context.tr('목록 붙여넣기')),
                        onChanged: (_) => setState(() {
                              _clear();
                              _filename = '';
                            })),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                          onPressed: _busy ? null : _file,
                          child: const LocalizedText('파일 선택')),
                      TextButton.icon(
                          onPressed: _busy ? null : _clipboard,
                          icon: const Icon(Icons.content_paste),
                          label: const LocalizedText('클립보드에서 붙여넣기')),
                      OutlinedButton(
                          onPressed: _busy || _text.text.trim().isEmpty
                              ? null
                              : _paste,
                          child: const LocalizedText('중복 확인·미리보기')),
                      if (_filename.isNotEmpty) Text(_filename)
                    ]),
                    if (_busy) const LinearProgressIndicator(),
                    if (_busy && _saveTotal > 0)
                      LocalizedText('$_saved / $_saveTotal 저장 중'),
                    if (_error != null) LocalizedText(_error!),
                    if (_retryRows != null && !_ready && !_busy)
                      TextButton(
                          onPressed: _retryPreview,
                          child: const LocalizedText('중복 확인 다시 시도')),
                    Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          LocalizedText(
                              '${_selected.length} / ${_rows.length}'),
                          TextButton(
                              onPressed: _busy || !_ready
                                  ? null
                                  : () => setState(() {
                                        _selected.clear();
                                        for (var i = 0; i < _rows.length; i++) {
                                          if (_canSelect(i) &&
                                              _existing[i]?.isEmpty == true) {
                                            _selected.add(i);
                                          }
                                        }
                                      }),
                              child: const LocalizedText('신규 항목 모두 선택')),
                          TextButton(
                              onPressed: _busy || !_ready
                                  ? null
                                  : () => setState(() {
                                        _selected.clear();
                                        for (var i = 0; i < _rows.length; i++) {
                                          if (_canSelect(i)) _selected.add(i);
                                        }
                                      }),
                              child: const LocalizedText('기존 포함 모두 선택')),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(_selected.clear),
                              child: const LocalizedText('선택 해제'))
                        ]),
                  ])),
              SliverList.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) => CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(i),
                      onChanged: _busy || !_canSelect(i)
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(i);
                                } else {
                                  _selected.remove(i);
                                }
                              }),
                      title: LocalizedText(
                          '${_rows[i].line}. ${_rows[i].data['title']}'),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LocalizedText(_status(i)),
                            LocalizedText(
                                '${_rows[i].data['category'] ?? ''} · ${_rows[i].data['link']}'),
                            if (_existing[i]?['title'] != null)
                              LocalizedText('← ${_existing[i]!['title']}')
                          ]))),
            ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const LocalizedText('닫기')),
          FilledButton(
              onPressed: _busy || !_ready || _selected.isEmpty ? null : _save,
              child: const LocalizedText('선택 항목 등록'))
        ],
      ));
}
