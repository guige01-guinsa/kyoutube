class RecipeSourceReference {
  const RecipeSourceReference({required this.type, required this.id});

  final String type;
  final String id;

  String get value => '$type:$id';

  static RecipeSourceReference parse(String value) {
    final separator = value.indexOf(':');
    if (separator <= 0 || separator == value.length - 1) {
      throw const FormatException('Invalid recipe source reference');
    }
    final type = value.substring(0, separator);
    final id = value.substring(separator + 1);
    if (!{'public', 'creator', 'user'}.contains(type) || id.trim().isEmpty) {
      throw const FormatException('Invalid recipe source reference');
    }
    return RecipeSourceReference(type: type, id: id);
  }
}
