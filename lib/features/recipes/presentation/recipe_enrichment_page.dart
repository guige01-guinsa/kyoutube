import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/recipe_enrichment_service.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import '../domain/recipe_enrichment_suggestion.dart';
import 'create_creator_recipe_page.dart';
import 'recipe_thumbnail.dart';

class RecipeEnrichmentPage extends ConsumerStatefulWidget {
  const RecipeEnrichmentPage({
    super.key,
    required this.recipe,
  });

  final Recipe recipe;

  @override
  ConsumerState<RecipeEnrichmentPage> createState() =>
      _RecipeEnrichmentPageState();
}

class _RecipeEnrichmentPageState extends ConsumerState<RecipeEnrichmentPage> {
  final Set<String> _selectedRecipeIds = <String>{};
  late final TextEditingController _searchController;
  String _searchQuery = '';

  bool _isLoadingCandidates = true;
  bool _isGenerating = false;
  String? _errorMessage;
  List<Recipe> _candidates = const <Recipe>[];
  RecipeEnrichmentSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();

    _searchQuery = widget.recipe.title;
    _searchController = TextEditingController(text: _searchQuery);

    _loadCandidates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoadingCandidates = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(recipeRepositoryProvider);

      final normalizedQuery = _searchQuery.trim();

      if (normalizedQuery.isEmpty) {
        throw StateError('검색어를 입력해 주세요.');
      }

      final candidates = await repository.listPublicRecipes(
        search: normalizedQuery,
        useAiSearch: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _candidates = candidates
            .where((candidate) => candidate.id != widget.recipe.id)
            .take(5)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '유사한 공공 레시피를 불러오지 못했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCandidates = false;
        });
      }
    }
  }

  Future<void> _generateSuggestion() async {
    final references = _candidates
        .where((candidate) => _selectedRecipeIds.contains(candidate.id))
        .toList(growable: false);

    if (references.isEmpty) {
      final youtubeUrl = (widget.recipe.youtubeUrl ?? '').trim();

      if (youtubeUrl.isNotEmpty) {
        await _generateSuggestionFromYoutubeDescription();
        return;
      }

      setState(() {
        _errorMessage = '참고할 공공 레시피를 하나 이상 선택해 주세요.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final service = RecipeEnrichmentService();

      final suggestion = await service.createSuggestion(
        recipe: widget.recipe,
        references: references,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestion = suggestion;
      });
    } on RecipeEnrichmentException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'AI 레시피 보강 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _generateSuggestionFromYoutubeDescription() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final service = RecipeEnrichmentService();

      final suggestion =
          await service.createSuggestionFromSelectedYoutubeVideo(
        recipe: widget.recipe,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestion = suggestion;
      });
    } on RecipeEnrichmentException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '영상 설명란 기반 AI 보강 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _openEditor(RecipeEnrichmentSuggestion suggestion) async {
    final createdRecipeId = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CreateCreatorRecipePage(
          initialRecipe: suggestion.toDraftRecipe(
            sourceRecipe: widget.recipe,
          ),
          returnCreatedRecipeId: true,
        ),
      ),
    );

    if (createdRecipeId is String &&
        createdRecipeId.trim().isNotEmpty &&
        mounted) {
      Navigator.of(context).pop(createdRecipeId);
    }
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _errorMessage = null;
      _selectedRecipeIds.clear();
    });
  }

  void _useSuggestedQuery(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return;
    }

    _searchController.text = normalized;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: normalized.length),
    );

    _updateSearchQuery(normalized);
  }

  void _toggleCandidate(Recipe candidate, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedRecipeIds.length >= 3) {
          _errorMessage = '참고 레시피는 최대 3개까지 선택할 수 있습니다.';
          return;
        }

        _selectedRecipeIds.add(candidate.id);
      } else {
        _selectedRecipeIds.remove(candidate.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;

    return Scaffold(
      appBar: AppBar(
        title: Text(suggestion == null ? 'AI로 레시피 보강' : 'AI 보강 제안'),
      ),
      body: SafeArea(
        child: suggestion == null
            ? _CandidateSelectionView(
                recipe: widget.recipe,
                candidates: _candidates,
                selectedRecipeIds: _selectedRecipeIds,
                searchController: _searchController,
                searchQuery: _searchQuery,
                isLoading: _isLoadingCandidates,
                isGenerating: _isGenerating,
                errorMessage: _errorMessage,
                onReload: _loadCandidates,
                onSearchChanged: _updateSearchQuery,
                onUseSuggestedQuery: _useSuggestedQuery,
                onToggle: _toggleCandidate,
                onGenerate: _generateSuggestion,
              )
            : _SuggestionReviewView(
                sourceRecipe: widget.recipe,
                suggestion: suggestion,
                onBackToCandidates: () {
                  setState(() {
                    _suggestion = null;
                  });
                },
                onOpenEditor: () => _openEditor(suggestion),
              ),
      ),
    );
  }
}

class _CandidateSelectionView extends StatelessWidget {
  const _CandidateSelectionView({
    required this.recipe,
    required this.candidates,
    required this.selectedRecipeIds,
    required this.searchController,
    required this.searchQuery,
    required this.isLoading,
    required this.isGenerating,
    required this.errorMessage,
    required this.onReload,
    required this.onSearchChanged,
    required this.onUseSuggestedQuery,
    required this.onToggle,
    required this.onGenerate,
  });

