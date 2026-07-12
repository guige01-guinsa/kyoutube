import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class RecipeImageService {
  RecipeImageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _bucketName = 'creator-recipe-images';

  String? _extractPathFromPublicUrl(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      return null;
    }

    final segments = uri.pathSegments;
    final publicIndex = segments.indexOf('public');
    if (publicIndex == -1 || publicIndex + 2 >= segments.length) {
      return null;
    }

    final bucket = segments[publicIndex + 1];
    if (bucket != _bucketName) {
      return null;
    }

    final filePathSegments = segments.sublist(publicIndex + 2);
    if (filePathSegments.isEmpty) {
      return null;
    }

    return filePathSegments.join('/');
  }

  Future<String> uploadCreatorRecipeImage({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final safeExt = fileExtension.trim().toLowerCase();
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final filePath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(_bucketName).uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    return _client.storage.from(_bucketName).getPublicUrl(filePath);
  }

  Future<void> deleteCreatorRecipeImageByUrl(String imageUrl) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    final filePath = _extractPathFromPublicUrl(imageUrl);
    if (filePath == null || !filePath.startsWith('$userId/')) {
      return;
    }

    await _client.storage.from(_bucketName).remove(<String>[filePath]);
  }
}
