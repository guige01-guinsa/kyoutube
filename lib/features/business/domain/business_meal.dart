import 'business_menu.dart';

DateTime mealDay(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime mealWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);
String mealDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class BusinessMeal {
  BusinessMeal(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get title => json['title'] as String;
  String get slot => json['slot'] as String;
  String get notes => json['notes'] as String;
  String get status => json['status'] as String;
  int get revision => (json['revision'] as num).toInt();
  DateTime get date => DateTime.parse(json['meal_date'] as String);
  List<Map<String, dynamic>> get sources =>
      List<Map<String, dynamic>>.from(json['sources'] as List);
  List<Map<String, dynamic>> get dishes =>
      List<Map<String, dynamic>>.from(json['snapshot']['sources'] as List);
  List<Map<String, dynamic>> get requirements =>
      List<Map<String, dynamic>>.from(json['snapshot']['requirements'] as List);
  Map<String, dynamic> get purchaseSource =>
      {'kind': 'meal', 'id': id, 'revision': revision, 'servings': 1};
  String get dishSummary => dishes
      .map((s) => '${s['title']} · ${menuNumber(s['servings'] as num)}')
      .join(' / ');
}
