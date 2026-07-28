import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ops/ops_monitor_service.dart';
import '../../../core/widgets/network_state_banner.dart';
import '../../recipes/application/recipe_network_fallback.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../application/voice_guide_providers.dart';
import '../application/voice_guide_service.dart';

class QuickCookPage extends ConsumerStatefulWidget {
  const QuickCookPage({
    super.key,
    required this.recipeId,
    this.sourceType = 'public',
  });

  final String recipeId;
  final String sourceType;

  @override
  ConsumerState<QuickCookPage> createState() => _QuickCookPageState();
}

class _QuickCookPageState extends ConsumerState<QuickCookPage> {
  static const List<int> _autoAdvanceSecondOptions = <int>[3, 5, 8];

  Timer? _autoAdvanceTimer;
  bool _autoTickInProgress = false;
  bool _autoAdvanceEnabled = false;
  int _autoAdvanceSeconds = 5;
  int _pendingNetworkRetryAttempts = 0;
  late final VoiceGuideService _voiceGuideService;

  Duration get _autoAdvanceInterval => Duration(seconds: _autoAdvanceSeconds);

  @override
  void initState() {
    super.initState();
    _voiceGuideService = ref.read(voiceGuideServiceProvider);
  }

  @override
  void dispose() {
    _cancelAutoAdvanceTimer();
    _voiceGuideService.stop();
    super.dispose();
  }

  void _cancelAutoAdvanceTimer() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  Future<void> _startGuide(List<String> steps, {int? fromIndex}) async {
    await _voiceGuideService.start(steps, fromIndex: fromIndex);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _nextStep(List<String> steps) async {
    await _voiceGuideService.next(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _previousStep(List<String> steps) async {
    await _voiceGuideService.previous(steps);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _setAutoAdvance(bool enabled, List<String> steps) async {
    if (enabled) {
      await _startAutoAdvance(steps);
      return;
    }

    _cancelAutoAdvanceTimer();
    if (!mounted) {
      return;
    }

    setState(() {
      _autoAdvanceEnabled = false;
    });
  }

  Future<void> _startAutoAdvance(List<String> steps, {int? fromIndex}) async {
    final snapshot = _voiceGuideService.snapshot(steps);

    if (!snapshot.hasSteps) {
      return;
    }

    _cancelAutoAdvanceTimer();
    await _startGuide(steps, fromIndex: fromIndex ?? snapshot.currentStepIndex);
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
        final current = _voiceGuideService.snapshot(steps);
        if (!current.hasSteps || current.isLastStep) {
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
        if (mounted) {
          setState(() {});
        }
      } finally {
        _autoTickInProgress = false;
      }
    });
  }

  Future<bool> _confirmExitIfNeeded(List<String> steps) async {
    final snapshot = _voiceGuideService.snapshot(steps);
    if (!snapshot.hasSteps || snapshot.currentStepIndex == 0) {
      return true;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('요리 모드를 종료할까요?'),
          content: const Text('현재 진행 단계가 있어요. 종료하면 집중 모드를 나가게 됩니다.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('계속 진행'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('종료'),
            ),
          ],
        );
      },
    );

