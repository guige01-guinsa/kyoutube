import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:k_youtube/features/recipes/data/local_first_recipe_repository.dart';
import 'package:k_youtube/features/recipes/data/local_recipe_backup_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('export and import roundtrip keeps counts', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      LocalFirstRecipeRepository.subscriberRecipesStorageKey,
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'title': '비빔국수',
          'ingredients': <String>['면', '고추장'],
          'steps': <String>['비빈다'],
        },
      ]),
    );
    await prefs.setStringList(
      LocalFirstRecipeRepository.bookmarksStorageKey,
      <String>['user:user-1'],
    );

    const service = LocalRecipeBackupService();
    final exported = await service.exportAsJsonString();

    SharedPreferences.setMockInitialValues(<String, Object>{});

    final result = await service.importFromJsonString(exported);

    expect(result.recipeCount, 1);
    expect(result.bookmarkCount, 1);
  });

  test('import rejects oversized payload', () async {
    const service = LocalRecipeBackupService();
    final huge = 'a' * (LocalRecipeBackupService.maxImportBytes + 10);

    expect(
      () => service.importFromJsonString(huge),
      throwsA(
        isA<LocalRecipeImportException>().having(
          (e) => e.code,
          'code',
          LocalRecipeImportErrorCode.payloadTooLarge,
        ),
      ),
    );
  });

  test('import rejects missing required recipe fields', () async {
    const service = LocalRecipeBackupService();
    final payload = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'subscriber_recipes': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'title': '',
          'ingredients': <String>['a'],
          'steps': <String>['b'],
        },
      ],
      'bookmarks': <String>['user:user-1'],
    });

    expect(
      () => service.importFromJsonString(payload),
      throwsA(
        isA<LocalRecipeImportException>().having(
          (e) => e.code,
          'code',
          LocalRecipeImportErrorCode.missingRequiredField,
        ),
      ),
    );
  });

  test('import rejects malformed bookmark item', () async {
    const service = LocalRecipeBackupService();
    final payload = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'subscriber_recipes': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'title': '라면',
          'ingredients': <String>['면'],
          'steps': <String>['끓인다'],
        },
      ],
      'bookmarks': <String>['broken-bookmark'],
    });

    expect(
      () => service.importFromJsonString(payload),
      throwsA(
        isA<LocalRecipeImportException>().having(
          (e) => e.code,
          'code',
          LocalRecipeImportErrorCode.invalidBookmarkItem,
        ),
      ),
    );
  });

  test('append mode keeps existing and adds non-duplicate recipes', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      LocalFirstRecipeRepository.subscriberRecipesStorageKey,
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'title': '기존 레시피',
          'ingredients': <String>['a'],
          'steps': <String>['b'],
        },
      ]),
    );
    await prefs.setStringList(
      LocalFirstRecipeRepository.bookmarksStorageKey,
      <String>['user:user-1'],
    );

    const service = LocalRecipeBackupService();
    final payload = jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'subscriber_recipes': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'user-1',
          'title': '중복 레시피',
          'ingredients': <String>['dup'],
          'steps': <String>['dup'],
        },
        <String, dynamic>{
          'id': 'user-2',
          'title': '신규 레시피',
          'ingredients': <String>['x'],
          'steps': <String>['y'],
        },
      ],
      'bookmarks': <String>['user:user-2'],
    });

    final result = await service.importFromJsonString(
      payload,
      mode: LocalRecipeImportMode.append,
    );

    expect(result.mode, LocalRecipeImportMode.append);
    expect(result.importedRecipeCount, 2);
    expect(result.skippedRecipeCount, 1);
    expect(result.recipeCount, 2);
    expect(result.bookmarkCount, 2);

    final rawRecipes =
        prefs.getString(LocalFirstRecipeRepository.subscriberRecipesStorageKey);
    expect(rawRecipes, isNotNull);
    final decoded = jsonDecode(rawRecipes!) as List<dynamic>;
    expect(decoded.length, 2);
  });
}
