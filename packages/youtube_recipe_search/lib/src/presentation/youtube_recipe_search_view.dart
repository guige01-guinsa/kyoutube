import 'dart:async';

import 'package:flutter/material.dart';

import '../application/youtube_search_controller.dart';
import '../domain/youtube_search_exception.dart';
import '../domain/youtube_search_result.dart';

typedef YoutubeUrlOpener = Future<void> Function(String url);

typedef YoutubeRecipeCreator = Future<void> Function(
  YoutubeSearchResult result,
);

class YoutubeRecipeSearchView extends StatefulWidget {
  const YoutubeRecipeSearchView({
    super.key,
    required this.controller,
    required this.onOpenUrl,
    this.onCreateRecipe,
    this.enabled = true,
    this.initialQuery,
    this.autoSearchInitialQuery = false,
    this.debounce = const Duration(milliseconds: 700),
  });

  final YoutubeSearchController controller;
  final YoutubeUrlOpener onOpenUrl;
  final YoutubeRecipeCreator? onCreateRecipe;
  final bool enabled;
  final String? initialQuery;
  final bool autoSearchInitialQuery;
  final Duration debounce;

  @override
  State<YoutubeRecipeSearchView> createState() =>
      _YoutubeRecipeSearchViewState();
}

class _YoutubeRecipeSearchViewState extends State<YoutubeRecipeSearchView> {
  final TextEditingController _text = TextEditingController();

  Timer? _timer;
  List<YoutubeSearchResult>? _items;
  String? _error;
  String? _creatingRecipeVideoId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialQuery?.trim() ?? '';

    if (initial.isNotEmpty) {
      _text.text = initial;
    }

    if (widget.autoSearchInitialQuery && initial.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _search();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _search);
  }

  Future<void> _search() async {
    _timer?.cancel();

    if (!widget.enabled || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.controller.search(_text.text);

      if (!mounted) {
        return;
      }

      if (page != null) {
        setState(() {
          _items = page.items;
        });
      }
    } on YoutubeSearchException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.code;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createRecipe(YoutubeSearchResult item) async {
    final creator = widget.onCreateRecipe;

    if (creator == null || !widget.enabled) {
      return;
    }

    setState(() {
      _creatingRecipeVideoId = item.videoId;
      _error = null;
    });

    try {
      await creator(item);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _creatingRecipeVideoId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final strings = _YoutubeSearchStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('youtube-search-input'),
          controller: _text,
          enabled: widget.enabled,
          onChanged: (_) => _schedule(),
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: strings.searchLabel,
            suffixIcon: IconButton(
              key: const Key('youtube-search-submit'),
              onPressed: widget.enabled ? _search : null,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(strings.durationNotice),
        ),
        if (!widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(strings.searchUnavailable),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${strings.searchFailed} ($_error)',
              key: const Key('youtube-search-error'),
            ),
          ),
        if (!_loading && items != null && items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              strings.noResults,
              key: const Key('youtube-search-empty'),
            ),
          ),
        if (items != null)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final item = items[index];

                return YoutubeSearchResultCard(
                  item: item,
                  canCreateRecipe:
                      widget.enabled && widget.onCreateRecipe != null,
                  isCreatingRecipe: _creatingRecipeVideoId == item.videoId,
                  onOpenUrl: () => widget.onOpenUrl(item.youtubeUrl),
                  onCreateRecipe: () => _createRecipe(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

class YoutubeSearchResultCard extends StatelessWidget {
  const YoutubeSearchResultCard({
    super.key,
    required this.item,
    required this.canCreateRecipe,
    required this.isCreatingRecipe,
    required this.onOpenUrl,
    required this.onCreateRecipe,
    this.onExcludeFromSearch,
  });

  final YoutubeSearchResult item;
  final bool canCreateRecipe;
  final bool isCreatingRecipe;
  final VoidCallback onOpenUrl;
  final VoidCallback onCreateRecipe;
  final VoidCallback? onExcludeFromSearch;

  @override
  Widget build(BuildContext context) {
    final strings = _YoutubeSearchStrings.of(context);
    final thumbnailCacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 4096)
        .toInt();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenUrl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    item.thumbnailUrl,
                    key: Key('youtube-thumbnail-${item.videoId}'),
                    fit: BoxFit.cover,
                    cacheWidth: thumbnailCacheWidth,
                    semanticLabel: strings.thumbnailLabel(item.title),
                    loadingBuilder: (
                      BuildContext context,
                      Widget child,
                      ImageChunkEvent? loadingProgress,
                    ) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return const ColoredBox(
                        color: Color(0xFFF1F3F4),
                        child: Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) =>
                        const ColoredBox(
                      color: Color(0xFFF1F3F4),
                      child: Center(
                        child: Icon(Icons.ondemand_video_outlined, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                subtitle: Text(
                  item.durationSec == null
                      ? item.channelTitle
                      : '${item.channelTitle} · ${_durationLabel(item.durationSec!)}',
                ),
                trailing: IconButton(
                  tooltip: strings.openYoutube,
                  onPressed: onOpenUrl,
                  icon: const Icon(Icons.open_in_new),
                ),
                onTap: onOpenUrl,
              ),
              if (canCreateRecipe)
                FilledButton.icon(
                  key: Key('youtube-create-recipe-${item.videoId}'),
                  onPressed: isCreatingRecipe ? null : onCreateRecipe,
                  icon: isCreatingRecipe
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restaurant_menu),
                  label: Text(
                    isCreatingRecipe
                        ? strings.savingRecipe
                        : strings.createFromVideo,
                  ),
                ),
              if (onExcludeFromSearch != null)
                TextButton.icon(
                  onPressed: onExcludeFromSearch,
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: Text(
                    strings.isEnglish ? 'Hide from search' : '검색에서 제외',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _YoutubeSearchStrings {
  const _YoutubeSearchStrings(this.isEnglish);

  factory _YoutubeSearchStrings.of(BuildContext context) =>
      _YoutubeSearchStrings(
          Localizations.localeOf(context).languageCode == 'en');

  final bool isEnglish;

  String get searchLabel =>
      isEnglish ? 'Search YouTube recipes' : 'YouTube 레시피 검색';
  String get durationNotice => isEnglish
      ? 'Search results only show videos up to 60 minutes long.'
      : '검색 결과에는 재생시간 60분 이내 영상만 표시됩니다.';
  String get searchUnavailable =>
      isEnglish ? 'YouTube search is unavailable.' : 'YouTube 검색을 사용할 수 없습니다.';
  String get searchFailed => isEnglish ? 'Search failed.' : '검색에 실패했습니다.';
  String get noResults => isEnglish ? 'No search results.' : '검색 결과가 없습니다.';
  String get openYoutube => isEnglish ? 'Open YouTube' : 'YouTube 열기';
  String get savingRecipe => isEnglish ? 'Saving recipe...' : '레시피 저장 중...';
  String get createFromVideo =>
      isEnglish ? 'Create recipe from this video' : '이 영상으로 레시피 만들기';

  String thumbnailLabel(String title) =>
      isEnglish ? 'Video thumbnail for $title' : '$title 대표 영상 이미지';
}
