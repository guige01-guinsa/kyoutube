import 'recipe_identity.dart';

enum RecipeProvenanceType {
  manual,
  youtube,
  copied,
  imported,
  unknown,
}

class RecipeOrigin {
  const RecipeOrigin({
    required this.label,
    this.ownerId,
    this.ownerName,
  });

  final String label;
  final String? ownerId;
  final String? ownerName;
}

class RecipeAccess {
  const RecipeAccess({
    required this.canSave,
    required this.canEdit,
    required this.canDelete,
    required this.canCreatePersonalVersion,
    required this.canShop,
    required this.canCook,
    required this.canShare,
  });

  const RecipeAccess.readOnly()
      : canSave = true,
        canEdit = false,
        canDelete = false,
        canCreatePersonalVersion = true,
        canShop = true,
        canCook = true,
        canShare = true;

  const RecipeAccess.owned()
      : canSave = true,
        canEdit = true,
        canDelete = true,
        canCreatePersonalVersion = false,
        canShop = true,
        canCook = true,
        canShare = true;

  const RecipeAccess.unavailable()
      : canSave = false,
        canEdit = false,
        canDelete = false,
        canCreatePersonalVersion = false,
        canShop = false,
        canCook = false,
        canShare = false;

  final bool canSave;
  final bool canEdit;
  final bool canDelete;
  final bool canCreatePersonalVersion;
  final bool canShop;
  final bool canCook;
  final bool canShare;
}

class RecipeProvenance {
  const RecipeProvenance({
    required this.type,
    this.source,
    this.sourceUrl,
  });

  final RecipeProvenanceType type;
  final RecipeIdentity? source;
  final String? sourceUrl;
}

class UnifiedRecipe {
  const UnifiedRecipe({
    required this.identity,
    required this.title,
    required this.ingredients,
    required this.steps,
    required this.origin,
    required this.access,
    required this.provenance,
    this.summary,
    this.imageUrl,
  });

  final RecipeIdentity identity;
  final String title;
  final String? summary;
  final String? imageUrl;
  final List<String> ingredients;
  final List<String> steps;
  final RecipeOrigin origin;
  final RecipeAccess access;
  final RecipeProvenance provenance;

  String get sourceReference => identity.reference;
}
