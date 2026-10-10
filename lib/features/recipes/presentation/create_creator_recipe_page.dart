import '../../workspace/application/workspace_navigation.dart';
import 'private_recipe_image.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/scout_page.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import '../domain/recipe_content_style.dart';
import 'widgets/advanced_recipe_text_field.dart';
import 'widgets/recipe_edit_history.dart';

class CreateCreatorRecipePage extends ConsumerStatefulWidget {
  const CreateCreatorRecipePage({
    super.key,
    this.initialRecipe,
    this.editRecipeId,
    this.returnCreatedRecipeId = false,
  });

  final Recipe? initialRecipe;

  /// 기존 creator 레시피 수정 시에만 전달됩니다.
  /// null이면 initialRecipe가 있어도 새 레시피 생성 모드입니다.
  final String? editRecipeId;

  /// true이면 새 레시피 저장 후 bool 대신 생성된 Recipe ID를 반환합니다.
  final bool returnCreatedRecipeId;

  @override
  ConsumerState<CreateCreatorRecipePage> createState() =>
      _CreateCreatorRecipePageState();
}

class _CreateCreatorRecipePageState
    extends ConsumerState<CreateCreatorRecipePage> {
  static const int _maxTitleLength = 120;
  static const int _maxSummaryLength = 240;
  static const int _maxTipsLength = 500;
  static const int _maxYoutubeUrlLength = 200;

  final _formKey = GlobalKey<FormState>();
  late final RichRecipeTextEditingController _titleController;
  late final RichRecipeTextEditingController _summaryController;
  late final RichRecipeTextEditingController _ingredientsController;
  late final RichRecipeTextEditingController _stepsController;
  late final RichRecipeTextEditingController _tipsController;
  final _youtubeUrlController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _summaryFocusNode = FocusNode();
  final _ingredientsFocusNode = FocusNode();
  final _stepsFocusNode = FocusNode();
  final _tipsFocusNode = FocusNode();
  final _youtubeUrlFocusNode = FocusNode();
  late final RecipeEditHistory _editHistory;
  final _imagePicker = ImagePicker();

  bool _isSubmitting = false;
  bool _saved = false;
  bool _showValidationErrors = false;
  String? _errorMessage;
  Uint8List? _selectedImageBytes;
  String _selectedImageExtension = 'jpg';

  bool get _isEditMode => widget.editRecipeId != null;
  bool get _isAiDraft =>
      widget.initialRecipe?.sourceType == 'ai_enrichment_draft';

  bool get _hasAiConfirmationItems {
    final recipe = widget.initialRecipe;
    if (recipe == null) return false;
    return <String>[
      recipe.summary ?? '',
      recipe.tips ?? '',
      ...recipe.ingredients,
      ...recipe.steps,
    ].any((value) => value.contains('확인 필요'));
  }

  @override
  void initState() {
    super.initState();
    final recipe = widget.initialRecipe;
    final title = recipe?.title ?? '';
    final summary = recipe?.summary ?? '';
    final ingredients = recipe?.ingredients.join('\n') ?? '';
    final steps = recipe?.steps.join('\n') ?? '';
    final tips = recipe?.tips ?? '';
    final contentStyles = decodeRecipeContentStyles(
      recipe?.contentStyles,
      legacyFieldLengths: <String, int>{
        'title': title.length,
        'summary': summary.length,
        'ingredients': ingredients.length,
        'steps': steps.length,
        'tips': tips.length,
      },
    );
    _titleController = RichRecipeTextEditingController(
      text: title,
      ranges: contentStyles['title'] ?? const <RecipeContentStyleRange>[],
    );
    _summaryController = RichRecipeTextEditingController(
      text: summary,
      ranges: contentStyles['summary'] ?? const <RecipeContentStyleRange>[],
    );
    _ingredientsController = RichRecipeTextEditingController(
      text: ingredients,
      ranges: contentStyles['ingredients'] ?? const <RecipeContentStyleRange>[],
    );
    _stepsController = RichRecipeTextEditingController(
      text: steps,
      ranges: contentStyles['steps'] ?? const <RecipeContentStyleRange>[],
    );
    _tipsController = RichRecipeTextEditingController(
      text: tips,
      ranges: contentStyles['tips'] ?? const <RecipeContentStyleRange>[],
    );
    if (recipe != null) {
      _youtubeUrlController.text = recipe.youtubeUrl ?? '';
    }
    _editHistory = RecipeEditHistory({
      _titleController: _titleFocusNode,
      _summaryController: _summaryFocusNode,
      _ingredientsController: _ingredientsFocusNode,
      _stepsController: _stepsFocusNode,
      _tipsController: _tipsFocusNode,
      _youtubeUrlController: _youtubeUrlFocusNode,
    });
  }

  @override
  void dispose() {
    _editHistory.dispose();
    _titleController.dispose();
    _summaryController.dispose();
    _ingredientsController.dispose();
    _stepsController.dispose();
    _tipsController.dispose();
    _youtubeUrlController.dispose();
    _titleFocusNode.dispose();
    _summaryFocusNode.dispose();
    _ingredientsFocusNode.dispose();
    _stepsFocusNode.dispose();
    _tipsFocusNode.dispose();
    _youtubeUrlFocusNode.dispose();
    super.dispose();
  }

  List<String> _splitLines(String input) {
    return input
        .split(RegExp(r'[\r\n,]+'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList();
  }

  List<RecipeContentStyleRange> _trimmedRanges(
    RichRecipeTextEditingController controller,
  ) {
    final raw = controller.text;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const <RecipeContentStyleRange>[];
    final start = raw.length - raw.trimLeft().length;
    return controller.exportSlice(start, start + trimmed.length);
  }

  _NormalizedRichList _normalizedList(
    RichRecipeTextEditingController controller,
  ) {
    final items = <String>[];
    final ranges = <RecipeContentStyleRange>[];
    var outputOffset = 0;
    for (final match in RegExp(r'[^,\r\n]+').allMatches(controller.text)) {
      final raw = match.group(0) ?? '';
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final leading = raw.length - raw.trimLeft().length;
      final sourceStart = match.start + leading;
      final sourceEnd = sourceStart + trimmed.length;
      ranges.addAll(controller.exportSlice(
        sourceStart,
        sourceEnd,
        outputOffset: outputOffset,
      ));
      items.add(trimmed);
      outputOffset += trimmed.length + 1;
    }
    return _NormalizedRichList(items: items, ranges: ranges);
  }

  RecipeContentStyleRanges _contentStylesForSave({
    required _NormalizedRichList ingredients,
    required _NormalizedRichList steps,
  }) {
    return <String, List<RecipeContentStyleRange>>{
      'title': _trimmedRanges(_titleController),
      'summary': _trimmedRanges(_summaryController),
      'ingredients': ingredients.ranges,
      'steps': steps.ranges,
      'tips': _trimmedRanges(_tipsController),
    };
  }

  String _guessExtension(String path) {
    final normalized = path.toLowerCase();
    if (normalized.endsWith('.png')) return 'png';
    if (normalized.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String? _validateYoutubeUrl(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '유효한 YouTube 링크를 입력해 주세요.';
    }

    final host = uri.host.toLowerCase();
    final isAllowedHost = host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');

    if (!isAllowedHost) {
      return 'YouTube 링크만 입력해 주세요.';
    }

    return null;
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );

    if (picked == null) {
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageExtension = _guessExtension(picked.path);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _showValidationErrors = true;
        _errorMessage = '제목·재료·조리 순서의 필수 항목을 확인해 주세요.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _showValidationErrors = false;
      _errorMessage = null;
    });

    String? uploadedImageUrl;
    try {
      final repository = ref.read(recipeRepositoryProvider);
      final imageService = ref.read(recipeImageServiceProvider);
      final summary = _summaryController.text.trim().isEmpty
          ? null
          : _summaryController.text.trim();
      final normalizedIngredients = _normalizedList(_ingredientsController);
      final normalizedSteps = _normalizedList(_stepsController);
      final ingredients = normalizedIngredients.items;
      final steps = normalizedSteps.items;
      final tips = _tipsController.text.trim().isEmpty
          ? null
          : _tipsController.text.trim();
      final youtubeUrl = _youtubeUrlController.text.trim().isEmpty
          ? null
          : _youtubeUrlController.text.trim();
      final contentStyles = encodeRecipeContentStyles(
        _contentStylesForSave(
          ingredients: normalizedIngredients,
          steps: normalizedSteps,
        ),
      );
      final previousImageUrl = widget.initialRecipe?.imageUrl;
      var imagePath = widget.initialRecipe?.imageUrl;

      if (_selectedImageBytes != null) {
        uploadedImageUrl = await imageService.uploadCreatorRecipeImage(
          bytes: _selectedImageBytes!,
          fileExtension: _selectedImageExtension,
        );
        imagePath = uploadedImageUrl;
      }

      final Recipe savedRecipe;

      if (_isEditMode) {
        savedRecipe = await repository.updateCreatorRecipe(
          id: widget.editRecipeId!,
          title: _titleController.text.trim(),
          summary: summary,
          ingredients: ingredients,
          steps: steps,
          tips: tips,
          imagePath: imagePath,
          youtubeUrl: youtubeUrl,
          contentStyles: contentStyles,
        );
      } else {
        savedRecipe = await repository.createCreatorRecipe(
          title: _titleController.text.trim(),
          summary: summary,
          ingredients: ingredients,
          steps: steps,
          tips: tips,
          imagePath: imagePath,
          youtubeUrl: youtubeUrl,
          contentStyles: contentStyles,
        );
      }

      if (_isEditMode &&
          uploadedImageUrl != null &&
          (previousImageUrl ?? '').isNotEmpty &&
          previousImageUrl != uploadedImageUrl) {
        unawaited(
            imageService.deleteCreatorRecipeImageByUrl(previousImageUrl!));
      }

      if (!mounted) {
        return;
      }
      final result =
          !_isEditMode && widget.returnCreatedRecipeId ? savedRecipe.id : true;

      setState(() {
        _saved = true;
        _isSubmitting = false;
      });
      // Let navigation guards observe the completed save before leaving.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (uploadedImageUrl != null) {
        try {
          await ref
              .read(recipeImageServiceProvider)
              .deleteCreatorRecipeImageByUrl(uploadedImageUrl);
        } catch (_) {
          // Ignore rollback failure and keep the original save error message.
        }
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode != 'ko';
    return ListenableBuilder(
        listenable: _editHistory,
        builder: (context, _) => WorkspaceEditGuard(
            dirty: !_saved &&
                (_isAiDraft ||
                    _editHistory.canUndo ||
                    _selectedImageBytes != null),
            busy: _isSubmitting,
            confirmLeave: () async =>
                _saved || await confirmWorkspaceDiscard(context),
            child: Scaffold(
              appBar: AppBar(
                title: LocalizedText(_isEditMode ? '내 레시피 수정' : '새 내 레시피'),
                actions: [
                  ListenableBuilder(
                      listenable: _editHistory,
                      builder: (context, _) =>
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                key: const Key('recipe-edit-undo'),
                                tooltip: context.tr('실행 취소'),
                                onPressed:
                                    !_isSubmitting && _editHistory.canUndo
                                        ? _editHistory.undo
                                        : null,
                                icon: const Icon(Icons.undo_rounded)),
                            IconButton(
                                key: const Key('recipe-edit-redo'),
                                tooltip: context.tr('다시 실행'),
                                onPressed:
                                    !_isSubmitting && _editHistory.canRedo
                                        ? _editHistory.redo
                                        : null,
                                icon: const Icon(Icons.redo_rounded)),
                          ])),
                ],
              ),
              body: SafeArea(
                child: ScoutPageBody(
                  maxWidth: 880,
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _showValidationErrors
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: <Widget>[
                        ScoutPageHeading(
                          title: isEnglish
                              ? 'Make the recipe your own'
                              : '나만의 레시피를 기록하세요',
                          subtitle: isEnglish
                              ? 'Start with a title, ingredients and steps. Add a photo and notes when you are ready.'
                              : '제목, 재료, 조리 순서를 먼저 입력하세요. 사진과 요리 팁은 나중에 더해도 좋아요.',
                          icon: Icons.edit_note_rounded,
                        ),
                        const SizedBox(height: 20),
                        if (_isAiDraft) ...<Widget>[
                          Card(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.55),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(Icons.smart_toy_outlined),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: LocalizedText(
                                      '선택한 YouTube 영상만으로 만든 AI 초안입니다. '
                                      '내용을 확인하고 자유롭게 수정한 뒤 저장해 주세요.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_hasAiConfirmationItems)
                            Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiaryContainer,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(Icons.warning_amber_rounded),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: LocalizedText(
                                        '영상에서 확인되지 않은 정보가 있습니다. '
                                        '“확인 필요”로 표시된 재료·분량·단계를 영상과 비교해 수정해 주세요.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                        if (_showValidationErrors) ...<Widget>[
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.error_outline),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: LocalizedText(
                                      '저장하려면 제목·재료·조리 순서를 모두 입력해야 합니다.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        ScoutPanel(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ScoutSectionLabel(
                                number: '01',
                                title:
                                    isEnglish ? 'Recipe essentials' : '레시피 소개',
                                subtitle: isEnglish
                                    ? 'A title is required. A short summary helps you find this recipe later.'
                                    : '제목은 필수예요. 요약을 더하면 나중에 쉽게 찾을 수 있어요.'),
                            AdvancedRecipeTextField(
                              key: const Key('creator-recipe-title'),
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              label: '제목',
                              maxLength: _maxTitleLength,
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return context.tr('제목을 입력해 주세요.');
                                }
                                if ((value ?? '').trim().length >
                                    _maxTitleLength) {
                                  return context
                                      .tr('제목은 $_maxTitleLength자 이하로 입력해 주세요.');
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            AdvancedRecipeTextField(
                              controller: _summaryController,
                              focusNode: _summaryFocusNode,
                              label: '요약',
                              maxLines: 2,
                              maxLength: _maxSummaryLength,
                            ),
                          ],
                        )),
                        const SizedBox(height: 20),
                        ScoutPanel(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ScoutSectionLabel(
                                number: '02',
                                title: isEnglish
                                    ? 'Ingredients & quantities'
                                    : '재료와 분량',
                                subtitle: isEnglish
                                    ? 'Required · Include quantities and units for easy preparation.'
                                    : '필수 · 재료마다 분량과 단위를 함께 적어 주세요.'),
                            AdvancedRecipeTextField(
                              controller: _ingredientsController,
                              focusNode: _ingredientsFocusNode,
                              label: '재료',
                              helperText: '줄바꿈 또는 쉼표로 구분',
                              maxLines: 4,
                              validator: (String? value) {
                                if (_splitLines(value ?? '').isEmpty) {
                                  return context.tr('재료를 하나 이상 입력해 주세요.');
                                }
                                return null;
                              },
                            ),
                          ],
                        )),
                        const SizedBox(height: 20),
                        ScoutPanel(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ScoutSectionLabel(
                                number: '03',
                                title: isEnglish
                                    ? 'Cooking instructions'
                                    : '조리 과정',
                                subtitle: isEnglish
                                    ? 'Required · Write one step per line, including cooking time and heat.'
                                    : '필수 · 단계별로 줄을 나누고 시간과 불 세기도 적어 주세요.'),
                            AdvancedRecipeTextField(
                              controller: _stepsController,
                              focusNode: _stepsFocusNode,
                              label: '조리 순서',
                              helperText: '줄바꿈 또는 쉼표로 구분',
                              maxLines: 5,
                              validator: (String? value) {
                                if (_splitLines(value ?? '').isEmpty) {
                                  return context.tr('조리 순서를 하나 이상 입력해 주세요.');
                                }
                                return null;
                              },
                            ),
                          ],
                        )),
                        const SizedBox(height: 20),
                        ScoutPanel(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ScoutSectionLabel(
                                number: '04',
                                title: isEnglish
                                    ? 'Notes & reference'
                                    : '팁과 참고 자료',
                                subtitle: isEnglish
                                    ? 'Optional · Add your own tips, a video link or a photo.'
                                    : '선택 · 나만의 팁, 참고 영상, 완성 사진을 더해 보세요.'),
                            AdvancedRecipeTextField(
                              controller: _tipsController,
                              focusNode: _tipsFocusNode,
                              label: '팁',
                              maxLines: 2,
                              maxLength: _maxTipsLength,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _youtubeUrlController,
                              focusNode: _youtubeUrlFocusNode,
                              decoration: InputDecoration(
                                  labelText: context.tr('YouTube 링크')),
                              keyboardType: TextInputType.url,
                              maxLength: _maxYoutubeUrlLength,
                              validator: (String? value) {
                                final message = _validateYoutubeUrl(value);
                                return message == null
                                    ? null
                                    : context.tr(message);
                              },
                            ),
                            const SizedBox(height: 16),
                            LocalizedText('대표 이미지',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _selectedImageBytes != null
                                      ? Image.memory(_selectedImageBytes!,
                                          fit: BoxFit.cover)
                                      : ((widget.initialRecipe?.imageUrl ?? '')
                                              .isNotEmpty
                                          ? PrivateRecipeImage(
                                              widget.initialRecipe!.imageUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) {
                                                return const Center(
                                                    child: LocalizedText(
                                                        '이미지를 불러오지 못했습니다.'));
                                              },
                                            )
                                          : const Center(
                                              child: LocalizedText(
                                                  '선택된 이미지가 없습니다.'))),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _isSubmitting ? null : _pickImage,
                              icon: const Icon(Icons.image_outlined),
                              label: LocalizedText(_selectedImageBytes == null
                                  ? '갤러리에서 이미지 선택'
                                  : '이미지 다시 선택'),
                            ),
                          ],
                        )),
                        if (_errorMessage != null) ...<Widget>[
                          const SizedBox(height: 16),
                          LocalizedText(
                            _errorMessage!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: LocalizedText(_isSubmitting
                              ? '저장 중...'
                              : (_isEditMode ? '수정 저장' : '레시피 저장')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )));
  }
}

class _NormalizedRichList {
  const _NormalizedRichList({required this.items, required this.ranges});

  final List<String> items;
  final List<RecipeContentStyleRange> ranges;
}
