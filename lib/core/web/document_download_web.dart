import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void downloadWebDocument(Uint8List bytes, String name, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.appendChild(link);
  link.click();
  link.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
