import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;

import '../../../core/ops/ops_monitor_service.dart';
import '../../onboarding/application/onboarding_state.dart';
import '../../recipes/application/recipe_network_fallback.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/application/youtube_search_providers.dart';
import '../../recipes/data/youtube_search_service.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/youtube_search_result.dart';
import '../../recipes/presentation/recipe_thumbnail.dart';

enum _SearchSource {
  public,
  youtube,
}

class _YoutubeImportDraft {
  const _YoutubeImportDraft({
    required this.title,
    this.summary,
    required this.ingredients,
    required this.steps,
    this.notes,
  });

  final String title;
  final String? summary;
  final List<String> ingredients;
  final List<String> steps;
  final String? notes;
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    this.initialSearchSource = 'public',
  });

  final String initialSearchSource;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const int _publicSearchVisibleMax = 9;

  String _searchQuery = '';
  bool _useAiSearch = false;
  _SearchSource _searchSource = _SearchSource.public;
  bool _onboardingChecked = false;
  int _publicSearchVisibleCount = _publicSearchVisibleMax;

  List<String> _splitLines(String value) {
    return value
        .split(RegExp(r'[\r\n,]+'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchSource == 'youtube') {
      _searchSource = _SearchSource.youtube;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureOnboardingFlow();
    });
  }

  Future<void> _ensureOnboardingFlow() async {
    if (_onboardingChecked) {
      return;
    }

    _onboardingChecked = true;
    final completed = await OnboardingState.isCompleted();
    if (!mounted || completed) {
      return;
    }

    context.go('/onboarding?returnTo=%2F');
  }

  Future<void> _openYoutube(BuildContext context, String youtubeUrl) async {
    await OpsMonitorService.recordEventCounter('youtube.result.open.clicked');

    final uri = Uri.tryParse(youtubeUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      await OpsMonitorService.recordEventCounter(
        'youtube.result.open.invalid_url',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효한 YouTube 링크가 아닙니다.')),
        );
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await OpsMonitorService.recordEventCounter('youtube.result.open.failed');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했습니다.')),
      );
      return;
    }

    await OpsMonitorService.recordEventCounter('youtube.result.open.success');
  }

  Future<void> _importYoutubeToMyRecipes(
    BuildContext context,
    YoutubeSearchResult item,
  ) async {
    await OpsMonitorService.recordEventCounter('youtube.import.clicked');
    if (!context.mounted) {
      return;
    }

    final draft = await _showYoutubeImportEditor(context, item);
    if (draft == null) {
      await OpsMonitorService.recordEventCounter('youtube.import.canceled');
      return;
    }

    final repository = ref.read(recipeRepositoryProvider);

    try {
      final created = await repository.createSubscriberRecipe(
        title: draft.title,
        summary: draft.summary,
        ingredients: draft.ingredients,
        steps: draft.steps,
        notes: draft.notes,
        youtubeUrl: item.youtubeUrl,
        sourceType: RecipeSourceType.youtubeImport,
      );

      ref.invalidate(subscriberRecipesProvider);
      await OpsMonitorService.recordEventCounter('youtube.import.completed');

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('YouTube 결과를 편집 후 내 요리 노트로 저장했습니다.'),
          action: SnackBarAction(
            label: '열기',
            onPressed: () {
              context.push('/my-recipes/${created.id}');
            },
          ),
        ),
      );
    } catch (error) {
      await OpsMonitorService.recordEventCounter('youtube.import.failed');
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('가져오기에 실패했습니다.\n$error')),
      );
    }
  }

  String _youtubeSearchErrorMessage(Object err) {
    if (err is YoutubeSearchException) {
      switch (err.code) {
        case 'invalid_query':
          return '검색어를 다시 확인해 주세요.';
        case 'quota_exceeded':
          return 'YouTube 검색 사용량 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.';
        case 'upstream_timeout':
          return 'YouTube 응답이 지연되고 있습니다. 다시 시도해 주세요.';
        case 'upstream_error':
          return 'YouTube 검색 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
        case 'invalid_response':
          return '검색 응답 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
        case 'misconfigured':
          return '검색 기능 설정이 올바르지 않습니다. 관리자에게 문의해 주세요.';
        case 'internal_error':
          return '검색 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      }
    }

    return 'YouTube 검색 결과를 불러오지 못했습니다.';
  }

  Future<_YoutubeImportDraft?> _showYoutubeImportEditor(
    BuildContext context,
    YoutubeSearchResult item,
  ) async {
    final titleController = TextEditingController(text: item.title);
    final summaryController = TextEditingController(
      text: item.channelTitle.isEmpty ? '' : '${item.channelTitle} 영상 기반 레시피',
    );
    final ingredientsController = TextEditingController();
    final stepsController = TextEditingController();
    final notesController = TextEditingController(text: item.youtubeUrl);
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<_YoutubeImportDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 16),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'YouTube 레시피 가져오기',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '제목',
                        border: OutlineInputBorder(),
                      ),
                      validator: (String? value) {
                        if ((value ?? '').trim().isEmpty) {
                          return '제목을 입력해 주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: summaryController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '요약(선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: ingredientsController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '재료(선택)',
                        hintText: '한 줄에 하나 또는 쉼표로 구분',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: stepsController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: '조리 순서(선택)',
                        hintText: '한 줄에 하나 또는 쉼표로 구분',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '메모(선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('취소'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            if (formKey.currentState?.validate() != true) {
                              return;
                            }
                            Navigator.of(context).pop(
                              _YoutubeImportDraft(
                                title: titleController.text.trim(),
                                summary: summaryController.text.trim().isEmpty
                                    ? null
                                    : summaryController.text.trim(),
                                ingredients: _splitLines(ingredientsController.text),
                                steps: _splitLines(stepsController.text),
                                notes: notesController.text.trim().isEmpty
                                    ? null
                                    : notesController.text.trim(),
                              ),
                            );
                          },
                          child: const Text('저장'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildYoutubeResults(BuildContext context, AsyncValue<List<YoutubeSearchResult>> async) {
    return async.when(
      data: (List<YoutubeSearchResult> items) {
        if (_searchQuery.trim().isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('YouTube 검색어를 입력해 주세요.'),
            ),
          );
        }

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('YouTube 검색 결과가 없습니다.'),
            ),
          );
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final item = items[index];
            return ListTile(
              leading: item.thumbnailUrl.isEmpty
                  ? const SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(child: Icon(Icons.play_circle_outline)),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item.thumbnailUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const SizedBox(
                            width: 56,
                            height: 56,
                            child: Center(child: Icon(Icons.play_circle_outline)),
                          );
                        },
                      ),
                    ),
              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.channelTitle.isEmpty ? '채널 정보 없음' : item.channelTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (String value) async {
                  if (value == 'open') {
                    await _openYoutube(context, item.youtubeUrl);
                    return;
                  }
                  if (value == 'import') {
                    await _importYoutubeToMyRecipes(context, item);
                  }
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'open',
                    child: Text('YouTube 열기'),
                  ),
                  PopupMenuItem<String>(
                    value: 'import',
                    child: Text('내 요리 노트로 가져오기'),
                  ),
                ],
              ),
              onTap: () => _openYoutube(context, item.youtubeUrl),
            );
          },
        );
      },
      error: (Object err, StackTrace stack) {
        final message = _youtubeSearchErrorMessage(err);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () {
                          ref.invalidate(youtubeSearchResultsProvider(_searchQuery));
                        },
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () {
        if (_searchQuery.trim().isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('YouTube 검색어를 입력해 주세요.'),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = PublicRecipeQuery(
      search: _searchQuery,
      useAiSearch: _useAiSearch,
    );
    final recipesAsync = ref.watch(publicRecipesFallbackProvider(query));
    final youtubeResultsAsync = ref.watch(youtubeSearchResultsProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Cooking Platform'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push('/bookmarks'),
            icon: const Icon(Icons.bookmark_outline),
            tooltip: '북마크',
          ),
          IconButton(
            onPressed: () => context.push('/creator'),
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '크리에이터',
          ),
          IconButton(
            onPressed: () => context.push('/kitchen'),
            icon: const Icon(Icons.shopping_cart_checkout_outlined),
            tooltip: '장보기',
          ),
          IconButton(
            onPressed: () => context.push('/ops'),
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: '운영 대시보드',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                labelText: '레시피 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _publicSearchVisibleCount = _publicSearchVisibleMax;
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (String value) {
                setState(() {
                  _searchQuery = value;
                  _publicSearchVisibleCount = _publicSearchVisibleMax;
                });
              },
              onSubmitted: (String value) async {
                final source = _searchSource == _SearchSource.youtube
                    ? 'youtube'
                    : 'public';
                await OpsMonitorService.recordEventCounter(
                  'search.submitted.$source',
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<_SearchSource>(
              segments: const <ButtonSegment<_SearchSource>>[
                ButtonSegment<_SearchSource>(
                  value: _SearchSource.public,
                  label: Text('공공레시피'),
                ),
                ButtonSegment<_SearchSource>(
                  value: _SearchSource.youtube,
                  label: Text('YouTube'),
                ),
              ],
              selected: <_SearchSource>{_searchSource},
              onSelectionChanged: (Set<_SearchSource> selected) {
                if (selected.isEmpty) {
                  return;
                }
                setState(() {
                  _searchSource = selected.first;
                  _publicSearchVisibleCount = _publicSearchVisibleMax;
                });
              },
            ),
          ),
          if (_searchSource == _SearchSource.public)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('AI 검색 사용'),
                value: _useAiSearch,
                onChanged: (bool value) {
                  setState(() {
                    _useAiSearch = value;
                  });
                },
              ),
            ),
          Expanded(
            child: _searchSource == _SearchSource.youtube
                ? _buildYoutubeResults(context, youtubeResultsAsync)
                : recipesAsync.when(
              data: (RecipeFetchResult<List<Recipe>> result) {
                final recipes = result.data;
                if (recipes.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        result.fromCache
                            ? '저장된 검색 결과가 없습니다.'
                            : '검색 결과가 없습니다.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final hasSearchQuery = _searchQuery.trim().isNotEmpty;
                final visibleLimit = hasSearchQuery
                  ? math.min(_publicSearchVisibleCount, recipes.length)
                  : recipes.length;
                final visibleRecipes = hasSearchQuery
                  ? recipes.take(visibleLimit).toList(growable: false)
                    : recipes;
                final hasMore = hasSearchQuery && visibleRecipes.length < recipes.length;

                final summaryText = hasSearchQuery
                    ? '총 ${recipes.length}건 중 ${visibleRecipes.length}건 표시'
                    : null;

                return Column(
                  children: <Widget>[
                    if (summaryText != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            summaryText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(publicRecipesFallbackProvider(query));
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification notification) {
                            if (!hasMore) {
                              return false;
                            }

                            final metrics = notification.metrics;
                            final reachedNearBottom =
                                metrics.pixels >= metrics.maxScrollExtent - 120;

                            if (reachedNearBottom) {
                              setState(() {
                                _publicSearchVisibleCount += _publicSearchVisibleMax;
                              });
                            }

                            return false;
                          },
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: visibleRecipes.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final recipe = visibleRecipes[index];
                              return ListTile(
                                leading: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: RecipeThumbnail(imageUrl: recipe.imageUrl),
                                ),
                                title: Text(recipe.title),
                                subtitle: Text(
                                  recipe.summary?.trim().isEmpty ?? true
                                      ? '요약 없음'
                                      : recipe.summary!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/recipes/${recipe.id}'),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              error: (Object err, StackTrace stack) {
                return LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                err is RecipeNetworkFallbackException
                                    ? err.message
                                    : '레시피를 불러오지 못했습니다.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: () {
                                  ref.invalidate(publicRecipesFallbackProvider(query));
                                },
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
