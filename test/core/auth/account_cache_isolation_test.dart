import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';

User user(String id) => User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-13');
Recipe recipe(String title) =>
    Recipe(id: 'recipe', title: title, ingredients: [], steps: []);

class AccountRepository implements RecipeRepository {
  final pending = Completer<Recipe?>();
  String account = 'A';
  int reads = 0;
  @override
  Future<Recipe?> getCreatorRecipeById(String id) {
    reads++;
    return account == 'A' ? pending.future : Future.value(recipe(account));
  }

  @override
  Future<Map<String, int>> getKitchenSummary() async {
    reads++;
    return {'ingredient_count': account == 'A' ? 1 : 2};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('late private response from A cannot replace B after account switch',
      () async {
    final users = StreamController<User?>();
    final repository = AccountRepository();
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((_) => users.stream),
      recipeRepositoryProvider.overrideWithValue(repository)
    ]);
    addTearDown(() => container.dispose());
    addTearDown(() => users.close());
    users.add(user('A'));
    await container.read(authUserProvider.future);
    final provider = creatorRecipeByIdProvider('recipe');
    final listener = container.listen(provider, (_, __) {});
    addTearDown(listener.close);
    await Future<void>.delayed(Duration.zero);
    repository.account = 'B';
    users.add(user('B'));
    await Future<void>.delayed(Duration.zero);
    expect((await container.read(provider.future))!.title, 'B');
    repository.pending.complete(recipe('private A'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).requireValue!.title, 'B');
    expect(repository.reads, 2);
  });
  test('private caches refresh on logout or account change, not token refresh',
      () async {
    final users = StreamController<User?>();
    final repository = AccountRepository();
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((_) => users.stream),
      recipeRepositoryProvider.overrideWithValue(repository)
    ]);
    addTearDown(() => container.dispose());
    addTearDown(() => users.close());
    users.add(user('A'));
    await container.read(authUserProvider.future);
    final listener = container.listen(kitchenSummaryProvider, (_, __) {});
    addTearDown(listener.close);
    expect(
        (await container
            .read(kitchenSummaryProvider.future))['ingredient_count'],
        1);
    users.add(user('A'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.reads, 1);
    repository.account = 'B';
    users.add(user('B'));
    await Future<void>.delayed(Duration.zero);
    expect(
        (await container
            .read(kitchenSummaryProvider.future))['ingredient_count'],
        2);
    expect(repository.reads, 2);
    users.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(kitchenSummaryProvider.future);
    expect(repository.reads, 3);
  });
}
