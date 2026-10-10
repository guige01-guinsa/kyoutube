import '../../../core/localization/localized_text.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../application/request_document_service.dart';
import '../domain/supplier_request.dart';
import 'business_registration_widgets.dart';
import 'shopping_assistant_dialogs.dart';

class RequestDocumentPreview extends ConsumerStatefulWidget {
  const RequestDocumentPreview({super.key, required this.request});
  final SupplierRequest request;
  @override
  ConsumerState<RequestDocumentPreview> createState() =>
      _RequestDocumentPreviewState();
}

class _RequestDocumentPreviewState
    extends ConsumerState<RequestDocumentPreview> {
  bool _buyerCopy = false, _supplierCopy = false;
  int _generation = 0;
  late final _owner = ref.read(activeAccountIdProvider);
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  Widget build(BuildContext context) => PurchasePdfPreview(
        title: t('구매요청서 PDF 미리보기', 'Purchase request PDF preview'),
        filename: widget.request.reference,
        generation: _generation,
        controls: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final item in [
            (
              true,
              widget.request.buyerBusiness,
              t('요청 업소 사업자등록증', 'Buyer registration certificate')
            ),
            (
              false,
              widget.request.supplierBusiness,
              t('공급업체 사업자등록증', 'Supplier registration certificate')
            ),
          ])
            if (item.$2.imagePath.isNotEmpty)
              Row(children: [
                Expanded(
                    child: CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title:
                            LocalizedText('${item.$3} ${t('사본 포함', 'copy included')}'),
                        value: item.$1 ? _buyerCopy : _supplierCopy,
                        onChanged: (v) => setState(() {
                              if (item.$1) {
                                _buyerCopy = v!;
                              } else {
                                _supplierCopy = v!;
                              }
                              _generation++;
                            }))),
                IconButton(
                    onPressed: () => showBusinessDocument(context,
                        title: item.$3, registration: item.$2),
                    tooltip: t('등록증 보기', 'View certificate'),
                    icon: const Icon(Icons.image_outlined)),
              ]),
        ]),
        buildDocument: () => ref.read(requestDocumentBuildProvider)(
            widget.request,
            english: Localizations.localeOf(context).languageCode != 'ko',
            buyerCopy: _buyerCopy,
            supplierCopy: _supplierCopy,
            accountStillActive: () =>
                mounted &&
                _owner != null &&
                ref.read(activeAccountIdProvider) == _owner),
      );
}

/// The preview, exported PDF and print callback use exactly the same bytes.
class PurchasePdfPreview extends ConsumerStatefulWidget {
  const PurchasePdfPreview(
      {super.key,
      required this.title,
      required this.filename,
      required this.buildDocument,
      this.generation = 0,
      this.controls});
  final String title, filename;
  final Future<Uint8List> Function() buildDocument;
  final int generation;
  final Widget? controls;
  @override
  ConsumerState<PurchasePdfPreview> createState() => _PurchasePdfPreviewState();
}

