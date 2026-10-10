import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/advanced_recipe_text_field.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/recipe_edit_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('undo and redo restore text, selection and selected formatting', () {
    final c = RichRecipeTextEditingController(text: 'Carrots');
    final focus = FocusNode();
    final history = RecipeEditHistory({c: focus});
    addTearDown(() {
      history.dispose();
      c.dispose();
      focus.dispose();
    });
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    expect(history.canUndo, false);
    c.applyToSelection((s) => s.copyWith(bold: true, color: 'blue'));
    c.value = const TextEditingValue(
        text: 'Roast carrots', selection: TextSelection.collapsed(offset: 5));
    history.undo();
    expect(c.text, 'Carrots');
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
    expect(c.exportRanges().single.style.bold, true);
    history.undo();
    expect(c.exportRanges(), isEmpty);
    expect(history.canUndo, false);
    history.redo();
    expect(c.exportRanges().single.style.color, 'blue');
    history.redo();
    expect(c.text, 'Roast carrots');
    expect(c.selection.baseOffset, 5);
    expect(history.canRedo, false);
  });
  test('history spans fields and clears redo on a new edit', () {
    final a = RichRecipeTextEditingController(text: 'Title'),
        b = TextEditingController(text: 'Link');
    final fa = FocusNode(), fb = FocusNode();
    final history = RecipeEditHistory({a: fa, b: fb});
    addTearDown(() {
      history.dispose();
      a.dispose();
      b.dispose();
      fa.dispose();
      fb.dispose();
    });
    a.text = 'Soup';
    b.text = 'Video';
    history.undo();
    expect(b.text, 'Link');
    expect(a.text, 'Soup');
    history.undo();
    expect(a.text, 'Title');
    history.redo();
    expect(a.text, 'Soup');
    b.text = 'New link';
    expect(history.canRedo, false);
  });
  test(
      'history is bounded and restores committed Korean text without stale IME state',
      () {
    final c = RichRecipeTextEditingController(text: '당근');
    final f = FocusNode();
    final history = RecipeEditHistory({c: f}, maxEdits: 2);
    addTearDown(() {
      history.dispose();
      c.dispose();
      f.dispose();
    });
    c.value = const TextEditingValue(
        text: '당근국',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 2, end: 3));
    c.text = '당근국수';
    c.text = '당근국수 완성';
    history.undo();
    history.undo();
    history.undo();
    expect(c.text, '당근국');
    expect(c.value.composing, TextRange.empty);
    expect(history.canUndo, false);
  });
}
