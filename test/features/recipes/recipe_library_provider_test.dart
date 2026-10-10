import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/recipes/application/recipe_library_provider.dart';

void main() {
  test('library name follows profile changes and never leaks across accounts',
      () async {
    final account = StateProvider<String?>((ref) => 'one');
    User profile(String id, String name) => User(
        id: id,
        appMetadata: {},
        userMetadata: {'display_name': name},
        aud: 'authenticated',
        createdAt: '2026-09-23');
    final user = StateProvider<User?>((ref) => profile('one', '첫사용자'));
    final container = ProviderContainer(overrides: [
      activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
      authUserProvider.overrideWith((ref) => Stream.value(ref.watch(user))),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(recipeOwnerNameProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(authUserProvider.future);
    expect(container.read(recipeOwnerNameProvider), '첫사용자');
    container.read(user.notifier).state = profile('one', '수정이름');
    await container.read(authUserProvider.future);
    expect(container.read(recipeOwnerNameProvider), '수정이름');
    container.read(account.notifier).state = 'two';
    expect(container.read(recipeOwnerNameProvider), isNull);
    container.read(user.notifier).state = profile('two', '다음사용자');
    await container.read(authUserProvider.future);
    expect(container.read(recipeOwnerNameProvider), '다음사용자');
    container.read(account.notifier).state = null;
    expect(container.read(recipeOwnerNameProvider), isNull);
  });
}
