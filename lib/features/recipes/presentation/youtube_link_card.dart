import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/youtube_metadata.dart';

class YouTubeLinkCard extends StatelessWidget {
  const YouTubeLinkCard({
    super.key,
    required this.youtubeUrl,
    this.metadata,
    this.displayTitle,
    this.note,
  });

  final String youtubeUrl;
  final RecipeYoutubeMetadata? metadata;
  final String? displayTitle;
  final String? note;

  static String? extractVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host.toLowerCase();

      if (host.contains('youtu.be')) {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first.trim() : '';
        return id.isNotEmpty ? id : null;
      }

      if (host.contains('youtube.com')) {
        final videoId = uri.queryParameters['v']?.trim() ?? '';
        if (videoId.isNotEmpty) {
          return videoId;
        }

        final segments = uri.pathSegments;
        final shortsIndex = segments.indexOf('shorts');
        if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
          final shortsId = segments[shortsIndex + 1].trim();
          return shortsId.isNotEmpty ? shortsId : null;
        }

        final embedIndex = segments.indexOf('embed');
        if (embedIndex >= 0 && segments.length > embedIndex + 1) {
          final embedId = segments[embedIndex + 1].trim();
          return embedId.isNotEmpty ? embedId : null;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static String thumbnailUrl(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  String? _bestThumbnailUrl(String? videoId) {
    final metadataThumbnail = metadata?.thumbnailUrl?.trim();
    if (metadataThumbnail != null && metadataThumbnail.isNotEmpty) {
      return metadataThumbnail;
    }

    if (videoId != null && videoId.isNotEmpty) {
      return thumbnailUrl(videoId);
    }

    return null;
  }

  String _relativeTime(DateTime? time) {
    if (time == null) {
      return '';
    }

    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inSeconds < 10) {
      return '방금 전';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds}초 전';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    }
    return '${diff.inDays}일 전';
  }

  Future<void> _openUrl(BuildContext context) async {
    final uri = Uri.tryParse(youtubeUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효한 YouTube 링크가 아닙니다.')),
        );
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = youtubeUrl.trim();
    if (trimmedUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final videoId = extractVideoId(trimmedUrl);
    final bestThumbnailUrl = _bestThumbnailUrl(videoId);
    final overrideTitle = displayTitle?.trim() ?? '';
    final metadataTitle = metadata?.title?.trim() ?? '';
    final metadataChannelName = metadata?.channelName?.trim() ?? '';
    final metadataError = metadata?.lastError?.trim() ?? '';
    final fetchedAgo = _relativeTime(metadata?.fetchedAt);
    final statusLabel = metadata == null
        ? '링크'
        : metadata!.hasError
            ? '동기화 실패'
            : '서버 메타데이터';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openUrl(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (bestThumbnailUrl != null) ...<Widget>[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  bestThumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.play_circle_outline, size: 48),
                    );
                  },
                ),
              ),
            ] else ...<Widget>[
              Container(
                height: 120,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.play_circle_outline, size: 48),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'YouTube 연결',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.open_in_new, size: 18),
                      const Spacer(),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(statusLabel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    overrideTitle.isNotEmpty
                        ? overrideTitle
                        : metadataTitle.isNotEmpty
                            ? metadataTitle
                        : '레시피와 연결된 원본 영상을 바로 열 수 있습니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if ((note ?? '').trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      note!.trim(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (metadataChannelName.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(metadataChannelName, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (fetchedAgo.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '동기화: $fetchedAgo',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (metadata?.providerName?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      metadata!.providerName!.trim(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (metadataError.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      metadataError,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SelectableText(trimmedUrl),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _openUrl(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('YouTube 열기'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}