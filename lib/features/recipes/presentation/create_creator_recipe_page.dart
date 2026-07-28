import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ai/application/ai_service.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

enum _AutoFilledField {
  summary,
  ingredients,
  steps,
  tips,
}

class _AutoFillDelta {
  const _AutoFillDelta({
    required this.label,
    required this.summary,
  });

  final String label;
  final String summary;
}

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
  final AiService _aiService = AiService();
  final Set<_AutoFilledField> _autoFilledChangedFields = <_AutoFilledField>{};
  final Map<_AutoFilledField, _AutoFillDelta> _autoFillDeltas =
      <_AutoFilledField, _AutoFillDelta>{};

  static const String _localDraftsPrefsKey = 'creator_recipe_local_drafts_v2';

  bool _isSubmitting = false;
  bool _isAutoFilling = false;
  bool _isSavingLocalDraft = false;
  bool _isResolvingYoutubeMeta = false;
  bool _didAutoRestoreOnEntry = false;
  String? _errorMessage;
  Uint8List? _selectedImageBytes;
  String _selectedImageExtension = 'jpg';
  String? _youtubeChannelTitle;
  String? _youtubeVideoTitle;

  bool get _isEditMode => widget.initialRecipe != null;

  bool get _isAuthenticated =>
      Supabase.instance.client.auth.currentSession != null;

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

    if (!_isEditMode) {
      unawaited(_autoRestoreLatestDraftOnEntry());
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

  Future<List<Map<String, dynamic>>> _readLocalDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localDraftsPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <Map<String, dynamic>>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .take(3)
        .toList(growable: false);
  }

  Future<void> _writeLocalDrafts(List<Map<String, dynamic>> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _localDraftsPrefsKey, jsonEncode(drafts.take(3).toList()));
  }

  String _formatSavedAt(String raw) {
    final dateTime = DateTime.tryParse(raw);
    if (dateTime == null) {
      return '시간 정보 없음';
    }

    final local = dateTime.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mi';
  }

  void _applyDraft(Map<String, dynamic> draft) {
    _titleController.text = (draft['title'] ?? '').toString();
    _summaryController.text = (draft['summary'] ?? '').toString();
    _ingredientsController.text = (draft['ingredients'] ?? '').toString();
    _stepsController.text = (draft['steps'] ?? '').toString();
    _tipsController.text = (draft['tips'] ?? '').toString();
    _youtubeUrlController.text = (draft['youtube_url'] ?? '').toString();
    _youtubeChannelTitle =
        (draft['youtube_channel_title'] ?? '').toString().trim().isEmpty
            ? null
            : (draft['youtube_channel_title'] ?? '').toString().trim();
    _youtubeVideoTitle =
        (draft['youtube_video_title'] ?? '').toString().trim().isEmpty
            ? null
            : (draft['youtube_video_title'] ?? '').toString().trim();
    _errorMessage = null;
    _autoFilledChangedFields.clear();
    _autoFillDeltas.clear();
  }

  bool _hasCurrentInput() {
    return _titleController.text.trim().isNotEmpty ||
        _summaryController.text.trim().isNotEmpty ||
        _ingredientsController.text.trim().isNotEmpty ||
        _stepsController.text.trim().isNotEmpty ||
        _tipsController.text.trim().isNotEmpty ||
        _youtubeUrlController.text.trim().isNotEmpty;
  }

  String _buildDraftPreview(Map<String, dynamic> draft) {
    final summary = (draft['summary'] ?? '').toString().trim();
    final ingredients = (draft['ingredients'] ?? '').toString().trim();
    final steps = (draft['steps'] ?? '').toString().trim();

    String preview = summary;
    if (preview.isEmpty) {
      preview = ingredients;
    }
    if (preview.isEmpty) {
      preview = steps;
    }
    if (preview.isEmpty) {
      return '미리보기 없음';
    }

    final oneLine = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 44) {
      return oneLine;
    }
    return '${oneLine.substring(0, 44)}...';
  }

  Future<void> _autoRestoreLatestDraftOnEntry() async {
    if (_didAutoRestoreOnEntry) {
      return;
    }
    _didAutoRestoreOnEntry = true;

    final drafts = await _readLocalDrafts();
    if (!mounted || drafts.isEmpty || _hasCurrentInput()) {
      return;
    }

    final latest = drafts.first;
    final hasAnyField = <String>[
      (latest['title'] ?? '').toString().trim(),
      (latest['summary'] ?? '').toString().trim(),
      (latest['ingredients'] ?? '').toString().trim(),
      (latest['steps'] ?? '').toString().trim(),
      (latest['tips'] ?? '').toString().trim(),
      (latest['youtube_url'] ?? '').toString().trim(),
    ].any((value) => value.isNotEmpty);

    if (!hasAnyField) {
      return;
    }

    setState(() {
      _applyDraft(latest);
    });

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('최근 로컬 초안을 자동 복원했습니다.')),
    );
  }

  Future<Map<String, dynamic>?> _pickDraftToRestore(
    List<Map<String, dynamic>> drafts,
  ) async {
    if (drafts.isEmpty) {
      return null;
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: drafts.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              if (index == drafts.length) {
                return ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('취소'),
                  onTap: () => Navigator.of(context).pop(),
                );
              }

              final draft = drafts[index];
              final title = (draft['title'] ?? '').toString().trim();
              final savedAt =
                  _formatSavedAt((draft['saved_at'] ?? '').toString());
              final preview = _buildDraftPreview(draft);

              return ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(title.isEmpty ? '제목 없는 초안' : title),
                subtitle: Text('저장 시각: $savedAt\n$preview'),
                isThreeLine: true,
                onTap: () => Navigator.of(context).pop(draft),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _restoreLocalDraftIfAvailable() async {
    final drafts = await _readLocalDrafts();
    if (!mounted || drafts.isEmpty) {
      return;
    }

    final selected = await _pickDraftToRestore(drafts);
    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _applyDraft(selected);
    });
  }

  Future<void> _clearLocalDraft({bool showMessage = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localDraftsPrefsKey);

    if (!mounted || !showMessage) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로컬 초안을 삭제했습니다.')),
    );
  }

  Future<void> _saveLocalDraft({bool showMessage = true}) async {
    setState(() {
      _isSavingLocalDraft = true;
      _errorMessage = null;
    });

    try {
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'summary': _summaryController.text.trim(),
        'ingredients': _ingredientsController.text.trim(),
        'steps': _stepsController.text.trim(),
        'tips': _tipsController.text.trim(),
        'youtube_url': _youtubeUrlController.text.trim(),
        'youtube_channel_title': _youtubeChannelTitle,
        'youtube_video_title': _youtubeVideoTitle,
        'saved_at': DateTime.now().toIso8601String(),
      };

      final drafts = await _readLocalDrafts();
      final normalizedTitle = payload['title'].toString().trim().toLowerCase();
      final dedupedDrafts = drafts.where((draft) {
        if (normalizedTitle.isEmpty) {
          return true;
        }

        final draftTitle =
            (draft['title'] ?? '').toString().trim().toLowerCase();
        return draftTitle != normalizedTitle;
      }).toList(growable: false);

      final nextDrafts = <Map<String, dynamic>>[payload, ...dedupedDrafts]
          .take(3)
          .toList(growable: false);
      await _writeLocalDrafts(nextDrafts);

      if (!mounted || !showMessage) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로컬 초안으로 저장했습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '로컬 초안 저장에 실패했습니다: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLocalDraft = false;
        });
      }
    }
  }

  InputDecoration _decorateAutoFilled(
    InputDecoration base,
    _AutoFilledField field, {
    String? helperText,
  }) {
    final wasChanged = _autoFilledChangedFields.contains(field);
    if (!wasChanged) {
      return helperText == null ? base : base.copyWith(helperText: helperText);
    }

    final mergedHelperText = helperText == null || helperText.isEmpty
        ? 'AI 자동 채움으로 갱신됨'
        : '$helperText\nAI 자동 채움으로 갱신됨';

    return base.copyWith(
      helperText: mergedHelperText,
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .tertiaryContainer
          .withValues(alpha: 0.35),
      suffixIcon: const Icon(Icons.auto_awesome, size: 18),
    );
  }

  bool _didTextChange(String before, String after) {
    return before.trim() != after.trim();
  }

  String _buildCountDelta(String before, String after) {
    final beforeCount = _splitLines(before).length;
    final afterCount = _splitLines(after).length;
    return '$beforeCount개 -> $afterCount개';
  }

  Future<void> _resolveYoutubeMetadataFromUrl({
    bool showErrorMessage = false,
  }) async {
    final youtubeUrl = _youtubeUrlController.text.trim();
    if (youtubeUrl.isEmpty) {
      setState(() {
        _youtubeChannelTitle = null;
        _youtubeVideoTitle = null;
      });
      return;
    }

    setState(() {
      _isResolvingYoutubeMeta = true;
    });

    try {
      final endpoint = Uri.https('www.youtube.com', '/oembed', <String, String>{
        'url': youtubeUrl,
        'format': 'json',
      });
      final response =
          await http.get(endpoint).timeout(const Duration(seconds: 6));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('메타데이터 조회 실패(${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('invalid_oembed_payload');
      }

      final channel = (decoded['author_name'] ?? '').toString().trim();
      final videoTitle = (decoded['title'] ?? '').toString().trim();

      if (!mounted) {
        return;
      }

      setState(() {
        _youtubeChannelTitle = channel.isEmpty ? null : channel;
        _youtubeVideoTitle = videoTitle.isEmpty ? null : videoTitle;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _youtubeChannelTitle = null;
        _youtubeVideoTitle = null;
      });

      if (showErrorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('YouTube 메타데이터 조회에 실패했습니다: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingYoutubeMeta = false;
        });
      }
    }
  }

  Widget _buildAutoFillSummaryCard() {
    if (_autoFillDeltas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: Theme.of(context)
          .colorScheme
          .tertiaryContainer
          .withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '자동 채움 변경점 요약 (${_autoFillDeltas.length}개)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ..._autoFillDeltas.values.map(
              (delta) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${delta.label}: ${delta.summary}'),
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _autoFillFromYoutube() async {
    final title = _titleController.text.trim();
    final youtubeUrl = _youtubeUrlController.text.trim();

    if (title.isEmpty && youtubeUrl.isEmpty) {
      setState(() {
        _errorMessage = '제목 또는 YouTube 링크를 입력해 주세요.';
      });
      return;
    }

    final hasExistingDraft = _summaryController.text.trim().isNotEmpty ||
        _ingredientsController.text.trim().isNotEmpty ||
        _stepsController.text.trim().isNotEmpty ||
        _tipsController.text.trim().isNotEmpty;

    if (hasExistingDraft) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('AI 자동 채움 적용'),
            content: const Text('현재 입력한 요약/재료/조리순서/팁을 AI 초안으로 덮어쓸까요?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('덮어쓰기'),
              ),
            ],
          );
        },
      );

      if (overwrite != true) {
        return;
      }
    }

    setState(() {
      _isAutoFilling = true;
      _errorMessage = null;
    });

    try {
      await _resolveYoutubeMetadataFromUrl(showErrorMessage: false);

      final beforeSummary = _summaryController.text;
      final beforeIngredients = _ingredientsController.text;
      final beforeSteps = _stepsController.text;
      final beforeTips = _tipsController.text;

      final effectiveTitle =
          title.isNotEmpty ? title : (_youtubeVideoTitle ?? '').trim();

      final draft = await _aiService.generateRecipeDraftFromYoutube(
        title: effectiveTitle,
        summary: _summaryController.text.trim(),
        youtubeUrl: youtubeUrl,
        channelTitle: (_youtubeChannelTitle ?? '').trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _summaryController.text = draft.summary;
        _ingredientsController.text = draft.ingredients.join('\n');
        _stepsController.text = draft.steps.join('\n');
        if (draft.tips.isNotEmpty) {
          _tipsController.text = draft.tips.join('\n');
        }

        _autoFilledChangedFields
          ..clear()
          ..addAll(<_AutoFilledField>{
            if (_didTextChange(beforeSummary, _summaryController.text))
              _AutoFilledField.summary,
            if (_didTextChange(beforeIngredients, _ingredientsController.text))
              _AutoFilledField.ingredients,
            if (_didTextChange(beforeSteps, _stepsController.text))
              _AutoFilledField.steps,
            if (_didTextChange(beforeTips, _tipsController.text))
              _AutoFilledField.tips,
          });

        _autoFillDeltas
          ..clear()
          ..addEntries(<MapEntry<_AutoFilledField, _AutoFillDelta>>[
            if (_didTextChange(beforeSummary, _summaryController.text))
              MapEntry(
                _AutoFilledField.summary,
                _AutoFillDelta(
                  label: '요약',
                  summary:
                      '${beforeSummary.trim().length}자 -> ${_summaryController.text.trim().length}자',
                ),
              ),
            if (_didTextChange(beforeIngredients, _ingredientsController.text))
              MapEntry(
                _AutoFilledField.ingredients,
                _AutoFillDelta(
                  label: '재료',
                  summary: _buildCountDelta(
                    beforeIngredients,
                    _ingredientsController.text,
                  ),
                ),
              ),
            if (_didTextChange(beforeSteps, _stepsController.text))
              MapEntry(
                _AutoFilledField.steps,
                _AutoFillDelta(
                  label: '조리 순서',
                  summary: _buildCountDelta(beforeSteps, _stepsController.text),
                ),
              ),
            if (_didTextChange(beforeTips, _tipsController.text))
              MapEntry(
                _AutoFilledField.tips,
                _AutoFillDelta(
                  label: '팁',
                  summary:
                      '${beforeTips.trim().length}자 -> ${_tipsController.text.trim().length}자',
                ),
              ),
          ]);
      });

      if (!mounted) {
        return;
      }

      final note = draft.degraded ? ' (보조 초안)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 자동 채움이 완료되었습니다$note. 최종 편집 후 저장해 주세요.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'AI 자동 채움에 실패했습니다: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAutoFilling = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_isAuthenticated) {
      await _saveLocalDraft(showMessage: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '현재 정책상 로그인 전에는 서버 저장이 불가하며 로컬 초안만 저장됩니다.';
      });
      return;
    }

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
      unawaited(_clearLocalDraft(showMessage: false));
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
              if (!_isAuthenticated) ...<Widget>[
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.45),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '정책 안내: 로그인 전에는 서버 저장이 불가하며 로컬 초안 저장만 지원됩니다.',
                    ),
                  ),
                ),
              ],
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
                decoration: _decorateAutoFilled(
                  const InputDecoration(labelText: '요약'),
                  _AutoFilledField.summary,
                ),
                maxLines: 2,
                maxLength: _maxSummaryLength,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ingredientsController,
                decoration: _decorateAutoFilled(
                  const InputDecoration(
                    labelText: '재료',
                  ),
                  _AutoFilledField.ingredients,
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
                decoration: _decorateAutoFilled(
                  const InputDecoration(
                    labelText: '조리 순서',
                  ),
                  _AutoFilledField.steps,
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
                decoration: _decorateAutoFilled(
                  const InputDecoration(labelText: '팁'),
                  _AutoFilledField.tips,
                ),
                maxLines: 2,
                maxLength: _maxTipsLength,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _youtubeUrlController,
                decoration: InputDecoration(
                  labelText: 'YouTube 링크',
                  suffixIcon: _isResolvingYoutubeMeta
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: () => _resolveYoutubeMetadataFromUrl(
                            showErrorMessage: true,
                          ),
                          icon: const Icon(Icons.refresh),
                          tooltip: '메타데이터 다시 조회',
                        ),
                ),
                keyboardType: TextInputType.url,
                maxLength: _maxYoutubeUrlLength,
                validator: _validateYoutubeUrl,
                onEditingComplete: () {
                  FocusScope.of(context).nextFocus();
                  unawaited(_resolveYoutubeMetadataFromUrl());
                },
              ),
              if ((_youtubeChannelTitle ?? '').isNotEmpty ||
                  (_youtubeVideoTitle ?? '').isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'YouTube 메타데이터',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        if ((_youtubeChannelTitle ?? '').isNotEmpty)
                          Text('채널: ${_youtubeChannelTitle!}'),
                        if ((_youtubeVideoTitle ?? '').isNotEmpty)
                          Text('영상 제목: ${_youtubeVideoTitle!}'),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_isSubmitting || _isAutoFilling)
                    ? null
                    : _autoFillFromYoutube,
                icon: _isAutoFilling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(
                    _isAutoFilling ? 'AI 초안 생성 중...' : 'YouTube 기반 AI 자동 채움'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed:
                        (_isSubmitting || _isAutoFilling || _isSavingLocalDraft)
                            ? null
                            : () => _saveLocalDraft(showMessage: true),
                    icon: _isSavingLocalDraft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                        _isSavingLocalDraft ? '로컬 초안 저장 중...' : '로컬 초안 저장'),
                  ),
                  TextButton(
                    onPressed:
                        (_isSubmitting || _isAutoFilling || _isSavingLocalDraft)
                            ? null
                            : () => _clearLocalDraft(showMessage: true),
                    child: const Text('로컬 초안 삭제'),
                  ),
                  TextButton(
                    onPressed:
                        (_isSubmitting || _isAutoFilling || _isSavingLocalDraft)
                            ? null
                            : _restoreLocalDraftIfAvailable,
                    child: const Text('최근 초안 불러오기'),
                  ),
                ],
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
              _buildAutoFillSummaryCard(),
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
