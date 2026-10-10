import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe_content_style.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/advanced_recipe_text_field.dart';

void main() {
  test('formatting applies only to the selected text', () {
    final controller = RichRecipeTextEditingController(text: '김치찌개');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);

    final applied = controller.applyToSelection(
      (style) => style.copyWith(bold: true, color: 'blue'),
    );

    expect(applied, isTrue);
    expect(controller.exportRanges(), hasLength(1));
    expect(controller.exportRanges().single.start, 0);
    expect(controller.exportRanges().single.end, 2);
    expect(controller.exportRanges().single.style.bold, isTrue);
    expect(controller.exportRanges().single.style.color, 'blue');
  });

  test('selection formatting survives edits and compact JSON round trip', () {
    final controller = RichRecipeTextEditingController(text: '맛있는 국수');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 6);
    controller.applyToSelection((style) => style.copyWith(size: 'large'));

    controller.value = const TextEditingValue(
      text: '아주 맛있는 국수',
      selection: TextSelection.collapsed(offset: 2),
    );
    final encoded = encodeRecipeContentStyles(
      <String, List<RecipeContentStyleRange>>{
        'title': controller.exportRanges(),
      },
    );
    final decoded = decodeRecipeContentStyles(encoded);

    expect(decoded['title'], hasLength(1));
    expect(decoded['title']!.single.start, 7);
    expect(decoded['title']!.single.end, 9);
    expect(decoded['title']!.single.style.size, 'large');
  });

  testWidgets('selection menu opens the recipe formatting controls',
      (tester) async {
    final controller = RichRecipeTextEditingController(text: '김치찌개');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: AdvancedRecipeTextField(
              controller: controller,
              focusNode: focusNode,
              label: '제목',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));

    expect(editable.showToolbar(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('서식'), findsOneWidget);

    await tester.tap(find.text('서식'));
    await tester.pumpAndSettle();
    expect(find.text('글자 크기'), findsOneWidget);
    expect(find.text('굵게'), findsOneWidget);
    expect(find.text('글자색'), findsOneWidget);

    await tester.tap(find.text('글자 크기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('크게'));
    await tester.pumpAndSettle();

    expect(controller.exportRanges(), hasLength(1));
    expect(controller.exportRanges().single.start, 0);
    expect(controller.exportRanges().single.end, 2);
    expect(controller.exportRanges().single.style.size, 'large');
  });
}
