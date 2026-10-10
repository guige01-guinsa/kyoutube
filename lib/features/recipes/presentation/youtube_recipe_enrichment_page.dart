import 'package:k_youtube/core/widgets/scout_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../membership/application/membership_providers.dart';
import 'widgets/youtube_draft_methods.dart';
import '../application/recipe_providers.dart';
import '../application/recipe_enrichment_service.dart';
import '../domain/recipe.dart';
import '../domain/recipe_enrichment_suggestion.dart';
import 'create_creator_recipe_page.dart';

class YoutubeRecipeEnrichmentPage extends ConsumerStatefulWidget {
  const YoutubeRecipeEnrichmentPage({
    super.key,
    required this.recipe,
  });

  final Recipe recipe;

  @override
  ConsumerState<YoutubeRecipeEnrichmentPage> createState() =>
      _YoutubeRecipeEnrichmentPageState();
}

class _YoutubeRecipeEnrichmentPageState
    extends ConsumerState<YoutubeRecipeEnrichmentPage> {
  static const _progressLabels = <String>[
    '영상 제목에서 레시피 이름을 정리하고 있습니다.',
    '영상 설명에서 재료와 분량을 확인하고 있습니다.',
    '조리 순서와 팁을 편집 가능한 초안으로 만들고 있습니다.',
  ];

  bool _isGenerating = false;
  bool _videoAnalysis = false;
  int _progressStage = 0;
  Timer? _progressTimer;
  final TextEditingController _transcriptController = TextEditingController();
  final TextEditingController _recipeNameHintController =
      TextEditingController();
  final TextEditingController _ingredientHintsController =
      TextEditingController();
  String? _error;
  String? _errorCode;
  RecipeEnrichmentSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    // Let the user choose a method before starting a billable generation.
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _transcriptController.dispose();
    _recipeNameHintController.dispose();
    _ingredientHintsController.dispose();
    super.dispose();
  }

  Future<void> _generate({
    String? transcript,
    bool includeHints = false,
    bool videoAnalysis = false,
  }) async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _videoAnalysis = videoAnalysis;
      _progressStage = 0;
      _error = null;
      _errorCode = null;
    });
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted || _progressStage >= _progressLabels.length - 1) return;
      setState(() => _progressStage += 1);
    });

    RecipeEnrichmentService? enrichmentService;
    try {
      enrichmentService = RecipeEnrichmentService();
      final suggestion =
          await enrichmentService.createSuggestionFromSelectedYoutubeVideo(
        recipe: widget.recipe,
        videoAnalysis: videoAnalysis,
        outputLocale: switch (Localizations.localeOf(context).languageCode) {
          'en' => 'en-US',
          'es' => 'es-419',
          _ => 'ko-KR',
        },
        transcript: transcript,
        recipeNameHint:
            includeHints ? _recipeNameHintController.text.trim() : null,
        ingredientHints:
            includeHints ? _ingredientHintsController.text.trim() : null,
      );

      if (!mounted) return;

      setState(() {
        _suggestion = suggestion;
      });

      await _openEditor(suggestion);
    } on RecipeEnrichmentException catch (error) {
      if (mounted) {
        if (error.code == 'ai_draft_incomplete') {
          ref.invalidate(recipeSearchExclusionsProvider);
        }
        setState(() {
          _error = error.message;
          _errorCode = error.code;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '영상 기반 AI 레시피 보강 중 오류가 발생했습니다.';
          _errorCode = null;
        });
      }
    } finally {
      if (mounted) {
        ref.invalidate(membershipInfoProvider);
        ref.invalidate(videoAnalysisUsageProvider);
      }
      enrichmentService?.close();
      _progressTimer?.cancel();
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _openYoutubeVideo() async {
    final rawUrl = widget.recipe.youtubeUrl?.trim() ?? '';
    final uri = Uri.tryParse(rawUrl);

    if (uri == null || !_isAllowedYoutubeUri(uri)) {
      _showMessage('YouTube 링크를 열 수 없습니다.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showMessage('YouTube를 열 수 없습니다.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('YouTube를 열 수 없습니다.');
      }
    }
  }

  bool _isAllowedYoutubeUri(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');
  }

  void _generateFromTranscript() {
    final transcript = _transcriptController.text.trim();
    if (transcript.isEmpty) {
      setState(() {
        _error = '자막을 붙여넣은 뒤 다시 시도해 주세요.';
      });
      return;
    }
    _generate(transcript: transcript, includeHints: true);
  }

  Future<void> _pasteTranscriptFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('클립보드에 붙여넣을 자막이 없습니다.');
      return;
    }
    _transcriptController.text = text;
    _transcriptController.selection = TextSelection.collapsed(
      offset: _transcriptController.text.length,
    );
    if (mounted) setState(() => _error = null);
    _showMessage('자막을 붙여넣었습니다.');
  }

  void _generateFromDescriptionWithHints() {
    _generate(includeHints: true);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: LocalizedText(message)),
    );
  }

  Future<void> _openEditor(RecipeEnrichmentSuggestion suggestion) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CreateCreatorRecipePage(
          initialRecipe: suggestion.toDraftRecipe(
            sourceRecipe: widget.recipe,
            isEnglish: Localizations.localeOf(context).languageCode != 'ko',
          ),
          returnCreatedRecipeId: true,
        ),
      ),
    );

    if (result is String && result.trim().isNotEmpty && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final youtubeUrl = widget.recipe.youtubeUrl?.trim() ?? '';
    final suggestion = _suggestion;

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('AI 레시피 초안 만들기'),
      ),
      body: ScoutPageBody(
          maxWidth: 900,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: ScoutStyle.mint,
                      borderRadius: BorderRadius.circular(22)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        LocalizedText('나의 레시피가 되는 과정',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                          const Chip(
                              avatar:
                                  Icon(Icons.check_circle_outline, size: 18),
                              label: LocalizedText('1 영상 선택')),
                          Chip(
                              avatar: Icon(
                                  suggestion == null
                                      ? Icons.auto_awesome
                                      : Icons.check_circle_outline,
                                  size: 18),
                              label: const LocalizedText('2 AI 초안')),
                          Chip(
                              avatar: Icon(
                                  suggestion == null
                                      ? Icons.edit_outlined
                                      : Icons.edit_note,
                                  size: 18),
                              label: const LocalizedText('3 확인 후 저장')),
                        ]),
                        const SizedBox(height: 8),
                        LocalizedText(
                            suggestion == null
                                ? (_isGenerating
                                    ? '영상 속 요리 정보를 정리하고 있어요.'
                                    : '설명 기반 자동 초안 또는 영상 분석을 선택해 주세요.')
                                : '초안이 준비됐어요. 재료와 분량을 확인해 주세요.',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                ),
                const SizedBox(height: 24),
                LocalizedText(
                  widget.recipe.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const LocalizedText(
                  '먼저 영상 제목과 설명란으로 AI 초안을 만듭니다. 결과가 부족하면 YouTube 자막을 붙여넣고 '
                  '요리명 또는 핵심 재료 힌트를 추가해 다시 만들 수 있습니다.',
                ),
                const SizedBox(height: 16),
                if (youtubeUrl.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(youtubeUrl),
                    ),
                  ),
                const SizedBox(height: 20),
                if (!_isGenerating)
                  YoutubeDraftMethods(
                    onStandard: () => _generate(),
                    onVideo: () => _generate(videoAnalysis: true),
                  ),
                if (suggestion == null) ...<Widget>[
                  if (_isGenerating) ...<Widget>[
                    LinearProgressIndicator(
                      value: (_progressStage + 1) / _progressLabels.length,
                    ),
                    const SizedBox(height: 12),
                    LocalizedText(
                      _videoAnalysis
                          ? '영상의 음성과 화면에서 조리 정보를 분석하고 있습니다. 최대 3분 정도 걸릴 수 있습니다.'
                          : _progressLabels[_progressStage],
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_error != null && !_isGenerating) ...<Widget>[
                    if (_isUsageLimitError(_errorCode))
                      const _AiUsageLimitNotice()
                    else
                      LocalizedText(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (!_isGenerating) ...<Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            LocalizedText(
                              '자막 위치 확인',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            const LocalizedText(
                              'YouTube 설명의 “더보기” 안쪽 내용은 앱이 전체 설명으로 자동 수집합니다. 기본 생성 결과가 부족하면 아래 순서로 자막을 붙여넣어 다시 만드세요.\n'
                              '1. 아래 버튼으로 YouTube 영상을 엽니다.\n'
                              '2. 영상 제목 주변의 더보기 또는 메뉴에서 “스크립트 표시”를 찾습니다.\n'
                              '3. 레시피 설명이 들어 있는 자막 텍스트를 복사해 아래에 붙여넣습니다.',
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed:
                                  youtubeUrl.isEmpty ? null : _openYoutubeVideo,
                              icon: const Icon(Icons.open_in_new),
                              label: const LocalizedText('YouTube에서 자막 확인'),
                            ),
                            const Divider(height: 28),
                            LocalizedText(
                              '보조 힌트',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            const LocalizedText(
                              '요리명과 핵심 재료를 알면 AI가 긴 자막에서 필요한 부분을 더 정확히 고릅니다.',
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _recipeNameHintController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: context.tr('요리명 힌트'),
                                hintText: context.tr('예: 김치찌개'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _ingredientHintsController,
                              minLines: 2,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: context.tr('핵심 재료 힌트'),
                                hintText: context.tr('예: 돼지고기, 김치, 두부, 대파'),
                              ),
                            ),
                            const Divider(height: 28),
                            LocalizedText(
                              '자막 붙여넣기',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            const LocalizedText(
                              '잡담이나 인사말이 섞여 있어도 됩니다. AI가 재료와 조리 순서 중심으로 정리합니다.',
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _transcriptController,
                              minLines: 6,
                              maxLines: 10,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: context.tr('영상 자막 붙여넣기'),
                                hintText: context
                                    .tr('예: 김치를 썰고 돼지고기를 볶은 다음 물을 넣고 끓입니다...'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                OutlinedButton.icon(
                                  onPressed: _pasteTranscriptFromClipboard,
                                  icon: const Icon(Icons.content_paste_rounded),
                                  label: const LocalizedText('클립보드 자막 붙여넣기'),
                                ),
                                FilledButton.icon(
                                  onPressed: _generateFromTranscript,
                                  icon:
                                      const Icon(Icons.closed_caption_outlined),
                                  label: const LocalizedText('자막으로 AI 초안 만들기'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _generateFromDescriptionWithHints,
                      icon: const Icon(Icons.description_outlined),
                      label: const LocalizedText('힌트와 함께 설명란으로 다시 시도'),
                    ),
                  ],
                ] else ...<Widget>[
                  LocalizedText(
                    suggestion.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  LocalizedText(suggestion.summary),
                  if (suggestion.servings != null ||
                      suggestion.prepTimeMinutes != null ||
                      suggestion.cookTimeMinutes != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        if (suggestion.servings != null)
                          Chip(
                              label: LocalizedText('${suggestion.servings}인분')),
                        if (suggestion.prepTimeMinutes != null)
                          Chip(
                              label: LocalizedText(
                                  '준비 ${suggestion.prepTimeMinutes}분')),
                        if (suggestion.cookTimeMinutes != null)
                          Chip(
                              label: LocalizedText(
                                  '조리 ${suggestion.cookTimeMinutes}분')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  LocalizedText('재료',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (suggestion.ingredientDetails.isEmpty)
                    ...suggestion.ingredients
                        .map((item) => LocalizedText('• $item'))
                  else
                    ...suggestion.ingredientDetails.asMap().entries.map(
                          (entry) => _EvidenceLine(
                            text: entry.key < suggestion.ingredients.length
                                ? suggestion.ingredients[entry.key]
                                : entry.value.name,
                            status: entry.value.status,
                          ),
                        ),
                  const SizedBox(height: 16),
                  LocalizedText('조리 순서',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (suggestion.stepDetails.isEmpty)
                    ...suggestion.steps.asMap().entries.map((entry) =>
                        LocalizedText('${entry.key + 1}. ${entry.value}'))
                  else
                    ...suggestion.stepDetails.asMap().entries.map(
                          (entry) => _EvidenceLine(
                            text: entry.key < suggestion.steps.length
                                ? '${entry.key + 1}. ${suggestion.steps[entry.key]}'
                                : '${entry.key + 1}. ${entry.value.instruction}',
                            status: entry.value.status,
                          ),
                        ),
                  if ((suggestion.tips ?? '').trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    LocalizedText('팁',
                        style: Theme.of(context).textTheme.titleMedium),
                    LocalizedText(suggestion.tips!),
                  ],
                  if (suggestion.warnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    LocalizedText(
                      '사용자 확인사항',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ...suggestion.warnings
                        .map((item) => LocalizedText('• $item')),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openEditor(suggestion),
                    icon: const Icon(Icons.edit_outlined),
                    label: const LocalizedText('초안 수정 후 저장'),
                  ),
                ],
              ],
            ),
          )),
    );
  }

  bool _isUsageLimitError(String? code) {
    return <String>{
      'ai_usage_limit_reached',
      'ai_upstream_quota_exceeded',
      'ai_upstream_rate_limited',
    }.contains(code);
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.text,
    required this.status,
  });

  final String text;
  final RecipeEvidenceStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final needsAttention = status != RecipeEvidenceStatus.confirmed;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: LocalizedText(text)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: needsAttention
                  ? colorScheme.errorContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: LocalizedText(
              status.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: needsAttention
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageLimitNotice extends StatelessWidget {
  const _AiUsageLimitNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.hourglass_top_rounded,
                color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: LocalizedText(
                'AI 사용량 한도에 도달했거나 요청이 일시적으로 많습니다. '
                '잠시 후 다시 시도해 주세요. 입력한 자막과 힌트는 이 화면에 그대로 유지됩니다.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
