import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/application/ai_service.dart';
import '../../cooking/application/voice_guide_providers.dart';
import '../../cooking/application/voice_guide_service.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../../core/ops/ops_monitor_service.dart';
import '../../../core/widgets/network_state_banner.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_network_fallback.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'youtube_link_card.dart';

class RecipeDetailPage extends ConsumerStatefulWidget {
  const RecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends ConsumerState<RecipeDetailPage> {
  static const bool _showVoiceGuideSection = false;
  static const List<int> _autoAdvanceSecondOptions = <int>[3, 5, 8];
  static const List<String> _aiRegenerateReasons = <String>[
    'too_short',
    'too_long',
    'need_more_steps',
    'need_safety_tips',
    'tone_not_clear',
  ];
  static const Map<String, String> _aiRegenerateReasonLabels = <String, String>{
    'too_short': '내용이 너무 짧아요',
    'too_long': '내용이 너무 길어요',
    'need_more_steps': '조리 순서 설명이 더 필요해요',
    'need_safety_tips': '안전/주의 팁이 더 필요해요',
    'tone_not_clear': '표현이 명확하지 않아요',
  };
  static const String _autoAdvanceSecondsPrefKey =
      'cooking.auto_advance_seconds';
  static const String _autoAdvanceEnabledPrefKey =
      'cooking.auto_advance_enabled';
  static const String _lastStepIndexPrefKeyPrefix = 'cooking.last_step_index';

  Timer? _autoAdvanceTimer;
  bool _autoAdvanceEnabled = false;
  bool _autoTickInProgress = false;
  bool _autoAdvanceRestorePending = false;
  bool _lastStepRestorePending = false;
  bool _isBookmarked = false;
  bool _isBookmarkLoading = true;
  int _autoAdvanceSeconds = 5;
  int _savedStepIndex = 0;
  int? _cookRating;
  bool? _cookLiked;
  bool _isAiSummaryLoading = false;
  bool _isAiFeedbackSubmitting = false;
  bool? _aiFeedbackLiked;
  int _aiRegenerateAttempt = 0;
  int _pendingNetworkRetryAttempts = 0;
  AiSummaryResult? _aiSummaryResult;
  final TextEditingController _cookNoteController = TextEditingController();
  final AiService _aiService = AiService();
  late final VoiceGuideService _voiceGuideService;

  Duration get _autoAdvanceInterval => Duration(seconds: _autoAdvanceSeconds);

  bool _isSessionProblem(Object error) {
    final message = error.toString();
    return message.contains('로그인이 필요합니다') || message.contains('다시 로그인해 주세요');
  }

  bool _isNetworkProblem(Object error) {
    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('ClientException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused');
  }

  String _friendlyActionError(Object error, String fallback) {
    if (_isSessionProblem(error)) {
      return '세션 정보를 다시 불러오지 못했습니다.';
    }

    if (_isNetworkProblem(error)) {
      return '네트워크 연결을 확인해 주세요.';
    }

    return fallback;
  }

  void _redirectToLoginIfNeeded(Object error) {
    if (_isSessionProblem(error) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션 정보를 다시 확인할 수 없습니다.')),
      );
    }
  }

  String get _lastStepIndexPrefKey =>
      '$_lastStepIndexPrefKeyPrefix.${widget.recipeId}';

  @override
  void initState() {
    super.initState();
    _voiceGuideService = ref.read(voiceGuideServiceProvider);
    _restoreAutoAdvancePreferences();
    _loadBookmarkState();
  }

  @override
  void dispose() {
    _cancelAutoAdvanceTimer();
    _voiceGuideService.stop();
    _cookNoteController.dispose();
    super.dispose();
  }

  Future<void> _restoreAutoAdvancePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt(_autoAdvanceSecondsPrefKey);
    final savedEnabled = prefs.getBool(_autoAdvanceEnabledPrefKey) ?? false;
    final savedStepIndex = prefs.getInt(_lastStepIndexPrefKey);

    if (!mounted) {
      return;
    }

