import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/web/document_download.dart';
import '../../../core/web/request_document_output.dart';
import '../../shopping/application/supplier_request_pdf.dart';
import '../application/guide_sample_store.dart';

/// Only reads local practice records. No membership or business-document access.
class GuideSamplePdfPage extends StatefulWidget {
  const GuideSamplePdfPage({super.key, required this.requestId});
  final String requestId;
  @override
  State<GuideSamplePdfPage> createState() => _GuideSamplePdfPageState();
}

class _GuideSamplePdfPageState extends State<GuideSamplePdfPage> {
  Uint8List? _bytes;
  List<Uint8List> _pages = [];
  String? _error, _message;
  bool _started = false, _busy = false;
  bool get en => AppLocalizations.of(context).isEnglish;
  String t(String ko, String english) => AppLocalizations.of(context).bilingual(ko, english);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final data = await GuideSampleStore(en).load();
      final request =
          data.requests.where((r) => r.id == widget.requestId).firstOrNull;
      if (request == null || !request.id.startsWith('sample-')) {
        throw StateError('Sample unavailable');
      }
      final font =
          await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf');
      final bytes =
          await supplierRequestPdf(request, font, english: en, practice: true);
      if (!mounted) return;
      setState(() => _bytes = bytes);
      try {
        final pages = await rasterRequestDocument(bytes);
        if (mounted) setState(() => _pages = pages);
      } catch (_) {
        if (mounted) {
          setState(() => _message = t(
              '미리보기 이미지를 표시하지 못했어요. PDF를 저장해서 확인할 수 있습니다.',
              'Preview images are unavailable. Save the PDF to view it.'));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('샘플 PDF를 만들지 못했습니다. 요청서를 저장하고 다시 시도해 주세요.',
            'Could not create the sample PDF. Save the request and retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _output(bool print, BuildContext button) async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final name = 'PRACTICE-${widget.requestId}.pdf';
      if (print) {
        await printRequestDocument(bytes, name, () => mounted);
      } else if (kIsWeb) {
        downloadWebDocument(bytes, name, 'application/pdf');
      } else {
        final box = button.findRenderObject() as RenderBox;
        await SharePlus.instance.share(ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
            fileNameOverrides: [name],
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size));
      }
      if (mounted) {
        setState(() => _message = t(
            '출력 화면에서 완료 여부를 확인하세요. 연습 요청서 상태는 바뀌지 않습니다.',
            'Check completion in the output dialog. Practice request status is unchanged.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('출력하지 못했습니다. PDF를 저장하거나 다시 시도해 주세요.',
            'Could not output the PDF. Save it or try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(t('샘플 PDF 미리보기', 'Sample PDF preview')),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: t('돌아가기', 'Back'),
              onPressed: () => context.pop())),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(t('연습용 문서입니다. 모든 페이지에 연습 표시가 포함됩니다.',
                                'Practice document. Every page is labelled as a sample.')),
                            const SizedBox(height: 16),
                            Builder(
                                builder: (button) => Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          FilledButton.icon(
                                              onPressed: _bytes == null || _busy
                                                  ? null
                                                  : () =>
                                                      _output(false, button),
                                              icon: const Icon(
                                                  Icons.download_outlined),
                                              label: Text(t('샘플 PDF 저장/공유',
                                                  'Save/share sample PDF'))),
                                          OutlinedButton.icon(
                                              onPressed: _bytes == null || _busy
                                                  ? null
                                                  : () => _output(true, button),
                                              icon: const Icon(
                                                  Icons.print_outlined),
                                              label: Text(t('인쇄', 'Print')))
                                        ])),
                            if (_busy) const LinearProgressIndicator(),
                            if (_error != null) ...[
                              Text(_error!),
                              TextButton(
                                  onPressed: _load,
                                  child: Text(t('다시 시도', 'Retry')))
                            ],
                            if (_message != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  child: Text(_message!)),
                            for (final page in _pages)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Image.memory(page,
                                      semanticLabel: t('연습용 구매요청서 페이지',
                                          'Practice purchase request page'))),
                          ]))))));
}
