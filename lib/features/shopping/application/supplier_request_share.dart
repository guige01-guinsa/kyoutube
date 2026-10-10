import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/supplier_request.dart';
import 'supplier_request_pdf.dart';
import '../../../core/web/document_download.dart';

Future<Uint8List> _renderPdf((SupplierRequest, ByteData, bool) task) =>
    supplierRequestPdf(task.$1, task.$2, english: task.$3);

typedef SupplierRequestShare = Future<void> Function(SupplierRequest request,
    {required bool english,
    required bool pdf,
    required Rect origin,
    required bool Function() accountStillActive});

final supplierRequestShareProvider = Provider<SupplierRequestShare>((_) =>
    (request,
        {required english,
        required pdf,
        required origin,
        required accountStillActive}) async {
      // A share sheet result reports choosing a target, not supplier acceptance.
      // It must never advance request status or shopping/inventory state.
      ShareParams params;
      if (pdf) {
        if (!accountStillActive()) throw StateError('Account changed');
        await Supabase.instance.client.rpc('assert_request_pdf_access');
        final font =
            await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf');
        final bytes = await compute(_renderPdf, (request, font, english));
        if (!accountStillActive()) throw StateError('Account changed');
        if (kIsWeb) {
          downloadWebDocument(
              bytes, '${request.reference}.pdf', 'application/pdf');
          return;
        }
        params = ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
            fileNameOverrides: ['${request.reference}.pdf'],
            sharePositionOrigin: origin);
      } else {
        if (kIsWeb) {
          if (!accountStillActive()) throw StateError('Account changed');
          await Clipboard.setData(ClipboardData(
              text: supplierRequestText(request, english: english)));
          return;
        }
        params = ShareParams(
            text: supplierRequestText(request, english: english),
            sharePositionOrigin: origin);
      }
      if (!accountStillActive()) throw StateError('Account changed');
      await SharePlus.instance.share(params);
    });