    return shouldExit ?? false;
  }

  Widget _stepCard(Recipe recipe) {
    final snapshot = _voiceGuideService.snapshot(recipe.steps);

    if (!snapshot.hasSteps) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('등록된 조리 순서가 없습니다.'),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'STEP ${snapshot.currentStepIndex + 1}/${snapshot.totalSteps}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (snapshot.isPlaying)
                  const Chip(
                    avatar: Icon(Icons.graphic_eq, size: 16),
                    label: Text('가이드 재생 중'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              snapshot.currentStepText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: snapshot.isFirstStep
                      ? null
                      : () => _previousStep(recipe.steps),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('이전'),
                ),
                FilledButton.icon(
                  onPressed: snapshot.isLastStep
                      ? null
                      : () => _nextStep(recipe.steps),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('다음'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _startGuide(
                    recipe.steps,
                    fromIndex: snapshot.currentStepIndex,
                  ),
                  icon: const Icon(Icons.replay),
                  label: const Text('다시 읽기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCreatorSource = widget.sourceType == 'creator';
    final recipeAsync = isCreatorSource
        ? null
        : ref.watch(publicRecipeDetailFallbackProvider(widget.recipeId));
    final creatorRecipeAsync = isCreatorSource
        ? ref.watch(creatorRecipeByIdProvider(widget.recipeId))
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) {
          return;
        }

        final recipe = recipeAsync?.valueOrNull?.data;
        final creatorRecipe = creatorRecipeAsync?.valueOrNull;
        final currentRecipe = recipe ?? creatorRecipe;
        if (currentRecipe == null) {
          if (mounted) {
            Navigator.of(this.context).pop();
          }
          return;
        }

        final allowExit = await _confirmExitIfNeeded(currentRecipe.steps);
        if (!mounted || !allowExit) {
          return;
        }

        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('바로 요리 모드'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final recipe = recipeAsync?.valueOrNull;
              final data = recipe?.data ?? creatorRecipeAsync?.valueOrNull;
              if (data == null) {
                if (mounted) {
                  Navigator.of(this.context).pop();
                }
                return;
              }

              final allowExit = await _confirmExitIfNeeded(data.steps);
              if (!mounted || !allowExit) {
                return;
              }

              Navigator.of(this.context).pop();
            },
          ),
        ),
        body: isCreatorSource
            ? creatorRecipeAsync!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object err, StackTrace _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: NetworkStateBanner(
                      message: '레시피를 불러오지 못했습니다. 네트워크를 확인해 주세요.',
                      kind: NetworkBannerKind.serverError,
                      onRetry: () {
                        ref.invalidate(creatorRecipeByIdProvider(widget.recipeId));
                      },
                    ),
                  ),
                ),
                data: (Recipe? recipe) {
                  if (recipe == null) {
                    return const Center(child: Text('레시피를 찾을 수 없습니다.'));
                  }

                  final snapshot = _voiceGuideService.snapshot(recipe.steps);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(
                        recipe.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '화면이 꺼지지 않도록 유지됩니다. 순서대로 집중해서 조리해 보세요.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<int>(
                        segments: _autoAdvanceSecondOptions
                            .map(
                              (int seconds) => ButtonSegment<int>(
                                value: seconds,
                                label: Text('${seconds}s'),
                              ),
                            )
                            .toList(),
                        selected: <int>{_autoAdvanceSeconds},
                        onSelectionChanged: (Set<int> value) {
                          if (value.isEmpty) {
                            return;
                          }
                          setState(() {
                            _autoAdvanceSeconds = value.first;
                          });
                          if (_autoAdvanceEnabled) {
                            _startAutoAdvance(
                              recipe.steps,
                              fromIndex: snapshot.currentStepIndex,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilterChip(
                          label: Text(
                            _autoAdvanceEnabled ? '자동 진행 켜짐' : '자동 진행 꺼짐',
                          ),
                          selected: _autoAdvanceEnabled,
                          onSelected: (_) => _setAutoAdvance(
                            !_autoAdvanceEnabled,
                            recipe.steps,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _stepCard(recipe),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('원본 상세 화면으로 돌아가기'),
                      ),
                    ],
                  );
                },
              )
            : recipeAsync!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object err, StackTrace _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: NetworkStateBanner(
                      message: err is RecipeNetworkFallbackException
                          ? err.message
                          : '레시피를 불러오지 못했습니다. 네트워크를 확인해 주세요.',
                      kind: NetworkBannerKind.serverError,
                      onRetry: () {
                        _pendingNetworkRetryAttempts += 1;
                        unawaited(
                          OpsMonitorService.recordEventCounter(
                            'network.retry.quick_cook.clicked',
                          ),
                        );
                        ref.invalidate(
                          publicRecipeDetailFallbackProvider(widget.recipeId),
                        );
                      },
                    ),
                  ),
                ),
                data: (RecipeFetchResult<Recipe?> result) {
            if (!result.fromCache && _pendingNetworkRetryAttempts > 0) {
              final attempts = _pendingNetworkRetryAttempts;
              _pendingNetworkRetryAttempts = 0;
              unawaited(
                OpsMonitorService.recordEventCounter(
                  'network.retry.quick_cook.success',
                ),
              );
              if (attempts <= 2) {
                unawaited(
                  OpsMonitorService.recordEventCounter(
                    'network.retry.quick_cook.success_within_2',
                  ),
                );
              }
            }
            final recipe = result.data;
            if (recipe == null) {
              return const Center(child: Text('레시피를 찾을 수 없습니다.'));
            }

            final snapshot = _voiceGuideService.snapshot(recipe.steps);

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
                          'network.retry.quick_cook.clicked',
                        ),
                      );
                      ref.invalidate(
                        publicRecipeDetailFallbackProvider(widget.recipeId),
                      );
                    },
                  ),
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '화면이 꺼지지 않도록 유지됩니다. 순서대로 집중해서 조리해 보세요.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                SegmentedButton<int>(
                  segments: _autoAdvanceSecondOptions
                      .map(
                        (int seconds) => ButtonSegment<int>(
                          value: seconds,
                          label: Text('${seconds}s'),
                        ),
                      )
                      .toList(),
                  selected: <int>{_autoAdvanceSeconds},
                  onSelectionChanged: (Set<int> value) {
                    if (value.isEmpty) {
                      return;
                    }
                    setState(() {
                      _autoAdvanceSeconds = value.first;
                    });
                    if (_autoAdvanceEnabled) {
                      _startAutoAdvance(
                        recipe.steps,
                        fromIndex: snapshot.currentStepIndex,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: Text(
                      _autoAdvanceEnabled ? '자동 진행 켜짐' : '자동 진행 꺼짐',
                    ),
                    selected: _autoAdvanceEnabled,
                    onSelected: (_) => _setAutoAdvance(
                      !_autoAdvanceEnabled,
                      recipe.steps,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _stepCard(recipe),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('원본 상세 화면으로 돌아가기'),
                ),
              ],
            );
                },
              ),
      ),
    );
  }
}
