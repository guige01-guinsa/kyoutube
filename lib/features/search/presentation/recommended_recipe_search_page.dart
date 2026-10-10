import '../../../core/auth/auth_return.dart';
import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_thumbnail.dart';
import '../../recipes/presentation/youtube_recipe_enrichment_page.dart';
import '../../youtube/domain/youtube_thumbnail_url.dart';
import '../application/recommended_recipe_search_service.dart';

class RecommendedRecipeSearchPage extends ConsumerStatefulWidget {
  const RecommendedRecipeSearchPage({
    super.key,
    required this.initialQuery,
  });

  final String initialQuery;

  @override
  ConsumerState<RecommendedRecipeSearchPage> createState() =>
      _RecommendedRecipeSearchPageState();
}

class _RecommendedRecipeSearchPageState
    extends ConsumerState<RecommendedRecipeSearchPage> {
  late final TextEditingController _queryController;
  RecommendedRecipeSearchResult? _result;
  bool _loading = false;
  String? _creatingRecipeVideoId;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery.trim());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _queryController.text.trim().isNotEmpty) {
        _search();
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      _showMessage('검색할 요리나 재료를 입력해 주세요.');
      return;
    }

    FocusScope.of(context).unfocus();
    final requestSerial = ++_requestSerial;
    setState(() {
      _loading = true;
    });

    final result =
        await ref.read(recommendedRecipeSearchServiceProvider).search(query);

    if (!mounted || requestSerial != _requestSerial) {
      return;
    }

    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _openLoginAndRefresh() async {
    await context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
    if (mounted) {
      await _search();
    }
  }

  Future<void> _openYoutubeUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !_isAllowedYoutubeUri(uri)) {
      _showMessage('이 YouTube 링크를 열 수 없습니다.');
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

  Future<void> _createRecipeFromYoutube(YoutubeSearchResult item) async {
    if (_creatingRecipeVideoId != null) {
      return;
    }

    setState(() {
      _creatingRecipeVideoId = item.videoId;
    });

    final sourceRecipe = Recipe(
      id: '',
      title: item.title.trim(),
      summary: item.channelTitle.trim().isEmpty
          ? '선택한 YouTube 영상 기반 레시피'
          : '선택한 YouTube 영상 기반 레시피 · ${item.channelTitle.trim()}',
      ingredients: const <String>[],
      steps: const <String>[],
      imageUrl: youtubeThumbnailUrlFromUrl(item.youtubeUrl),
      youtubeUrl: item.youtubeUrl,
      sourceType: 'youtube_import',
    );

    try {
      final createdRecipeId = await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => YoutubeRecipeEnrichmentPage(recipe: sourceRecipe),
        ),
      );

      if (createdRecipeId is String &&
          createdRecipeId.trim().isNotEmpty &&
          mounted) {
        _showMessage('내 레시피에 저장했습니다.');
        context.go('/creator/${Uri.encodeComponent(createdRecipeId)}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingRecipeVideoId = null;
        });
      }
    }
  }

  Future<void> _excludeYoutube(YoutubeSearchResult item) async {
    await _excludeRecipe(
      sourceType: 'youtube',
      sourceId: item.videoId,
      title: item.title,
      imageUrl: item.thumbnailUrl,
      youtubeUrl: item.youtubeUrl,
    );
  }

  Future<void> _excludePublic(Recipe recipe) async {
    await _excludeRecipe(
      sourceType: 'public',
      sourceId: recipe.id,
      title: recipe.title,
      summary: recipe.summary,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      imageUrl: recipe.imageUrl,
      youtubeUrl: recipe.youtubeUrl,
    );
  }

  Future<void> _excludeRecipe({
    required String sourceType,
    required String sourceId,
    required String title,
    String? summary,
    List<String> ingredients = const <String>[],
    List<String> steps = const <String>[],
    String? imageUrl,
    String? youtubeUrl,
  }) async {
    try {
      await ref.read(recipeRepositoryProvider).excludeRecipeFromSearch(
            sourceType: sourceType,
            sourceId: sourceId,
            title: title,
            summary: summary,
            ingredients: ingredients,
            steps: steps,
            imageUrl: imageUrl,
            youtubeUrl: youtubeUrl,
          );
      if (!mounted) return;
      final result = _result;
      if (result != null) {
        setState(() {
          _result = RecommendedRecipeSearchResult(
            query: result.query,
            youtubeRecipes: result.youtubeRecipes
                .where((item) =>
                    sourceType != 'youtube' || item.videoId != sourceId)
                .toList(growable: false),
            publicRecipes: result.publicRecipes
                .where((item) => sourceType != 'public' || item.id != sourceId)
                .toList(growable: false),
            youtubeError: result.youtubeError,
            publicRecipeError: result.publicRecipeError,
          );
        });
      }
      ref.invalidate(recipeSearchExclusionsProvider);
      _showMessage('검색 제외 레시피에 추가했습니다.');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains('로그인이 필요합니다')) {
        await context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true));
        return;
      }
      _showMessage('검색 제외 레시피에 추가하지 못했습니다.');
    }
  }

  bool _isAllowedYoutubeUri(Uri uri) {
    if (uri.scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: LocalizedText(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('추천 검색')),
      body: ScoutPageBody(
          maxWidth: 1000,
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        key: const Key('recommended-search-input'),
                        controller: _queryController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          labelText: context.tr('요리나 재료를 검색하세요'),
                          hintText: context.tr('한국 요리 검색'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            key: const Key('recommended-search-submit'),
                            onPressed: _loading ? null : _search,
                            icon: const Icon(Icons.arrow_forward),
                            tooltip: context.tr('검색'),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      LocalizedText(
                        '영상 레시피와 공공 레시피를 함께 찾아드려요.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          )),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final result = _result;
    if (result == null) {
      return const CenteredStateView(
        icon: Icons.search,
        title: '무엇을 만들어 볼까요?',
        message: '요리 이름이나 가지고 있는 재료를 검색해 보세요.',
      );
    }

    final youtubeAuthRequired = result.youtubeError is YoutubeSearchException &&
        (result.youtubeError! as YoutubeSearchException).code ==
            'youtube_auth_required';

    if (result.resultCount == 0) {
      if (youtubeAuthRequired) {
        return CenteredStateView(
          icon: Icons.login,
          title: '영상 검색은 로그인이 필요합니다',
          message: '로그인한 뒤 같은 검색어로 영상 레시피를 다시 찾아드릴게요.',
          actionLabel: context.tr('로그인하기'),
          onAction: _openLoginAndRefresh,
          secondaryActionLabel: '공공 레시피 다시 찾기',
          onSecondaryAction: _search,
        );
      }
      return CenteredStateView(
        icon: Icons.search_off,
        title: '검색 결과가 없습니다',
        message: result.publicRecipeError == null
            ? '다른 요리 이름이나 재료로 다시 검색해 보세요.'
            : '검색 서비스를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
        actionLabel: context.tr('다시 검색'),
        onAction: _search,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: <Widget>[
        if (youtubeAuthRequired)
          _SearchNoticeCard(
            icon: Icons.login,
            message: '로그인하면 영상 레시피 추천도 함께 볼 수 있어요.',
            actionLabel: context.tr('로그인'),
            onAction: _openLoginAndRefresh,
          )
        else if (result.youtubeError != null)
          const _SearchNoticeCard(
            icon: Icons.info_outline,
            message: '영상 검색이 원활하지 않아 공공 레시피를 보여드려요.',
          ),
        if (result.youtubeRecipes.isNotEmpty) ...<Widget>[
          const _ResultSectionTitle(
            icon: Icons.ondemand_video_outlined,
            title: '영상 레시피 추천',
            badge: '우선 추천',
          ),
          ...result.youtubeRecipes.map(
            (item) => YoutubeSearchResultCard(
              item: item,
              canCreateRecipe: true,
              isCreatingRecipe: _creatingRecipeVideoId == item.videoId,
              onOpenUrl: () => _openYoutubeUrl(item.youtubeUrl),
              onCreateRecipe: () => _createRecipeFromYoutube(item),
              onExcludeFromSearch: () => _excludeYoutube(item),
            ),
          ),
        ],
        if (result.publicRecipes.isNotEmpty) ...<Widget>[
          const _ResultSectionTitle(
            icon: Icons.menu_book_outlined,
            title: '공공 레시피',
          ),
          ...result.publicRecipes.map(
            (recipe) => _RecommendedPublicRecipeCard(
              recipe: recipe,
              onTap: () => context.push('/recipes/${recipe.id}'),
              onExcludeFromSearch: () => _excludePublic(recipe),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultSectionTitle extends StatelessWidget {
  const _ResultSectionTitle({
    required this.icon,
    required this.title,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          LocalizedText(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (badge != null) ...<Widget>[
            const SizedBox(width: 8),
            Chip(
              visualDensity: VisualDensity.compact,
              label: LocalizedText(badge!),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchNoticeCard extends StatelessWidget {
  const _SearchNoticeCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: LocalizedText(message)),
            if (actionLabel != null && onAction != null)
              TextButton(
                  onPressed: onAction, child: LocalizedText(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

class _RecommendedPublicRecipeCard extends StatelessWidget {
  const _RecommendedPublicRecipeCard({
    required this.recipe,
    required this.onTap,
    required this.onExcludeFromSearch,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback onExcludeFromSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('recommended-public-recipe-card-${recipe.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            RecipeThumbnail(
              imageUrl: recipe.imageUrl,
              width: 112,
              height: 88,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LocalizedText(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    LocalizedText('재료 ${recipe.ingredients.length}개'),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: context.tr('검색에서 제외'),
              onPressed: onExcludeFromSearch,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