    setState(() {
      if (savedSeconds != null &&
          _autoAdvanceSecondOptions.contains(savedSeconds)) {
        _autoAdvanceSeconds = savedSeconds;
      }
      _autoAdvanceRestorePending = savedEnabled;
      if (savedStepIndex != null && savedStepIndex >= 0) {
        _savedStepIndex = savedStepIndex;
        _lastStepRestorePending = true;
      }
    });
  }

  Future<void> _persistAutoAdvanceSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoAdvanceSecondsPrefKey, seconds);
  }

  Future<void> _persistAutoAdvanceEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoAdvanceEnabledPrefKey, enabled);
  }

  Future<void> _persistCurrentStepIndex(List<String> steps) async {
    final snapshot = _voiceGuideService.snapshot(steps);
    if (!snapshot.hasSteps) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastStepIndexPrefKey, snapshot.currentStepIndex);
  }

  Future<void> _startGuide(List<String> steps, {int? fromIndex}) async {
    await _voiceGuideService.start(steps, fromIndex: fromIndex);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _nextStep(List<String> steps) async {
    await _voiceGuideService.next(steps);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _previousStep(List<String> steps) async {
    await _voiceGuideService.previous(steps);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _cancelAutoAdvanceTimer() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  Future<void> _setAutoAdvance(bool enabled, List<String> steps) async {
    _autoAdvanceRestorePending = false;
    await _persistAutoAdvanceEnabled(enabled);

    if (enabled) {
      await _startAutoAdvance(steps);
      return;
    }

    await _stopAutoAdvance(steps: steps, stopGuidance: false);
  }

  Future<void> _copyToMyRecipes(Recipe recipe) async {
    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.createSubscriberRecipeFromPublic(source: recipe);
      ref.invalidate(subscriberRecipesProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내 요리 노트에 복사했습니다.')),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복사 기능을 사용할 수 없습니다.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyActionError(err, '복사에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }

  Future<void> _loadBookmarkState() async {
    try {
      final repository = ref.read(recipeRepositoryProvider);
      final bookmarked = await repository.isBookmarked(
        recipeType: 'public',
        recipeId: widget.recipeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isBookmarked = bookmarked;
        _isBookmarkLoading = false;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }

      _redirectToLoginIfNeeded(err);

      setState(() {
        _isBookmarkLoading = false;
      });
    }
  }

  Future<void> _toggleBookmark(Recipe recipe) async {
    setState(() {
      _isBookmarkLoading = true;
    });

    try {
      final repository = ref.read(recipeRepositoryProvider);
      if (_isBookmarked) {
        await repository.removeBookmark(
            recipeType: 'public', recipeId: recipe.id);
      } else {
        await repository.addBookmark(recipeType: 'public', recipeId: recipe.id);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isBookmarked = !_isBookmarked;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isBookmarked ? '북마크에 저장했습니다.' : '북마크를 해제했습니다.')),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('북마크 기능을 사용할 수 없습니다.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyActionError(err, '북마크 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBookmarkLoading = false;
        });
      }
    }
  }

  Future<void> _createShoppingListFromRecipe(Recipe recipe) async {
    if (recipe.ingredients.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재료 정보가 없어 장보기 목록을 만들 수 없습니다.')),
      );
      return;
    }

    try {
      final repository = ref.read(recipeRepositoryProvider);
      final result = await repository.createKitchenShoppingFromRecipe(
        recipeType: 'public',
        recipe: recipe,
      );
      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenShoppingListsProvider(kitchenDefaultShoppingListsQuery));

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reopenedFromCompleted
                ? '완료된 장보기를 다시 열었습니다. 부족 재료 ${result.missingCount}개'
                : result.resetFromFullyChecked
                    ? '이전 장보기를 다시 시작합니다. 체크를 초기화했습니다.'
                : result.noMissingItems
                  ? '이미 보유 중인 재료라 장보기 항목이 없습니다.'
                  : result.reusedActiveList
                    ? '기존 장보기 리스트를 이어서 사용합니다. 남은 항목 ${result.missingCount}개'
                        : '장보기 리스트를 만들었습니다. 부족 재료 ${result.missingCount}개',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      if (context.mounted) {
        context.push('/kitchen');
      }
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장보기 추가 기능을 사용할 수 없습니다.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_friendlyActionError(
              err,
              '장보기 목록 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.',
            )}\n$err',
          ),
        ),
      );
    }
  }

  Future<void> _completeCookSession(Recipe recipe) async {
    try {
      await ref.read(kitchenApiProvider).completeCook(
            recipeType: 'public',
            recipeId: recipe.id,
            recipeTitle: recipe.title,
            rating: _cookRating,
            liked: _cookLiked,
            note: _cookNoteController.text,
          );

      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenCookSessionsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('조리 완료 기록을 저장했습니다.'),
          action: SnackBarAction(
            label: '장보기 보기',
            onPressed: () {
              context.push('/kitchen');
            },
          ),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('조리 완료 기록 기능을 사용할 수 없습니다.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyActionError(err, '조리 완료 기록 저장에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }

  Future<void> _startAutoAdvance(List<String> steps, {int? fromIndex}) async {
    final snapshot = _voiceGuideService.snapshot(steps);

    if (!snapshot.hasSteps) {
      return;
    }

    _cancelAutoAdvanceTimer();
    await _startGuide(
      steps,
      fromIndex: fromIndex ?? snapshot.currentStepIndex,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _autoAdvanceEnabled = true;
    });

    _autoAdvanceTimer = Timer.periodic(_autoAdvanceInterval, (_) async {
      if (!mounted || _autoTickInProgress) {
        return;
      }

      _autoTickInProgress = true;
      try {
        final currentSnapshot = _voiceGuideService.snapshot(steps);

        if (!currentSnapshot.hasSteps || currentSnapshot.isLastStep) {
          await _voiceGuideService.stopGuidance(steps);
          _cancelAutoAdvanceTimer();
          if (mounted) {
            setState(() {
              _autoAdvanceEnabled = false;
            });
          }
          return;
        }

        await _voiceGuideService.next(steps);
        await _persistCurrentStepIndex(steps);
        if (mounted) {
          setState(() {});
        }
      } finally {
        _autoTickInProgress = false;
      }
    });
  }

  Future<void> _generateAiSummary(
    Recipe recipe, {
    String action = 'summarize',
    String? regenerateReason,
  }) async {
    if (_isAiSummaryLoading) {
      return;
    }

    final normalizedAction =
        action == 'regenerate' ? 'regenerate' : 'summarize';
    final previousSummary = _aiSummaryResult?.summary ?? '';
    final regenerateAttempt =
        normalizedAction == 'regenerate' ? _aiRegenerateAttempt + 1 : 0;
    final userFeedbackContext = _aiFeedbackLiked == null
        ? ''
        : (_aiFeedbackLiked! ? 'liked' : 'disliked');

    setState(() {
      _isAiSummaryLoading = true;
    });

    final buffer = StringBuffer()
      ..write(recipe.title)
      ..write(' ')
      ..write(recipe.summary ?? '')
      ..write(' 재료: ')
      ..write(recipe.ingredients.join(', '))
      ..write(' 순서: ')
      ..write(recipe.steps.join(' / '));

    try {
      final result = await _aiService.summarizeRecipe(
        buffer.toString(),
        action: normalizedAction,
        title: recipe.title,
        ingredients: recipe.ingredients,
        steps: recipe.steps,
        regenerateReason: regenerateReason,
        previousSummary: previousSummary,
        regenerateAttempt: regenerateAttempt,
        userFeedbackContext: userFeedbackContext,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        if (result.summary.trim().isEmpty) {
          _aiSummaryResult = const AiSummaryResult(
            summary: 'AI 요약 결과가 비어 있습니다.',
            tips: <String>[],
            cautions: <String>[],
            engine: 'unknown',
            degraded: true,
            errorCode: 'empty_summary',
          );
        } else {
          _aiSummaryResult = result;
          _aiFeedbackLiked = null;
          _aiRegenerateAttempt = regenerateAttempt;
        }
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyActionError(err, 'AI 요약 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAiSummaryLoading = false;
        });
      }
    }
  }

  Future<String?> _pickAiRegenerateReason() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const ListTile(
                title: Text('다시 생성 이유를 선택해 주세요'),
                subtitle: Text('선택한 이유는 품질 개선 분석에 활용됩니다.'),
              ),
              ..._aiRegenerateReasons.map((String reason) {
                final label = _aiRegenerateReasonLabels[reason] ?? reason;
                return ListTile(
                  leading: const Icon(Icons.refresh_outlined),
                  title: Text(label),
                  onTap: () => Navigator.of(context).pop(reason),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitAiSummaryFeedback({
    required Recipe recipe,
    required bool liked,
  }) async {
    final result = _aiSummaryResult;
    if (result == null || _isAiFeedbackSubmitting) {
      return;
    }

    setState(() {
      _isAiFeedbackSubmitting = true;
    });

    final ok = await _aiService.submitSummaryFeedback(
      summary: result.summary,
      liked: liked,
      recipeId: recipe.id,
      note: result.errorCode,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isAiFeedbackSubmitting = false;
      if (ok) {
        _aiFeedbackLiked = liked;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'AI 피드백이 저장되었습니다.' : 'AI 피드백 저장에 실패했습니다.'),
      ),
    );
  }

  Future<void> _stopAutoAdvance({
    required List<String> steps,
    required bool stopGuidance,
  }) async {
    _cancelAutoAdvanceTimer();

    if (stopGuidance) {
      await _voiceGuideService.stopGuidance(steps);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _autoAdvanceEnabled = false;
    });
  }

  int _clampStepIndex(int index, int length) {
    if (length <= 0) {
      return 0;
    }

    if (index < 0) {
      return 0;
    }

    if (index >= length) {
      return length - 1;
    }

    return index;
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(
      publicRecipeDetailFallbackProvider(widget.recipeId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('레시피 상세'),
        actions: <Widget>[
          IconButton(
            onPressed: _isBookmarkLoading
                ? null
                : () {
                    recipeAsync.whenData((RecipeFetchResult<Recipe?> result) {
                      final recipe = result.data;
                      if (recipe != null) {
                        _toggleBookmark(recipe);
                      }
                    });
                  },
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
            tooltip: _isBookmarked ? '북마크 해제' : '북마크',
          ),
        ],
      ),
      body: recipeAsync.when(
        data: (RecipeFetchResult<Recipe?> result) {
          if (!result.fromCache && _pendingNetworkRetryAttempts > 0) {
            final attempts = _pendingNetworkRetryAttempts;
            _pendingNetworkRetryAttempts = 0;
            unawaited(
              OpsMonitorService.recordEventCounter(
                'network.retry.recipe_detail.success',
              ),
            );
            if (attempts <= 2) {
              unawaited(
                OpsMonitorService.recordEventCounter(
                  'network.retry.recipe_detail.success_within_2',
                ),
              );
            }
          }
          final recipe = result.data;
          if (recipe == null) {
            return CenteredStateView(
              icon: Icons.search_off,
              title: '레시피를 찾을 수 없습니다',
              message: '삭제되었거나 접근할 수 없는 레시피입니다.',
              actionLabel: '홈으로 이동',
              onAction: () => context.go('/'),
            );
          }

          final guideSnapshot = _voiceGuideService.snapshot(recipe.steps);

          if (_lastStepRestorePending && guideSnapshot.hasSteps) {
            final restoreIndex = _clampStepIndex(
              _savedStepIndex,
              guideSnapshot.totalSteps,
            );
            _lastStepRestorePending = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              if (_autoAdvanceRestorePending) {
                _autoAdvanceRestorePending = false;
                _startAutoAdvance(recipe.steps, fromIndex: restoreIndex);
                return;
              }

              _startGuide(recipe.steps, fromIndex: restoreIndex);
            });
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (result.fromCache)
                NetworkStateBanner(
                  message: result.isStale
                      ? '네트워크 문제로 저장된 예전 상세 데이터를 보여주고 있어요.'
                      : '네트워크 문제로 최근 저장된 상세 데이터를 보여주고 있어요.',
                  cachedAt: result.fetchedAt,
                  kind: NetworkBannerKind.degradedCache,
                  onRetry: () {
                    _pendingNetworkRetryAttempts += 1;
                    unawaited(
                      OpsMonitorService.recordEventCounter(
                        'network.retry.recipe_detail.clicked',
                      ),
                    );
                    ref.invalidate(
                      publicRecipeDetailFallbackProvider(widget.recipeId),
                    );
                  },
                ),
              if ((recipe.imageUrl ?? '').isNotEmpty) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(child: Text('이미지를 불러오지 못했습니다.')),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                recipe.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(recipe.summary ?? '요약 정보가 없습니다.'),
              if ((recipe.youtubeUrl ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                YouTubeLinkCard(youtubeUrl: recipe.youtubeUrl!),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: recipe.steps.isEmpty
                      ? null
                      : () => context.push('/quick-cook/${recipe.id}'),
                  icon: const Icon(Icons.restaurant_menu_outlined),
                  label: const Text('바로 요리 시작'),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _isAiSummaryLoading
                      ? null
                      : () => _generateAiSummary(recipe),
                  icon: _isAiSummaryLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label:
                      Text(_isAiSummaryLoading ? 'AI 요약 생성 중...' : 'AI 요약 생성'),
                ),
              ),
              if (_aiSummaryResult != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F8F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFE1D7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _aiSummaryResult!.summary,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_aiSummaryResult!.degraded) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          '안정화 모드 응답입니다. (${_aiSummaryResult!.errorCode ?? 'degraded'})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_aiSummaryResult!.tips.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '추천 팁',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        ..._aiSummaryResult!.tips.map(
                          (String tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text('• $tip'),
                          ),
                        ),
                      ],
                      if (_aiSummaryResult!.cautions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '주의사항',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        ..._aiSummaryResult!.cautions.map(
                          (String caution) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text('• $caution'),
                          ),
                        ),
                      ],
                      if (_aiSummaryResult!.engine.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'engine: ${_aiSummaryResult!.engine}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _isAiSummaryLoading
                              ? null
                              : () async {
                                  final reason =
                                      await _pickAiRegenerateReason();
                                  if (reason == null || !mounted) {
                                    return;
                                  }
                                  recipeAsync.whenData(
                                    (RecipeFetchResult<Recipe?> latestResult) {
                                      final latest = latestResult.data;
                                      if (latest != null) {
                                        _generateAiSummary(
                                          latest,
                                          action: 'regenerate',
                                          regenerateReason: reason,
                                        );
                                      }
                                    },
                                  );
                                },
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('다시 생성'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: const Text('도움 됐어요'),
                            selected: _aiFeedbackLiked == true,
                            onSelected: _isAiFeedbackSubmitting
                                ? null
                                : (_) => _submitAiSummaryFeedback(
                                      recipe: recipe,
                                      liked: true,
                                    ),
                          ),
                          ChoiceChip(
                            label: const Text('아쉬워요'),
                            selected: _aiFeedbackLiked == false,
                            onSelected: _isAiFeedbackSubmitting
                                ? null
                                : (_) => _submitAiSummaryFeedback(
                                      recipe: recipe,
                                      liked: false,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => _copyToMyRecipes(recipe),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('내 레시피로 복사'),
                    ),
                      FilledButton.icon(
                        onPressed: () => _createShoppingListFromRecipe(recipe),
                        icon: const Icon(Icons.shopping_cart_checkout_outlined),
                        label: const Text('장보기 리스트 만들기'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('재료', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (recipe.ingredients.isEmpty)
                const Text('등록된 재료 정보가 없습니다.')
              else
                ...recipe.ingredients.map(
                  (String item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $item'),
                  ),
                ),
              const SizedBox(height: 20),
              Text('조리 순서', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (recipe.steps.isEmpty)
                const Text('등록된 조리 순서가 없습니다.')
              else
                ...recipe.steps.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${entry.key + 1}. ${entry.value}'),
                      ),
                    ),
              const SizedBox(height: 20),
              Text('조리 완료 피드백', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: const Text('좋아요'),
                            selected: _cookLiked == true,
                            onSelected: (bool selected) {
                              setState(() {
                                _cookLiked = selected ? true : null;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('아쉬워요'),
                            selected: _cookLiked == false,
                            onSelected: (bool selected) {
                              setState(() {
                                _cookLiked = selected ? false : null;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '평점 (선택)',
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _cookRating,
                            isExpanded: true,
                            hint: const Text('평점을 선택하세요'),
                            items: const <DropdownMenuItem<int>>[
                              DropdownMenuItem<int>(
                                  value: 1, child: Text('1점')),
                              DropdownMenuItem<int>(
                                  value: 2, child: Text('2점')),
                              DropdownMenuItem<int>(
                                  value: 3, child: Text('3점')),
                              DropdownMenuItem<int>(
                                  value: 4, child: Text('4점')),
                              DropdownMenuItem<int>(
                                  value: 5, child: Text('5점')),
                            ],
                            onChanged: (int? value) {
                              setState(() {
                                _cookRating = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cookNoteController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '한 줄 메모 (선택)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _completeCookSession(recipe),
                          icon: const Icon(Icons.task_alt),
                          label: const Text('조리 완료 기록'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showVoiceGuideSection) ...<Widget>[
                const SizedBox(height: 20),
                Text('음성 가이드', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          guideSnapshot.hasSteps
                              ? '현재 단계 ${guideSnapshot.currentStepIndex + 1}/${guideSnapshot.totalSteps}'
                              : '안내할 조리 단계가 없습니다.',
                        ),
                        if (guideSnapshot.hasSteps) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            guideSnapshot.currentStepText,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: !guideSnapshot.hasSteps ||
                                      guideSnapshot.isFirstStep
                                  ? null
                                  : () async {
                                      if (_autoAdvanceEnabled) {
                                        await _stopAutoAdvance(
                                          steps: recipe.steps,
                                          stopGuidance: false,
                                        );
                                      }
                                      await _previousStep(recipe.steps);
                                    },
                              icon: const Icon(Icons.skip_previous),
                              label: const Text('이전'),
                            ),
                            FilledButton.icon(
                              onPressed: !guideSnapshot.hasSteps
                                  ? null
                                  : () async {
                                      if (_autoAdvanceEnabled) {
                                        await _stopAutoAdvance(
                                          steps: recipe.steps,
                                          stopGuidance: false,
                                        );
                                      }
                                      await _startGuide(
                                        recipe.steps,
                                        fromIndex: guideSnapshot.currentStepIndex,
                                      );
                                    },
                              icon: Icon(
                                guideSnapshot.isPlaying
                                    ? Icons.replay
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                guideSnapshot.isPlaying ? '다시 듣기' : '시작',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: !guideSnapshot.hasSteps ||
                                      guideSnapshot.isLastStep
                                  ? null
                                  : () async {
                                      if (_autoAdvanceEnabled) {
                                        await _stopAutoAdvance(
                                          steps: recipe.steps,
                                          stopGuidance: false,
                                        );
                                      }
                                      await _nextStep(recipe.steps);
                                    },
                              icon: const Icon(Icons.skip_next),
                              label: const Text('다음'),
                            ),
                            OutlinedButton.icon(
                              onPressed: !guideSnapshot.isPlaying
                                  ? null
                                  : () async {
                                      await _stopAutoAdvance(
                                        steps: recipe.steps,
                                        stopGuidance: true,
                                      );
                                    },
                              icon: const Icon(Icons.stop),
                              label: const Text('정지'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '자동 재생 (단계당 $_autoAdvanceSeconds초)',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Switch.adaptive(
                              value: _autoAdvanceEnabled ||
                                  _autoAdvanceRestorePending,
                              onChanged: guideSnapshot.hasSteps
                                  ? (bool enabled) async {
                                      await _setAutoAdvance(
                                          enabled, recipe.steps);
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _autoAdvanceSecondOptions
                              .map(
                                (int seconds) => ChoiceChip(
                                  label: Text('$seconds초'),
                                  selected: _autoAdvanceSeconds == seconds,
                                  onSelected: (bool selected) async {
                                    if (!selected) {
                                      return;
                                    }

                                    if (_autoAdvanceSeconds == seconds) {
                                      return;
                                    }

                                    setState(() {
                                      _autoAdvanceSeconds = seconds;
                                    });

                                    await _persistAutoAdvanceSeconds(seconds);

                                    if (_autoAdvanceEnabled) {
                                      await _stopAutoAdvance(
                                        steps: recipe.steps,
                                        stopGuidance: false,
                                      );
                                      await _startAutoAdvance(recipe.steps);
                                    }
                                  },
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '현재 빌드에서는 TTS 출력이 비활성화되어 단계 상태만 갱신됩니다. 자동 재생은 단계 인덱스만 순차적으로 이동합니다.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
        error: (Object err, StackTrace stack) => CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '상세를 불러오지 못했습니다',
          message: _friendlyActionError(err, '잠시 후 다시 시도해 주세요.'),
          actionLabel: '다시 시도',
          onAction: () {
            _pendingNetworkRetryAttempts += 1;
            unawaited(
              OpsMonitorService.recordEventCounter(
                'network.retry.recipe_detail.clicked',
              ),
            );
            ref.invalidate(publicRecipeDetailFallbackProvider(widget.recipeId));
            _loadBookmarkState();
          },
          secondaryActionLabel: '홈으로 이동',
          onSecondaryAction: () => context.go('/'),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('레시피 상세를 불러오는 중입니다...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
