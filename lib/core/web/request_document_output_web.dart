import 'dart:typed_data';
import 'dart:js_interop';

@JS('recipeScoutPdfRaster')
external JSPromise<JSArray<JSUint8Array>> _raster(JSUint8Array bytes);
@JS('recipeScoutPdfPrint')
external JSPromise<JSBoolean> _print(JSUint8Array bytes, JSString name);
Future<List<Uint8List>> rasterRequestDocument(Uint8List bytes) async =>
    (await _raster(bytes.toJS).toDart).toDart.map((p) => p.toDart).toList();
Future<bool> printRequestDocument(
    Uint8List bytes, String name, bool Function() accountStillActive) async {
  if (!accountStillActive()) throw StateError('Account changed');
  return (await _print(bytes.toJS, name.toJS).toDart).toDart;
}
