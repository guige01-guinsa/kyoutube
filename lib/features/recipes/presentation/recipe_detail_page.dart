import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_providers.dart';
import '../../cooking/application/voice_guide_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
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
  static const String _lastStepIndexPrefKeyPrefix =
      'cooking.last_step_index';

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
  final TextEditingController _cookNoteController = TextEditingController();

  Duration get _autoAdvanceInterval => Duration(seconds: _autoAdvanceSeconds);

  bool _isSessionProblem(Object error) {
    final message = error.toString();
    return message.contains('로그인이 필요합니다') ||
        message.contains('다시 로그인해 주세요');
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

  void _redirectToLoginIfNeeded(Object error) {
    if (_isSessionProblem(error) && mounted) {
      context.push('/login');
    }
  }

  String get _lastStepIndexPrefKey =>
      '$_lastStepIndexPrefKeyPrefix.${widget.recipeId}';

  @override
  void initState() {
    super.initState();
    _restoreAutoAdvancePreferences();
    _loadBookmarkState();
  }

  @override
  void dispose() {
    _cancelAutoAdvanceTimer();
    ref.read(voiceGuideServiceProvider).stop();
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

    final snapshot = ref.read(voiceGuideServiceProvider).snapshot(steps);
    if (!snapshot.hasSteps) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastStepIndexPrefKey, snapshot.currentStepIndex);
  }

  Future<void> _startGuide(List<String> steps, {int? fromIndex}) async {
    final service = ref.read(voiceGuideServiceProvider);
    await service.start(steps, fromIndex: fromIndex);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _nextStep(List<String> steps) async {
    final service = ref.read(voiceGuideServiceProvider);
    await service.next(steps);
    await _persistCurrentStepIndex(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _previousStep(List<String> steps) async {
    final service = ref.read(voiceGuideServiceProvider);
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
      context.push('/login');
      return;
    }

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
        context.push('/login');
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
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBookmarkLoading = false;
        _isBookmarked = false;
      });
      return;
    }

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
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push('/login');
      return;
    }

    setState(() {
      _isBookmarkLoading = true;
    });

    try {
      final repository = ref.read(recipeRepositoryProvider);
      if (_isBookmarked) {
        await repository.removeBookmark(recipeType: 'public', recipeId: recipe.id);
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
        SnackBar(content: Text(_isBookmarked ? '북마크에 저장했습니다.' : '북마크를 해제했습니다.')),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        context.push('/login');
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

  Future<void> _addMissingIngredientsToShopping(Recipe recipe) async {
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push('/login');
      return;
    }

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
      final missingCount = await repository.createKitchenShoppingFromRecipe(
        recipeType: 'public',
        recipe: recipe,
      );
      ref.invalidate(kitchenSummaryProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('장보기 목록을 만들었습니다. 부족 재료 $missingCount개'),
          action: SnackBarAction(
            label: '장보기 열기',
            onPressed: () {
              context.push('/kitchen?tab=shopping');
            },
          ),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      if (_isSessionProblem(err)) {
        context.push('/login');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyActionError(err, '장보기 목록 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }

  Future<void> _completeCookSession(Recipe recipe) async {
    final currentUser = ref.read(authUserProvider).valueOrNull;
    if (currentUser == null) {
      if (!mounted) {
        return;
      }
      context.push('/login');
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

      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenCookSessionsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('조리 완료 기록을 저장했습니다.'),
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
        context.push('/login');
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
    final service = ref.read(voiceGuideServiceProvider);
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
      await ref.read(voiceGuideServiceProvider).stopGuidance(steps);
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
    final currentUser = ref.watch(authUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
          title: const Text('레시피 상세'),
        actions: <Widget>[
          IconButton(
            onPressed: _isBookmarkLoading
                ? null
                : () {
                    recipeAsync.whenData((Recipe? recipe) {
                      if (recipe != null) {
                        _toggleBookmark(recipe);
                      }
                    });
                  },
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
            tooltip: currentUser == null
                ? '로그인 후 북마크 가능'
                : (_isBookmarked ? '북마크 해제' : '북마크'),
          ),
        ],
      ),
      body: recipeAsync.when(
        data: (Recipe? recipe) {
          if (recipe == null) {
            return CenteredStateView(
              icon: Icons.search_off,
              title: '레시피를 찾을 수 없습니다',
              message: '삭제되었거나 접근할 수 없는 레시피입니다.',
              actionLabel: '홈으로 이동',
              onAction: () => context.go('/'),
            );
          }

          final guideSnapshot = ref
              .read(voiceGuideServiceProvider)
              .snapshot(recipe.steps);

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
                    OutlinedButton.icon(
                      onPressed: () => _addMissingIngredientsToShopping(recipe),
                      icon: const Icon(Icons.shopping_cart_checkout_outlined),
                      label: const Text('부족 재료 장보기 추가'),
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
                              DropdownMenuItem<int>(value: 1, child: Text('1점')),
                              DropdownMenuItem<int>(value: 2, child: Text('2점')),
                              DropdownMenuItem<int>(value: 3, child: Text('3점')),
                              DropdownMenuItem<int>(value: 4, child: Text('4점')),
                              DropdownMenuItem<int>(value: 5, child: Text('5점')),
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
                            value:
                                _autoAdvanceEnabled || _autoAdvanceRestorePending,
                            onChanged: guideSnapshot.hasSteps
                                ? (bool enabled) async {
                                    await _setAutoAdvance(enabled, recipe.steps);
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
          );
        },
        error: (Object err, StackTrace stack) => CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '상세를 불러오지 못했습니다',
          message: _friendlyActionError(err, '잠시 후 다시 시도해 주세요.'),
          actionLabel: '다시 시도',
          onAction: () {
            ref.invalidate(recipeByIdProvider(widget.recipeId));
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
