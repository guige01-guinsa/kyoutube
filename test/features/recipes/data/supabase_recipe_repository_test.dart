import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k_youtube/features/recipes/data/supabase_recipe_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  SupabaseRecipeRepository repositoryFor(http.Client client) {
    return SupabaseRecipeRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      httpClient: client,
    );
  }

  test('public recipe request sends the function search contract and maps data',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, contains('recipe_api'));
      expect(request.url.queryParameters['type'], 'public');
      expect(request.url.queryParameters['search'], '감자');
      expect(request.url.queryParameters['search_mode'], 'keyword');
      expect(request.headers['authorization'], startsWith('Bearer'));

      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'status': 'ok',
            'data': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'recipe-1',
                'title': '감자 요리',
                'ingredients': <String>['감자'],
                'steps': <String>['조리'],
              },
              <String, dynamic>{
                'id': 'recipe-2',
                'title': '감자 수프',
                'ingredients': <String>['감자'],
                'steps': <String>['끓이기'],
              },
            ],
          }),
        ),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final recipes = await repositoryFor(client).listPublicRecipes(search: '감자');

    expect(recipes, hasLength(2));
    expect(recipes.first.title, '감자 요리');
  });

  test(
      'public recipe response with non-list data is not hidden as an empty list',
      () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'status': 'ok',
          'data': <String, dynamic>{'unexpected': 'shape'},
        }),
        200,
      ),
    );

    expect(
      repositoryFor(client).listPublicRecipes(),
      throwsA(isA<StateError>()),
    );
  });

  test('public recipe detail uses the Edge Function for an external source id',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, contains('recipe_api/external-source-id'));
      expect(request.url.queryParameters['type'], 'public');
      expect(request.headers['authorization'], startsWith('Bearer'));

      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'status': 'ok',
            'data': <String, dynamic>{
              'id': 'external-source-id',
              'title': '외부 레시피 상세',
              'ingredients': <String>['재료'],
              'steps': <String>['조리'],
            },
          }),
        ),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final recipe =
        await repositoryFor(client).getRecipeById('external-source-id');

    expect(recipe?.id, 'external-source-id');
    expect(recipe?.title, '외부 레시피 상세');
  });

  test('public recipe detail returns null only for a 404 response', () async {
    final client = MockClient((_) async => http.Response('', 404));

    final recipe = await repositoryFor(client).getRecipeById('missing-id');

    expect(recipe, isNull);
  });

  test('public recipe detail surfaces non-404 failures', () async {
    final client = MockClient((_) async => http.Response('', 502));

    expect(
      repositoryFor(client).getRecipeById('external-source-id'),
      throwsA(isA<StateError>()),
    );
  });
}
