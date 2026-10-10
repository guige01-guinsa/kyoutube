import 'package:flutter/material.dart';

import '../../../../core/localization/localized_text.dart';
import '../../domain/recipe_content_style.dart';

class RichRecipeTextEditingController extends TextEditingController {
  RichRecipeTextEditingController({
    super.text,
    List<RecipeContentStyleRange> ranges = const <RecipeContentStyleRange>[],
  }) {
    final currentText = text;
    _lastText = currentText;
    _styles = List<RecipeContentStyle?>.filled(currentText.length, null);
    for (final range in ranges) {
      final start = range.start.clamp(0, currentText.length);
      final end = range.end.clamp(0, currentText.length);
      for (var index = start; index < end; index++) {
        _styles[index] = range.style.isDefault ? null : range.style;
      }
    }
    addListener(_syncStylesWithText);
  }

  late String _lastText;
  late List<RecipeContentStyle?> _styles;
  bool _notifyingStyleChange = false;

  bool get hasSelectedText =>
      selection.isValid &&
      !selection.isCollapsed &&
      selection.end <= text.length;

  bool get selectionIsBold {
    if (!hasSelectedText) return false;
    for (var index = selection.start; index < selection.end; index++) {
      if (!(_styles[index]?.bold ?? false)) return false;
    }
    return true;
  }

  void _syncStylesWithText() {
    if (_notifyingStyleChange || text == _lastText) return;
    final oldText = _lastText;
    final oldStyles = _styles;
    final newText = text;

    var prefix = 0;
    final prefixLimit =
        oldText.length < newText.length ? oldText.length : newText.length;
    while (prefix < prefixLimit && oldText[prefix] == newText[prefix]) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix += 1;
    }

    final insertedLength = newText.length - prefix - suffix;
    RecipeContentStyle? inherited;
    if (prefix > 0 && prefix - 1 < oldStyles.length) {
      inherited = oldStyles[prefix - 1];
    } else if (prefix < oldStyles.length) {
      inherited = oldStyles[prefix];
    }
    _styles = <RecipeContentStyle?>[
      ...oldStyles.take(prefix),
      ...List<RecipeContentStyle?>.filled(insertedLength, inherited),
      ...oldStyles.skip(oldText.length - suffix),
    ];
    _lastText = newText;
  }

  bool applyToSelection(
    RecipeContentStyle Function(RecipeContentStyle current) transform,
  ) {
    if (!hasSelectedText) return false;
    for (var index = selection.start; index < selection.end; index++) {
      final next = transform(_styles[index] ?? const RecipeContentStyle());
      _styles[index] = next.isDefault ? null : next;
    }
    _notifyingStyleChange = true;
    notifyListeners();
    _notifyingStyleChange = false;
    return true;
  }

  List<RecipeContentStyleRange> exportRanges() {
    final ranges = <RecipeContentStyleRange>[];
    var start = 0;
    while (start < _styles.length) {
      final style = _styles[start];
      if (style == null || style.isDefault) {
        start += 1;
        continue;
      }
      var end = start + 1;
      while (end < _styles.length && _styles[end] == style) {
        end += 1;
      }
      ranges.add(RecipeContentStyleRange(
        start: start,
        end: end,
        style: style,
      ));
      start = end;
    }
    return ranges;
  }

  List<RecipeContentStyleRange> exportSlice(
    int start,
    int end, {
    int outputOffset = 0,
  }) {
    return styleRangesForSlice(
      exportRanges(),
      start,
      end,
      outputOffset: outputOffset,
    );
  }

  /// Restore formatting and text together without normal edit inheritance.
  void restoreEditingState(
      TextEditingValue restored, List<RecipeContentStyleRange> ranges) {
    _notifyingStyleChange = true;
    try {
      _lastText = restored.text;
      _styles = List<RecipeContentStyle?>.filled(restored.text.length, null);
      for (final range in ranges) {
        for (var i = range.start.clamp(0, restored.text.length);
            i < range.end.clamp(0, restored.text.length);
            i++) {
          _styles[i] = range.style.isDefault ? null : range.style;
        }
      }
      value = restored;
      notifyListeners();
    } finally {
      _notifyingStyleChange = false;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return buildRecipeStyledTextSpan(
      context: context,
      text: text,
      ranges: exportRanges(),
      baseStyle: style,
    );
  }

  @override
  void dispose() {
    removeListener(_syncStylesWithText);
    super.dispose();
  }
}

