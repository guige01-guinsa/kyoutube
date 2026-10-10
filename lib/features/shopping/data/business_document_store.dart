import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/supplier_request.dart';

const businessDocumentsBucket = 'purchase-business-documents';
const businessDocumentMaxBytes = 5 * 1024 * 1024;

/// Decode and re-encode locally to remove metadata and bound image dimensions.
Future<Uint8List> prepareBusinessDocument(Uint8List input) async {
  if (input.isEmpty || input.length > businessDocumentMaxBytes) {
    throw const FormatException('Image must be at most 5 MB');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(input);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 24000000) {
      throw const FormatException('Image dimensions too large');
    }
    final scale = 2048 /
        (descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height);
    codec = await descriptor.instantiateCodec(
        targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
        targetHeight: scale < 1 ? (descriptor.height * scale).round() : null);
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > businessDocumentMaxBytes) {
      throw const FormatException('Use a smaller image');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

abstract class BusinessDocumentStore {
  Future<String> upload(Uint8List png);
  Future<Uint8List> download(String path);
  Future<void> discard(String path);
}

final businessDocumentStoreProvider = Provider<BusinessDocumentStore>(
    (_) => SupabaseBusinessDocumentStore(Supabase.instance.client));

class SupabaseBusinessDocumentStore implements BusinessDocumentStore {
  SupabaseBusinessDocumentStore(this.client);
  final SupabaseClient client;
  String get owner =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  void _owned(String path, String user) {
    if (!RegExp('^${RegExp.escape(user)}/[0-9a-f-]{36}\\.png\$')
        .hasMatch(path)) {
      throw const FormatException('Invalid private document');
    }
  }

  @override
  Future<String> upload(Uint8List png) async {
    final user = owner;
    if (png.length > businessDocumentMaxBytes ||
        png.length < 8 ||
        png[0] != 137 ||
        png[1] != 80 ||
        png[2] != 78 ||
        png[3] != 71) {
      throw const FormatException('PNG required');
    }
    final path = '$user/${newShoppingId()}.png';
    await client.storage.from(businessDocumentsBucket).uploadBinary(path, png,
        fileOptions:
            const FileOptions(contentType: 'image/png', upsert: false));
    if (owner != user) throw StateError('Account changed');
    return path;
  }

  @override
  Future<Uint8List> download(String path) async {
    final user = owner;
    _owned(path, user);
    final bytes =
        await client.storage.from(businessDocumentsBucket).download(path);
    if (owner != user) throw StateError('Account changed');
    if (bytes.length > businessDocumentMaxBytes) {
      throw const FormatException('Image too large');
    }
    return bytes;
  }

  @override
  Future<void> discard(String path) async {
    _owned(path, owner);
    // RLS permits deletion only when no saved request references this image.
    await client.storage.from(businessDocumentsBucket).remove([path]);
  }
}
