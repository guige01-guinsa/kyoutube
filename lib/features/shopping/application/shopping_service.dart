class ShoppingService {
  List<String> buildChecklist(List<String> ingredients) {
    return ingredients
        .where((String item) => item.trim().isNotEmpty)
        .map((String item) => '- [ ] $item')
        .toList();
  }
}
