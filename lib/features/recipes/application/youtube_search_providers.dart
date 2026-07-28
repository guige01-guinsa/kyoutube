import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/youtube_search_service.dart';
import '../domain/youtube_search_result.dart';

final youtubeSearchQueryProvider = StateProvider<String>(
  (ref) => '',
);

final youtubeSearchLimitProvider = StateProvider<int>(
  (ref) => 5,
);

final youtubeSearchServiceProvider = Provider<YoutubeSearchService>(
  (ref) => const YoutubeSearchService(),
);

final youtubeSearchResultsProvider =
    FutureProvider.family<List<YoutubeSearchResult>, String>(
  (ref, String query) async {
    final service = ref.watch(youtubeSearchServiceProvider);
    final limit = ref.watch(youtubeSearchLimitProvider);

    return service.search(
      query: query,
      limit: limit,
    );
  },
);
