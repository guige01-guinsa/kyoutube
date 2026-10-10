import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/official_channels.dart';
import '../localization/app_localizations.dart';

/// Loading this card makes no external requests.
class OfficialChannelsCard extends StatefulWidget {
  const OfficialChannelsCard({super.key, this.openUrl});
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<OfficialChannelsCard> createState() => _OfficialChannelsCardState();
}

class _OfficialChannelsCardState extends State<OfficialChannelsCard> {
  bool _opening = false;
  Future<void> _open(OfficialChannel channel) async {
    if (_opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await (widget.openUrl?.call(channel.uri) ??
          launchUrl(channel.uri,
              mode: LaunchMode.externalApplication,
              webOnlyWindowName: '_blank'));
    } catch (_) {
      // Do not expose platform error details.
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (opened) return;
    final en = AppLocalizations.of(context).isEnglish;
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(en ? 'Could not open the link' : '링크를 열지 못했어요'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(en
                    ? 'Copy this address and open it in your browser.'
                    : '아래 주소를 복사해 브라우저에서 열어 주세요.'),
                const SizedBox(height: 12),
                SelectableText(channel.url),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(en ? 'Close' : '닫기')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final en = AppLocalizations.of(context).isEnglish;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(en ? 'Official guides' : '공식 사용 안내',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(en
                      ? 'Follow video tutorials or read detailed guides on our blog. Content is in Korean.'
                      : '영상으로 따라 하고, 블로그에서 자세한 사용법과 소식을 확인하세요.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        key: const Key('official-youtube'),
                        onPressed: _opening
                            ? null
                            : () => _open(OfficialChannel.youtube),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(en ? 'Official YouTube' : '공식 유튜브')),
                    OutlinedButton.icon(
                        key: const Key('official-blog'),
                        onPressed:
                            _opening ? null : () => _open(OfficialChannel.blog),
                        icon: const Icon(Icons.article_outlined),
                        label: Text(en ? 'Official blog' : '공식 블로그')),
                  ]),
                ])));
  }
}
