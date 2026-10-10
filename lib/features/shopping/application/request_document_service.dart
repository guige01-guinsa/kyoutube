import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/web/document_download.dart';
import '../../../core/web/request_document_output.dart';
import '../data/business_document_store.dart';
import '../domain/supplier_request.dart';
import 'supplier_request_pdf.dart';

typedef DocumentAccess = Future<void> Function();
typedef DocumentRaster = Future<List<Uint8List>> Function(Uint8List bytes);
typedef DocumentPrint = Future<bool> Function(
    Uint8List bytes, String name, bool Function() active);
typedef DocumentExport = Future<void> Function(
    Uint8List bytes, String name, String mime, Rect origin);
final requestDocumentAccessProvider = Provider<DocumentAccess>((_) => () async {
      await Supabase.instance.client.rpc('assert_request_pdf_access');
    });
final requestDocumentRasterProvider =
    Provider<DocumentRaster>((_) => rasterRequestDocument);
final requestDocumentPrintProvider =
    Provider<DocumentPrint>((_) => printRequestDocument);
final requestDocumentExportProvider =
    Provider<DocumentExport>((_) => (bytes, name, mime, origin) async {
          if (kIsWeb) {
            downloadWebDocument(bytes, name, mime);
            return;
          }
          await SharePlus.instance.share(ShareParams(
              files: [XFile.fromData(bytes, mimeType: mime)],
              fileNameOverrides: [name],
              sharePositionOrigin: origin));
        });

typedef RequestDocumentBuild = Future<Uint8List> Function(
    SupplierRequest request,
    {required bool english,
    required bool buyerCopy,
    required bool supplierCopy,
    required bool Function() accountStillActive});
Future<Uint8List> _render(
        (SupplierRequest, ByteData, bool, Uint8List?, Uint8List?) task) =>
    supplierRequestPdf(task.$1, task.$2,
        english: task.$3,
        buyerCertificate: task.$4,
        supplierCertificate: task.$5);
final requestDocumentBuildProvider = Provider<RequestDocumentBuild>((ref) =>
    (request,
        {required english,
        required buyerCopy,
        required supplierCopy,
        required accountStillActive}) async {
      void active() {
        if (!accountStillActive()) throw StateError('Account changed');
      }

      active();
      await ref.read(requestDocumentAccessProvider)();
      active();
      Uint8List? buyer, supplier;
      if (buyerCopy && request.buyerBusiness.imagePath.isNotEmpty) {
        buyer = await ref
            .read(businessDocumentStoreProvider)
            .download(request.buyerBusiness.imagePath);
        active();
      }
      if (supplierCopy && request.supplierBusiness.imagePath.isNotEmpty) {
        supplier = await ref
            .read(businessDocumentStoreProvider)
            .download(request.supplierBusiness.imagePath);
        active();
      }
      final font =
          await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf');
      active();
      final bytes =
          await compute(_render, (request, font, english, buyer, supplier));
      active();
      return bytes;
    });
