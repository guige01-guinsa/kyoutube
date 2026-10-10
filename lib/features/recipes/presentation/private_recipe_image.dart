import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env.dart';
import '../../auth/application/auth_providers.dart';

class PrivateRecipeImage extends ConsumerWidget {
  const PrivateRecipeImage(this.url,
      {super.key,
      this.fit,
      this.cacheWidth,
      this.cacheHeight,
      this.errorBuilder});
  final String url;
  final BoxFit? fit;
  final int? cacheWidth, cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeAccountIdProvider);
    final original = Uri.tryParse(url), origin = Uri.tryParse(Env.supabaseUrl);
    var target = url;
    Map<String, String>? headers;
    const prefix = '/storage/v1/object/public/creator-recipe-images/';
    if (original != null &&
        (original.scheme == 'https' || original.scheme == 'http') &&
        origin != null &&
        original.origin == origin.origin &&
        (original.path.startsWith(prefix) ||
            original.path.startsWith(
                '/storage/v1/object/sign/creator-recipe-images/'))) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) {
        return errorBuilder?.call(
                context, StateError('Sign in required'), null) ??
            const SizedBox.shrink();
      }
      target = original
          .replace(
              path: original.path
                  .replaceFirst('/object/public/', '/object/authenticated/')
                  .replaceFirst('/object/sign/', '/object/authenticated/'),
              query: '')
          .toString();
      headers = {'Authorization': 'Bearer $token'};
    }
    return Image.network(target,
        headers: headers,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: errorBuilder);
  }
}
