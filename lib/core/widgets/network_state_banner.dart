import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum NetworkBannerKind {
  degradedCache,
  serverError,
}

class NetworkStateBanner extends StatelessWidget {
  const NetworkStateBanner({
    super.key,
    required this.message,
    this.cachedAt,
    this.onRetry,
    this.kind = NetworkBannerKind.degradedCache,
  });

  final String message;
  final DateTime? cachedAt;
  final VoidCallback? onRetry;
  final NetworkBannerKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDegraded = kind == NetworkBannerKind.degradedCache;
    final background =
        isDegraded ? const Color(0xFFFFF4E5) : const Color(0xFFFFECEC);
    final border =
        isDegraded ? const Color(0xFFF0B76B) : const Color(0xFFE38B8B);
    final icon =
        isDegraded ? Icons.wifi_off_outlined : Icons.cloud_off_outlined;

    final timeLabel = cachedAt == null
        ? null
        : DateFormat('MM/dd HH:mm').format(cachedAt!.toLocal());

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: scheme.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (timeLabel != null) ...<Widget>[
            const SizedBox(height: 8),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('마지막으로 본 데이터 $timeLabel'),
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
