enum ChefSalesPeriod { day, week, month }

String chefDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ChefSalesRange {
  const ChefSalesRange(this.from, this.until);
  final DateTime from, until;
  factory ChefSalesRange.forDate(DateTime date, ChefSalesPeriod period) {
    final day = DateTime(date.year, date.month, date.day);
    switch (period) {
      case ChefSalesPeriod.day:
        return ChefSalesRange(day, DateTime(day.year, day.month, day.day + 1));
      case ChefSalesPeriod.week:
        final monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
        return ChefSalesRange(
            monday, DateTime(monday.year, monday.month, monday.day + 7));
      case ChefSalesPeriod.month:
        return ChefSalesRange(
            DateTime(day.year, day.month), DateTime(day.year, day.month + 1));
    }
  }
}

class ChefSale {
  const ChefSale(
      {required this.id,
      required this.date,
      required this.title,
      required this.quantity,
      required this.unitPrice,
      required this.unitCost,
      this.revision = 1,
      this.voided = false,
      required this.currency});
  final int revision;
  final bool voided;
  final int id, quantity;
  final DateTime date;
  final String title, currency;
  final double unitPrice, unitCost;
  double get revenue => quantity * unitPrice;
  double get profit => revenue - quantity * unitCost;
  factory ChefSale.fromJson(Map<String, dynamic> row) => ChefSale(
      id: row['id'] as int,
      revision: (row['revision'] as num? ?? 1).toInt(),
      voided: row['voided'] == true,
      date: DateTime.parse(row['sale_date'] as String),
      title: row['recipe_title'] as String,
      quantity: row['quantity'] as int,
      unitPrice: (row['unit_price'] as num).toDouble(),
      unitCost: (row['unit_cost'] as num).toDouble(),
      currency: row['currency'] as String);
}

class ChefSalesTotals {
  const ChefSalesTotals(
      {required this.quantity, required this.revenue, required this.cost});
  final int quantity;
  final double revenue, cost;
  double get profit => revenue - cost;
  factory ChefSalesTotals.fromJson(Map<String, dynamic> row) => ChefSalesTotals(
      quantity: (row['quantity'] as num).toInt(),
      revenue: (row['revenue'] as num).toDouble(),
      cost: (row['cost'] as num).toDouble());
}
