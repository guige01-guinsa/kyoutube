import '../../../core/auth/auth_return.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import 'widgets/recipe_reading_sections.dart';
import '../../auth/application/auth_providers.dart';
import '../../cooking/application/voice_guide_providers.dart';
import '../../cooking/application/voice_guide_service.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../domain/recipe.dart';

class RecipeDetailPage extends ConsumerStatefulWidget {
  const RecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends ConsumerState<RecipeDetailPage> {
  static const List<int> _autoAdvanceSecondOptions = <int>[3, 5, 8];
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
  int _autoAdvanceSeconds = 5;
  int _savedStepIndex = 0;
  int? _cookRating;
  bool? _cookLiked;
  final TextEditingController _cookNoteController = TextEditingController();
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
      return '로그인 상태를 다시 확인해 주세요.';
    }

    if (_isNetworkProblem(error)) {
      return '네트워크 연결을 확인해 주세요.';
    }

    return fallback;
  }

  String get _lastStepIndexPrefKey =>
      '$_lastStepIndexPrefKeyPrefix.${widget.recipeId}';

  @override
  void initState() {
    super.initState();
    _voiceGuideService = ref.read(voiceGuideServiceProvider);
    _restoreAutoAdvancePreferences();
  }

  @override
  void dispose() {
    _cancelAutoAdvanceTimer();
    unawaited(_voiceGuideService.stop());
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
    if (!mounted) {
      return;
    }

    final snapshot = _voiceGuideService.snapshot(steps);
    if (!snapshot.hasSteps) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastStepIndexPrefKey, snapshot.currentStepIndex);
  }

  Future<void> _startGuide(List<String> steps, {int? fromIndex}) async {
    final service = _voiceGuideService;
    await service.start(steps, fromIndex: fromIndex);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _nextStep(List<String> steps) async {
    final service = _voiceGuideService;
    await service.next(steps);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _previousStep(List<String> steps) async {
    final service = _voiceGuideService;
    await service.previous(steps);
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
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
      return;
    }

    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.createSubscriberRecipeFromPublic(source: recipe);
      if (!mounted) {
        return;
      }

      // 기존 개인 레시피 목록과 통합 내 레시피 목록을 함께 갱신한다.
      ref.invalidate(subscriberRecipesProvider);
      ref.invalidate(myUnifiedRecipesProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const LocalizedText('내 레시피에 저장했습니다.'),
          action: SnackBarAction(
            label: '내 레시피 관리',
            onPressed: () {
              context.go('/my-recipes');
            },
          ),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            _friendlyActionError(err, '복사에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }

  Future<void> _addMissingIngredientsToShopping(Recipe recipe) async {
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
      return;
    }

    if (recipe.ingredients.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('재료 정보가 없어 장보기 목록을 만들 수 없습니다.')),
      );
      return;
    }

    if (!mounted) return;
    final source = Uri.encodeComponent('public:${recipe.id}');
    context.push('/shopping-review?source=$source');
  }

  Future<void> _completeCookSession(Recipe recipe) async {
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
      return;
    }

    try {
      await ref.read(kitchenApiProvider).completeCook(
            recipeType: 'public',
            recipeId: recipe.id,
            recipeTitle: recipe.title,
            rating: _cookRating,
            liked: _cookLiked,
            note: _cookNoteController.text,
          );

      if (!mounted) {
        return;
      }
      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenCookSessionsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const LocalizedText('조리 완료 기록을 저장했습니다.'),
          action: SnackBarAction(
            label: '히스토리 보기',
            onPressed: () {
              context.push('/kitchen?tab=history');
            },
          ),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            _friendlyActionError(err, '조리 완료 기록 저장에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }

  Future<void> _startAutoAdvance(List<String> steps, {int? fromIndex}) async {
    final service = _voiceGuideService;
    final snapshot = service.snapshot(steps);

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
        final currentSnapshot = service.snapshot(steps);

        if (!currentSnapshot.hasSteps || currentSnapshot.isLastStep) {
          await service.stopGuidance(steps);
          _cancelAutoAdvanceTimer();
          if (mounted) {
            setState(() {
              _autoAdvanceEnabled = false;
            });
          }
          return;
        }

        await service.next(steps);
        await _persistCurrentStepIndex(steps);
        if (mounted) {
          setState(() {});
        }
      } finally {
        _autoTickInProgress = false;
      }
    });
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
    final recipeAsync = ref.watch(recipeByIdProvider(widget.recipeId));

    return Scaffold(
      appBar: AppBar(title: const LocalizedText('레시피 상세')),
      body: recipeAsync.when(
        data: (Recipe? recipe) {
          if (recipe == null) {
            return CenteredStateView(
              icon: Icons.search_off,
              title: '레시피를 찾을 수 없습니다',
              message: '삭제되었거나 접근할 수 없는 레시피입니다.',
              actionLabel: context.tr('홈으로 이동'),
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

          return Center(
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      RecipeOverview(recipe: recipe),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: () => _copyToMyRecipes(recipe),
                              icon: const Icon(Icons.library_add_outlined),
                              label: const LocalizedText('내 레시피로 복사'),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  _addMissingIngredientsToShopping(recipe),
                              icon: const Icon(
                                  Icons.shopping_cart_checkout_outlined),
                              label: const LocalizedText(
                                  '\uC7A5\uBCF4\uAE30\uC900\uBE44'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      RecipeIngredientsSection(ingredients: recipe.ingredients),
                      const SizedBox(height: 28),
                      RecipeStepsSection(steps: recipe.steps),
                      const SizedBox(height: 24),
                      LocalizedText('단계 안내',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              LocalizedText(
                                guideSnapshot.hasSteps
                                    ? '현재 단계 ${guideSnapshot.currentStepIndex + 1}/${guideSnapshot.totalSteps}'
                                    : '안내할 조리 단계가 없습니다.',
                              ),
                              if (guideSnapshot.hasSteps) ...<Widget>[
                                const SizedBox(height: 8),
                                LocalizedText(
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
                                    label: const LocalizedText('이전'),
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
                                              fromIndex: guideSnapshot
                                                  .currentStepIndex,
                                            );
                                          },
                                    icon: Icon(
                                      guideSnapshot.isPlaying
                                          ? Icons.replay
                                          : Icons.play_arrow,
                                    ),
                                    label: LocalizedText(
                                      guideSnapshot.isPlaying
                                          ? '단계 다시 보기'
                                          : '안내 시작',
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
                                    label: const LocalizedText('다음'),
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
                                    label: const LocalizedText('정지'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: LocalizedText(
                                      '자동 재생 (단계당 $_autoAdvanceSeconds초)',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
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
                                        label: LocalizedText('$seconds초'),
                                        selected:
                                            _autoAdvanceSeconds == seconds,
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

                                          await _persistAutoAdvanceSeconds(
                                              seconds);

                                          if (_autoAdvanceEnabled) {
                                            await _stopAutoAdvance(
                                              steps: recipe.steps,
                                              stopGuidance: false,
                                            );
                                            await _startAutoAdvance(
                                                recipe.steps);
                                          }
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 8),
                              LocalizedText(
                                '소리 없이 조리 단계를 안내해요. 자동 진행을 켜면 선택한 간격으로 다음 단계로 이동합니다.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      LocalizedText('조리 완료 피드백',
                          style: Theme.of(context).textTheme.titleMedium),
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
                                    label: const LocalizedText('좋아요'),
                                    selected: _cookLiked == true,
                                    onSelected: (bool selected) {
                                      setState(() {
                                        _cookLiked = selected ? true : null;
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const LocalizedText('아쉬워요'),
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
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: context.tr('평점 (선택)'),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _cookRating,
                                    isExpanded: true,
                                    hint: const LocalizedText('평점을 선택하세요'),
                                    items: const <DropdownMenuItem<int>>[
                                      DropdownMenuItem<int>(
                                          value: 1, child: LocalizedText('1점')),
                                      DropdownMenuItem<int>(
                                          value: 2, child: LocalizedText('2점')),
                                      DropdownMenuItem<int>(
                                          value: 3, child: LocalizedText('3점')),
                                      DropdownMenuItem<int>(
                                          value: 4, child: LocalizedText('4점')),
                                      DropdownMenuItem<int>(
                                          value: 5, child: LocalizedText('5점')),
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
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: context.tr('한 줄 메모 (선택)'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: () => _completeCookSession(recipe),
                                  icon: const Icon(Icons.task_alt),
                                  label: const LocalizedText('조리 완료 기록'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  )));
        },
        error: (Object err, StackTrace stack) => CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '상세를 불러오지 못했습니다',
          message: _friendlyActionError(err, '잠시 후 다시 시도해 주세요.'),
          actionLabel: context.tr('다시 시도'),
          onAction: () {
            ref.invalidate(recipeByIdProvider(widget.recipeId));
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
                LocalizedText('레시피 상세를 불러오는 중입니다...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
