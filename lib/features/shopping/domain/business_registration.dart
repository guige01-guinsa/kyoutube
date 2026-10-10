/// A private attachment to a purchase request, not public supplier verification.
class BusinessRegistration {
  const BusinessRegistration({this.number = '', this.imagePath = ''});
  final String number, imagePath;
  bool get isEmpty => number.isEmpty && imagePath.isEmpty;
  bool get valid =>
      (number.isEmpty && imagePath.isEmpty) ||
      RegExp(r'^\d{10}$').hasMatch(number.replaceAll('-', '').trim());
  String get formattedNumber {
    final digits = number.replaceAll('-', '').trim();
    return RegExp(r'^\d{10}$').hasMatch(digits)
        ? '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}'
        : number.trim();
  }

  Map<String, dynamic> toJson() =>
      {'number': formattedNumber, 'image_path': imagePath};
  factory BusinessRegistration.fromJson(dynamic data) {
    if (data is! Map) return const BusinessRegistration();
    return BusinessRegistration(
        number: data['number'] as String? ?? '',
        imagePath: data['image_path'] as String? ?? '');
  }
}