class AdvancedRecipeTextField extends StatelessWidget {
  const AdvancedRecipeTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    this.helperText,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
  });

  final RichRecipeTextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String? helperText;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      contextMenuBuilder: (context, editableTextState) {
        return _RecipeSelectionContextMenu(
          anchors: editableTextState.contextMenuAnchors,
          defaultItems: editableTextState.contextMenuButtonItems,
          controller: controller,
          editableTextState: editableTextState,
        );
      },
      decoration: InputDecoration(
        labelText: context.tr(label),
        helperText: helperText == null ? null : context.tr(helperText!),
      ),
      style: Theme.of(context).textTheme.bodyLarge,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      validator: validator,
    );
  }
}

enum _RecipeContextMenuMode { standard, formatting, size, color }

class _RecipeSelectionContextMenu extends StatefulWidget {
  const _RecipeSelectionContextMenu({
    required this.anchors,
    required this.defaultItems,
    required this.controller,
    required this.editableTextState,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> defaultItems;
  final RichRecipeTextEditingController controller;
  final EditableTextState editableTextState;

  @override
  State<_RecipeSelectionContextMenu> createState() =>
      _RecipeSelectionContextMenuState();
}

class _RecipeSelectionContextMenuState
    extends State<_RecipeSelectionContextMenu> {
  _RecipeContextMenuMode _mode = _RecipeContextMenuMode.standard;

  void _apply(
    RecipeContentStyle Function(RecipeContentStyle current) transform,
  ) {
    widget.controller.applyToSelection(transform);
    widget.editableTextState.hideToolbar(false);
  }

  ContextMenuButtonItem _button(String label, VoidCallback onPressed) {
    return ContextMenuButtonItem(
      label: context.tr(label),
      onPressed: onPressed,
    );
  }

  List<ContextMenuButtonItem> _formattingItems() {
    switch (_mode) {
      case _RecipeContextMenuMode.standard:
        if (!widget.controller.hasSelectedText) return widget.defaultItems;
        return <ContextMenuButtonItem>[
          _button(
            '서식',
            () => setState(() => _mode = _RecipeContextMenuMode.formatting),
          ),
          ...widget.defaultItems,
        ];
      case _RecipeContextMenuMode.formatting:
        return <ContextMenuButtonItem>[
          _button('뒤로',
              () => setState(() => _mode = _RecipeContextMenuMode.standard)),
          _button(
            '글자 크기',
            () => setState(() => _mode = _RecipeContextMenuMode.size),
          ),
          _button(
            '굵게',
            () {
              final makeBold = !widget.controller.selectionIsBold;
              _apply((style) => style.copyWith(bold: makeBold));
            },
          ),
          _button(
            '글자색',
            () => setState(() => _mode = _RecipeContextMenuMode.color),
          ),
        ];
      case _RecipeContextMenuMode.size:
        return <ContextMenuButtonItem>[
          _button('뒤로',
              () => setState(() => _mode = _RecipeContextMenuMode.formatting)),
          _button('작게', () => _apply((style) => style.copyWith(size: 'small'))),
          _button(
              '일반', () => _apply((style) => style.copyWith(size: 'normal'))),
          _button('크게', () => _apply((style) => style.copyWith(size: 'large'))),
        ];
      case _RecipeContextMenuMode.color:
        return <ContextMenuButtonItem>[
          _button('뒤로',
              () => setState(() => _mode = _RecipeContextMenuMode.formatting)),
          _button(
              '기본색', () => _apply((style) => style.copyWith(color: 'default'))),
          _button(
              '초록색', () => _apply((style) => style.copyWith(color: 'forest'))),
          _button(
              '파란색', () => _apply((style) => style.copyWith(color: 'blue'))),
          _button(
              '산호색', () => _apply((style) => style.copyWith(color: 'coral'))),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: widget.anchors,
      buttonItems: _formattingItems(),
    );
  }
}
