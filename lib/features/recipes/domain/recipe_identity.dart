class RecipeIdentity {
  const RecipeIdentity({
    required this.sourceType,
    required this.sourceId,
  });

  final String sourceType;
  final String sourceId;

  static const Set<String> supportedSourceTypes = <String>{
    'public',
    'creator',
    'user',
  };

  String get reference => '$sourceType:$sourceId';

  bool get isPublic => sourceType == 'public';
  bool get isCreator => sourceType == 'creator';
  bool get isUser => sourceType == 'user';

  static RecipeIdentity parse(String value) {
    final trimmed = value.trim();
    final separator = trimmed.indexOf(':');

    if (separator <= 0 || separator == trimmed.length - 1) {
      throw const FormatException('Recipe reference must be typed.');
    }

    final sourceType = trimmed.substring(0, separator).trim().toLowerCase();
    final sourceId = trimmed.substring(separator + 1).trim();

    if (!supportedSourceTypes.contains(sourceType)) {
      throw FormatException('Unsupported recipe source type: $sourceType');
    }
    if (sourceId.isEmpty) {
      throw const FormatException('Recipe source id is required.');
    }

    return RecipeIdentity(sourceType: sourceType, sourceId: sourceId);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecipeIdentity &&
            other.sourceType == sourceType &&
            other.sourceId == sourceId;
  }

  @override
  int get hashCode => Object.hash(sourceType, sourceId);

  @override
  String toString() => reference;
}
