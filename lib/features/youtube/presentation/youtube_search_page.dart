import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/config/env.dart';
import '../data/supabase_youtube_search_transport.dart';
import '../data/youtube_recipe_creation_service.dart';

class YoutubeSearchPage extends StatefulWidget {
  const YoutubeSearchPage({
    super.key,
    this.transport,
    this.creationService,
    this.enabled = Env.youtubeSearchEnabled,
  });

  final YoutubeSearchTransport? transport;
  final YoutubeRecipeCreationService? creationService;
  final bool enabled;

  @override
  State<YoutubeSearchPage> createState() => _YoutubeSearchPageState();
}

class _YoutubeSearchPageState extends State<YoutubeSearchPage> {
  late final YoutubeSearchController _controller;
  late final YoutubeRecipeCreationService _creationService;

  @override
  void initState() {
    super.initState();

    final transport = widget.transport ?? SupabaseYoutubeSearchTransport();

    _controller = YoutubeSearchController(
      YoutubeSearchClient(transport),
    );

    _creationService = widget.creationService ?? YoutubeRecipeCreationService();
  }

  Future<void> _openYoutubeUrl(String rawUrl) async {
    if (!widget.enabled) {
      return;
    }

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

  Future<void> _createRecipeFromYoutube({
    required String title,
    required String channelTitle,
    required String youtubeUrl,
  }) async {
    if (!widget.enabled) {
      return;
    }

    try {
      final result = await _creationService.createDraftFromYoutube(
        YoutubeRecipeDraftInput(
          title: title,
          channelTitle: channelTitle,
          youtubeUrl: youtubeUrl,
        ),
      );

      if (!mounted) {
        return;
      }

      _showMessage('내 레시피에 저장했습니다.');

      context.go('/creator/${Uri.encodeComponent(result.recipeId)}');
    } on YoutubeRecipeCreationException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('레시피 생성 중 오류가 발생했습니다.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('YouTube'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'YouTube search is currently unavailable.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: YoutubeRecipeSearchView(
            controller: _controller,
            enabled: widget.enabled,
            onOpenUrl: _openYoutubeUrl,
            onCreateRecipe: (item) => _createRecipeFromYoutube(
              title: item.title,
              channelTitle: item.channelTitle,
              youtubeUrl: item.youtubeUrl,
            ),
          ),
        ),
      ),
    );
  }
}
