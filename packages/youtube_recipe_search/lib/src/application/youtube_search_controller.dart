import '../domain/youtube_search_contract.dart';
import '../domain/youtube_search_repository.dart';

class YoutubeSearchController {
  YoutubeSearchController(this.repository);
  final YoutubeSearchRepository repository;
  bool _inFlight = false;

  Future<YoutubeSearchPage?> search(String query) async {
    if (_inFlight) return null;
    _inFlight = true;
    try {
      return await repository.search(YoutubeSearchRequest(query: query));
    } finally {
      _inFlight = false;
    }
  }
}
