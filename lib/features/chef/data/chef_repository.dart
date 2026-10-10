import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/chef_recipe.dart';

class ChefWorkspace {
  const ChefWorkspace(this.document, this.revision);
  final ChefRecipe document;
  final int revision;
}

abstract class ChefRepository {
  Future<ChefWorkspace?> load(String recipeId);
  Future<List<ChefVersion>> versions(String recipeId, {int? beforeVersion});
  Future<int> save(String recipeId, ChefRecipe document, int revision,
      {String? versionLabel, String versionNote = ''});
}

final chefRepositoryProvider = Provider<ChefRepository>(
    (ref) => SupabaseChefRepository(Supabase.instance.client));

class SupabaseChefRepository implements ChefRepository {
  SupabaseChefRepository(this.client);
  final SupabaseClient client;
  @override
  Future<ChefWorkspace?> load(String recipeId) async {
    final rows = await client
        .rpc('get_chef_workspace', params: {'p_recipe_id': recipeId}) as List;
    final row =
        rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
    return row == null
        ? null
        : ChefWorkspace(
            ChefRecipe.fromJson(
                Map<String, dynamic>.from(row['document'] as Map)),
            row['revision'] as int);
  }

  @override
  Future<List<ChefVersion>> versions(String recipeId,
      {int? beforeVersion}) async {
    final result = await client.rpc('get_chef_versions', params: {
      'p_recipe_id': recipeId,
      'p_before': beforeVersion,
    }) as List;
    final rows = result.map((row) => Map<String, dynamic>.from(row as Map));
    return rows.map(ChefVersion.fromJson).toList(growable: false);
  }

  @override
  Future<int> save(String recipeId, ChefRecipe document, int revision,
      {String? versionLabel, String versionNote = ''}) async {
    final result = await client.rpc('save_chef_workspace', params: {
      'p_recipe_id': recipeId,
      'p_document': document.toJson(),
      'p_expected_revision': revision,
      'p_version_label': versionLabel,
      'p_version_note': versionNote,
    });
    return (result as num).toInt();
  }
}