  final Recipe recipe;
  final List<Recipe> candidates;
  final Set<String> selectedRecipeIds;
  final TextEditingController searchController;
  final String searchQuery;
  final bool isLoading;
  final bool isGenerating;
  final String? errorMessage;
  final Future<void> Function() onReload;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onUseSuggestedQuery;
  final void Function(Recipe candidate, bool selected) onToggle;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text(
          recipe.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          '현재 레시피와 유사한 공공 레시피를 선택하면 AI가 재료와 조리 순서를 보강한 초안을 제안합니다.',
        ),
        const SizedBox(height: 8),
        Text(
          '참고 레시피는 최대 3개까지 선택할 수 있습니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Text(
          '참고 레시피 검색어',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: searchController,
          enabled: !isLoading && !isGenerating,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: '검색어',
            hintText: '레시피 이름 또는 원하는 조리 방향 입력',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: onSearchChanged,
          onSubmitted: (_) => onReload(),
        ),
        const SizedBox(height: 12),
        Text(
          '추천 검색어',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ActionChip(
              label: Text(recipe.title),
              onPressed:
                  isGenerating ? null : () => onUseSuggestedQuery(recipe.title),
            ),
            ...recipe.ingredients.take(4).map(
                  (ingredient) => ActionChip(
                    label: Text(ingredient),
                    onPressed: isGenerating
                        ? null
                        : () => onUseSuggestedQuery(
                              '${recipe.title} $ingredient',
                            ),
                  ),
                ),
            ActionChip(
              label: const Text('간단한 한 끼'),
              onPressed: isGenerating
                  ? null
                  : () => onUseSuggestedQuery(
                        '${recipe.title} 간단한 한 끼',
                      ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isLoading || isGenerating ? null : onReload,
          icon: const Icon(Icons.travel_explore_outlined),
          label: const Text('유사 공공 레시피 찾기'),
        ),
        const SizedBox(height: 20),
        Text(
          '참고할 공공 레시피',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (candidates.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  const Text('유사한 공공 레시피를 찾지 못했습니다.'),
                  if ((recipe.youtubeUrl ?? '').trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      '원본 YouTube 영상의 설명란을 참고해 AI 보강 초안을 만들 수 있습니다.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: onReload,
                    child: const Text('다시 검색'),
                  ),
                ],
              ),
            ),
          )
        else
          ...candidates.map(
            (candidate) {
              final selected = selectedRecipeIds.contains(candidate.id);

              return Card(
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  value: selected,
                  onChanged: isGenerating
                      ? null
                      : (value) => onToggle(candidate, value ?? false),
                  secondary: RecipeThumbnail(
                    imageUrl: candidate.imageUrl,
                    width: 56,
                    height: 56,
                  ),
                  title: Text(candidate.title),
                  subtitle: Text(
                    candidate.summary ?? '요약 정보가 없습니다.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              );
            },
          ),
        if (errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: isLoading || isGenerating ? null : onGenerate,
          icon: isGenerating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(
            isGenerating
                ? 'AI 보강 제안 생성 중...'
                : (candidates.isEmpty &&
                        (recipe.youtubeUrl ?? '').trim().isNotEmpty
                    ? '영상 설명란으로 레시피 보강'
                    : 'AI 보강 제안 만들기'),
          ),
        ),
      ],
    );
  }
}

class _SuggestionReviewView extends StatelessWidget {
  const _SuggestionReviewView({
    required this.sourceRecipe,
    required this.suggestion,
    required this.onBackToCandidates,
    required this.onOpenEditor,
  });

  final Recipe sourceRecipe;
  final RecipeEnrichmentSuggestion suggestion;
  final VoidCallback onBackToCandidates;
  final VoidCallback onOpenEditor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text(
          'AI가 만든 편집 가능한 초안입니다.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '기존 레시피는 변경되지 않으며, 편집 후 새 내 레시피로 저장됩니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _Section(
          title: '요약',
          child: Text(suggestion.summary),
        ),
        _Section(
          title: '재료',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: suggestion.ingredients
                .map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $item'),
                    ))
                .toList(growable: false),
          ),
        ),
        _Section(
          title: '조리 순서',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: suggestion.steps
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${entry.key + 1}. ${entry.value}'),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        if ((suggestion.tips ?? '').isNotEmpty)
          _Section(
            title: '팁',
            child: Text(suggestion.tips!),
          ),
        if (suggestion.warnings.isNotEmpty)
          _Section(
            title: '확인할 사항',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: suggestion.warnings
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $item'),
                      ))
                  .toList(growable: false),
            ),
          ),
        if (suggestion.references.isNotEmpty)
          _Section(
            title: '참고 자료',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: suggestion.references
                  .map((reference) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          reference.channelName == null
                              ? '• ${reference.title}'
                              : '• ${reference.title} · ${reference.channelName}',
                        ),
                      ))
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onOpenEditor,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('내 레시피 만들기에서 편집'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onBackToCandidates,
          child: const Text('참고 레시피 다시 선택'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
