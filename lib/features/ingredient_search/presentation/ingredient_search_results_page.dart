import '../../../core/auth/auth_return.dart';
import 'package:k_youtube/core/widgets/scout_page.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/youtube_recipe_enrichment_page.dart';
import '../../youtube/data/supabase_youtube_search_transport.dart';
import '../../youtube/domain/youtube_thumbnail_url.dart';

class IngredientSearchResultsPage extends StatefulWidget {
  const IngredientSearchResultsPage({
    super.key,
    required this.ingredients,
  });

  final List<String> ingredients;

  @override
  State<IngredientSearchResultsPage> createState() =>
      _IngredientSearchResultsPageState();
}

class _IngredientSearchResultsPageState
    extends State<IngredientSearchResultsPage> {
  late final YoutubeSearchController _controller;
  late final SupabaseYoutubeSearchTransport _transport;

  @override
  void initState() {
    super.initState();
    _transport = SupabaseYoutubeSearchTransport();
    _controller = YoutubeSearchController(YoutubeSearchClient(_transport));
  }

  @override
  void dispose() {
    _transport.close();
    super.dispose();
  }

  String get _query => widget.ingredients.join(' ');

  bool _isAuthenticated() {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
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
    final normalizedTitle = item.title.trim();
    final normalizedYoutubeUrl = item.youtubeUrl.trim();

    if (normalizedTitle.isEmpty || normalizedYoutubeUrl.isEmpty) {
      _showMessage('영상 정보를 확인할 수 없습니다.');
      return;
    }

    final sourceRecipe = Recipe(
      id: '',
      title: normalizedTitle,
      summary: item.channelTitle.trim().isEmpty
          ? '선택한 YouTube 영상 기반 레시피'
          : '선택한 YouTube 영상 기반 레시피 · ${item.channelTitle.trim()}',
      ingredients: const <String>[],
      steps: const <String>[],
      imageUrl: youtubeThumbnailUrlFromUrl(normalizedYoutubeUrl),
      youtubeUrl: normalizedYoutubeUrl,
      sourceType: 'youtube_import',
    );

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
    if (!_isAuthenticated()) {
      return Scaffold(
        appBar: AppBar(title: const LocalizedText('재료 찾기')),
        body: ScoutPageBody(
            maxWidth: 1000,
            child: Center(
              child: FilledButton(
                onPressed: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
                child: const LocalizedText('로그인하기'),
              ),
            )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('YouTube 검색'),
      ),
      body: ScoutPageBody(
          maxWidth: 1000,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.ingredients
                        .map((ingredient) =>
                            Chip(label: LocalizedText(ingredient)))
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: YoutubeRecipeSearchView(
                      controller: _controller,
                      initialQuery: _query,
                      autoSearchInitialQuery: _query.trim().length >= 2,
                      onOpenUrl: _openYoutubeUrl,
                      onCreateRecipe: _createRecipeFromYoutube,
                    ),
                  ),
                ],
              ),
            ),
          )),
    );
  }
}
