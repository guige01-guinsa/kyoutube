import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

Future<List<Uint8List>> rasterRequestDocument(Uint8List bytes) async => [
      await for (final page in Printing.raster(bytes, dpi: 85))
        await page.toPng()
    ];
Future<bool> printRequestDocument(
        Uint8List bytes, String name, bool Function() accountStillActive) =>
    Printing.layoutPdf(
        name: name,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
        onLayout: (_) async {
          if (!accountStillActive()) throw StateError('Account changed');
          return bytes;
        });
