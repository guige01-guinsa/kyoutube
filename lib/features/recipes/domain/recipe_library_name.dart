/// Display names never fall back to an email address or an account identifier.
String? recipeOwnerName(Map<String, dynamic>? metadata) {
  for (final key in ['display_name', 'full_name', 'name', 'nickname']) {
    final value = metadata?[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String recipeLibraryName(
    {String? owner, bool business = false, bool english = false}) {
  final name = owner?.trim() ?? '';
  if (name.isEmpty) {
    return english
        ? (business ? 'Business recipes' : 'Personal recipes')
        : (business ? '업소 레시피' : '개인 레시피');
  }
  return english ? '$name’s recipes' : '$name${business ? '' : '님'} 레시피';
}
