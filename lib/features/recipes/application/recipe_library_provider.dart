import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/recipe_library_name.dart';

final recipeOwnerNameProvider = Provider<String?>((ref) {
  final account = ref.watch(activeAccountIdProvider);
  if (account == null) return null;
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user?.id != account) return null;
  return recipeOwnerName(user?.userMetadata);
});
