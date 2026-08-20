import 'youtube_search_contract.dart';

abstract interface class YoutubeSearchRepository {
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request);
}
