import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

class CreateCreatorRecipePage extends ConsumerStatefulWidget {
  const CreateCreatorRecipePage({
    super.key,
    this.initialRecipe,
  });

  final Recipe? initialRecipe;

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
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _stepsController = TextEditingController();
  final _tipsController = TextEditingController();
  final _youtubeUrlController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _isSubmitting = false;
  String? _errorMessage;
  Uint8List? _selectedImageBytes;
  String _selectedImageExtension = 'jpg';

  bool get _isEditMode => widget.initialRecipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.initialRecipe;
    if (recipe != null) {
      _titleController.text = recipe.title;
      _summaryController.text = recipe.summary ?? '';
      _tipsController.text = recipe.tips ?? '';
      _ingredientsController.text = recipe.ingredients.join('\n');
      _stepsController.text = recipe.steps.join('\n');
      _youtubeUrlController.text = recipe.youtubeUrl ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _ingredientsController.dispose();
    _stepsController.dispose();
    _tipsController.dispose();
    _youtubeUrlController.dispose();
    super.dispose();
  }

  List<String> _splitLines(String input) {
    return input
        .split(RegExp(r'[\r\n,]+'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList();
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
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    String? uploadedImageUrl;
    try {
      final repository = ref.read(recipeRepositoryProvider);
      final imageService = ref.read(recipeImageServiceProvider);
      final summary = _summaryController.text.trim().isEmpty
          ? null
          : _summaryController.text.trim();
      final ingredients = _splitLines(_ingredientsController.text);
      final steps = _splitLines(_stepsController.text);
      final tips = _tipsController.text.trim().isEmpty
          ? null
          : _tipsController.text.trim();
      final youtubeUrl = _youtubeUrlController.text.trim().isEmpty
          ? null
          : _youtubeUrlController.text.trim();
      final previousImageUrl = widget.initialRecipe?.imageUrl;
      var imagePath = widget.initialRecipe?.imageUrl;

      if (_selectedImageBytes != null) {
        uploadedImageUrl = await imageService.uploadCreatorRecipeImage(
          bytes: _selectedImageBytes!,
          fileExtension: _selectedImageExtension,
        );
        imagePath = uploadedImageUrl;
      }

      if (_isEditMode) {
        await repository.updateCreatorRecipe(
          id: widget.initialRecipe!.id,
          title: _titleController.text.trim(),
          summary: summary,
          ingredients: ingredients,
          steps: steps,
          tips: tips,
          imagePath: imagePath,
          youtubeUrl: youtubeUrl,
        );
      } else {
        await repository.createCreatorRecipe(
          title: _titleController.text.trim(),
          summary: summary,
          ingredients: ingredients,
          steps: steps,
          tips: tips,
          imagePath: imagePath,
          youtubeUrl: youtubeUrl,
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
      Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? '크리에이터 레시피 수정' : '새 크리에이터 레시피')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '제목'),
                maxLength: _maxTitleLength,
                validator: (String? value) {
                  if ((value ?? '').trim().isEmpty) {
                    return '제목을 입력해 주세요.';
                  }
                  if ((value ?? '').trim().length > _maxTitleLength) {
                    return '제목은 $_maxTitleLength자 이하로 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _summaryController,
                decoration: const InputDecoration(labelText: '요약'),
                maxLines: 2,
                maxLength: _maxSummaryLength,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ingredientsController,
                decoration: const InputDecoration(
                  labelText: '재료',
                  helperText: '줄바꿈 또는 쉼표로 구분',
                ),
                maxLines: 4,
                validator: (String? value) {
                  if (_splitLines(value ?? '').isEmpty) {
                    return '재료를 하나 이상 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stepsController,
                decoration: const InputDecoration(
                  labelText: '조리 순서',
                  helperText: '줄바꿈 또는 쉼표로 구분',
                ),
                maxLines: 5,
                validator: (String? value) {
                  if (_splitLines(value ?? '').isEmpty) {
                    return '조리 순서를 하나 이상 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tipsController,
                decoration: const InputDecoration(labelText: '팁'),
                maxLines: 2,
                maxLength: _maxTipsLength,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _youtubeUrlController,
                decoration: const InputDecoration(labelText: 'YouTube 링크'),
                keyboardType: TextInputType.url,
                maxLength: _maxYoutubeUrlLength,
                validator: _validateYoutubeUrl,
              ),
              const SizedBox(height: 16),
              Text('대표 이미지', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _selectedImageBytes != null
                        ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                        : ((widget.initialRecipe?.imageUrl ?? '').isNotEmpty
                            ? Image.network(
                                widget.initialRecipe!.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) {
                                  return const Center(
                                      child: Text('이미지를 불러오지 못했습니다.'));
                                },
                              )
                            : const Center(child: Text('선택된 이미지가 없습니다.'))),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                    _selectedImageBytes == null ? '갤러리에서 이미지 선택' : '이미지 다시 선택'),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: Text(_isSubmitting
                    ? '저장 중...'
                    : (_isEditMode ? '수정 저장' : '레시피 저장')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