class _PurchasePdfPreviewState extends ConsumerState<PurchasePdfPreview> {
  late final _owner = ref.read(activeAccountIdProvider);
  Uint8List? _bytes;
  List<Uint8List> _pages = [];
  String? _error, _message;
  bool _loading = true, _outputBusy = false;
  int _loadId = 0;
  bool get _active =>
      mounted && _owner != null && ref.read(activeAccountIdProvider) == _owner;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant PurchasePdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) _load();
  }

  Future<void> _load() async {
    if (!_active) return;
    final id = ++_loadId;
    for (final page in _pages) {
      MemoryImage(page).evict();
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _bytes = null;
      _pages = [];
    });
    try {
      final bytes = await widget.buildDocument();
      if (!_active || id != _loadId) return;
      final pages = await ref.read(requestDocumentRasterProvider)(bytes);
      if (!_active || id != _loadId) return;
      setState(() {
        _bytes = bytes;
        _pages = pages;
      });
    } on PostgrestException catch (e) {
      if (_active && id == _loadId) {
        setState(() => _error = e.message.contains('PDF_MEMBERSHIP_REQUIRED')
            ? t('PDF 미리보기·출력·인쇄는 플러스·비즈니스에서 제공합니다. 기본 미리보기와 텍스트 공유는 계속 사용할 수 있습니다.',
                'PDF preview, export and printing require Plus or Business. Basic preview and text sharing remain available.')
            : t('문서 접근 권한을 확인하지 못했습니다.', 'Could not verify document access.'));
      }
    } catch (_) {
      if (_active && id == _loadId) {
        setState(() => _error = t('문서를 준비하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.',
            'Could not prepare the document. Check your connection and retry.'));
      }
    } finally {
      if (_active && id == _loadId) setState(() => _loading = false);
    }
  }

  Future<void> _output(bool print, BuildContext button) async {
    final bytes = _bytes;
    if (bytes == null || !_active || _loading) return;
    final box = button.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _outputBusy = true;
      _message = null;
    });
    try {
      await ref.read(requestDocumentAccessProvider)();
      if (!_active) return;
      if (print) {
        await ref.read(requestDocumentPrintProvider)(
            bytes, widget.filename, () => _active);
      } else {
        await ref.read(requestDocumentExportProvider)(
            bytes, '${widget.filename}.pdf', 'application/pdf', origin);
      }
      if (_active) {
        setState(() => _message = print
            ? t('인쇄 화면에서 프린터와 인쇄 결과를 확인해 주세요. 요청서 상태는 바뀌지 않습니다.',
                'Check the printer and result in the print dialog. Request status is unchanged.')
            : t('PDF 출력 화면을 열었습니다. 파일을 저장하거나 공유해 주세요.',
                'PDF export opened. Save or share the file.'));
      }
    } catch (_) {
      if (_active) {
        setState(() => _message = t(
            '출력하지 못했습니다. 이용권한과 프린터 연결을 확인하거나 PDF를 저장해 다시 출력해 주세요.',
            'Output unavailable. Check access and printer connectivity, or save the PDF and print it separately.'));
      }
    } finally {
      if (_active) setState(() => _outputBusy = false);
    }
  }

  @override
  void dispose() {
    for (final bytes in _pages) {
      MemoryImage(bytes).evict();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShoppingAccountGuard(
          child: Dialog.fullscreen(
              child: Scaffold(
        appBar: AppBar(
            title: Text(widget.title),
            actions: [
              GuideHelpButton(lesson: 'buy-request', enabled: !_outputBusy)
            ],
            leading: IconButton(
                onPressed: _outputBusy ? null : () => Navigator.pop(context),
                tooltip: t('닫기', 'Close'),
                icon: const Icon(Icons.close))),
        body: Column(children: [
          if (widget.controls != null)
            ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .28),
                child: SingleChildScrollView(
                    child: IgnorePointer(
                        ignoring: _outputBusy, child: widget.controls!))),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: Text(t('다시 시도', 'Retry')))
                ])),
          Expanded(
              child: ListView.builder(
                  itemCount: _pages.length,
                  itemBuilder: (context, i) => Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(children: [
                                LocalizedText('${i + 1} / ${_pages.length}'),
                                const SizedBox(height: 6),
                                InteractiveViewer(
                                    minScale: 1,
                                    maxScale: 4,
                                    child: Image.memory(_pages[i],
                                        semanticLabel:
                                            '${t('문서 페이지', 'Document page')} ${i + 1}')),
                              ])))))),
          if (_message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
        ]),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  Builder(
                      builder: (ctx) => FilledButton.icon(
                          onPressed: _loading || _outputBusy || _bytes == null
                              ? null
                              : () => _output(false, ctx),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(kIsWeb
                              ? t('PDF 다운로드', 'Download PDF')
                              : t('PDF 저장·공유', 'Save / share PDF')))),
                  Builder(
                      builder: (ctx) => OutlinedButton.icon(
                          onPressed: _loading || _outputBusy || _bytes == null
                              ? null
                              : () => _output(true, ctx),
                          icon: const Icon(Icons.print_outlined),
                          label: Text(t('프린터 인쇄', 'Print')))),
                ]))),
      )));
}
