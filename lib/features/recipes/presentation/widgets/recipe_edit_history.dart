import 'package:flutter/material.dart';
import '../../domain/recipe_content_style.dart';
import 'advanced_recipe_text_field.dart';

/// Bounded chronological history across fields, including rich text styles.
class RecipeEditHistory extends ChangeNotifier {
  RecipeEditHistory(this.fields, {this.maxEdits = 100}) : assert(maxEdits > 0) {
    for (final controller in fields.keys) {
      _current[controller] = _TextState.capture(controller);
      void listener() => _changed(controller);
      _listeners[controller] = listener;
      controller.addListener(listener);
    }
  }
  final Map<TextEditingController, FocusNode> fields;
  final int maxEdits;
  final _current = <TextEditingController, _TextState>{};
  final _listeners = <TextEditingController, VoidCallback>{};
  final _undo = <_Edit>[];
  final _redo = <_Edit>[];
  bool _restoring = false;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _changed(TextEditingController controller) {
    if (_restoring) return;
    final before = _current[controller]!;
    final after = _TextState.capture(controller);
    _current[controller] = after;
    if (before.sameContent(after)) return;
    _undo.add(_Edit(controller, before, after));
    if (_undo.length > maxEdits) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    final edit = _undo.removeLast();
    _redo.add(edit);
    _restore(edit.controller, edit.before);
  }

  void redo() {
    if (!canRedo) return;
    final edit = _redo.removeLast();
    _undo.add(edit);
    _restore(edit.controller, edit.after);
  }

  void _restore(TextEditingController controller, _TextState state) {
    _restoring = true;
    try {
      final restored = state.value.copyWith(
        composing: TextRange.empty,
        selection: state.value.selection.isValid
            ? state.value.selection
            : TextSelection.collapsed(offset: state.value.text.length),
      );
      if (controller is RichRecipeTextEditingController) {
        controller.restoreEditingState(restored, state.ranges);
      } else {
        controller.value = restored;
      }
      _current[controller] = _TextState.capture(controller);
      fields[controller]!.requestFocus();
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    _current.clear();
    _undo.clear();
    _redo.clear();
    super.dispose();
  }
}

class _TextState {
  _TextState.capture(TextEditingController controller)
      : value = controller.value,
        ranges = controller is RichRecipeTextEditingController
            ? controller.exportRanges()
            : const [];
  final TextEditingValue value;
  final List<RecipeContentStyleRange> ranges;
  bool sameContent(_TextState other) {
    if (value.text != other.value.text || ranges.length != other.ranges.length) {
      return false;
    }
    for (var i = 0; i < ranges.length; i++) {
      final a = ranges[i], b = other.ranges[i];
      if (a.start != b.start || a.end != b.end || a.style != b.style) {
        return false;
      }
    }
    return true;
  }
}

class _Edit {
  _Edit(this.controller, this.before, this.after);
  final TextEditingController controller;
  final _TextState before, after;
}
