import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/recipes/data/supabase_recipe_repository.dart';

void main() {
  test('new notebook saves and edits never implicitly publish a recipe',
      () async {
    final supabase = SupabaseClient('https://unit.invalid', 'unit-anon');
    addTearDown(supabase.dispose);
    await supabase.auth.setInitialSession(jsonEncode({
      'access_token': 'unit-access-token',
      'refresh_token': 'unit-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': '11111111-1111-4111-8111-111111111111',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-09-13T00:00:00Z'
      }
    }));
    final methods = <String>[];
    final httpClient = MockClient((request) async {
      methods.add(request.method);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['is_published'], false);
      return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {
              'id': 'private-recipe',
              'title': 'Private',
              'ingredients': ['Rice'],
              'steps': ['Cook']
            }
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    addTearDown(httpClient.close);
    final repository =
        SupabaseRecipeRepository(client: supabase, httpClient: httpClient);
    await repository.createCreatorRecipe(
        title: 'Private', ingredients: ['Rice'], steps: ['Cook']);
    await repository.updateCreatorRecipe(
        id: 'private-recipe',
        title: 'Private',
        ingredients: ['Rice'],
        steps: ['Cook']);
    expect(methods, ['POST', 'PATCH']);
  });
}
