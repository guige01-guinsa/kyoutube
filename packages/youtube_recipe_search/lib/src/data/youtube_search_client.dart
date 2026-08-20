import '../domain/youtube_search_contract.dart';
import '../domain/youtube_search_exception.dart';
import '../domain/youtube_search_repository.dart';

class YoutubeTransportResponse {
  const YoutubeTransportResponse(
      {required this.statusCode, required this.body});
  final int statusCode;
  final Object? body;
}

abstract interface class YoutubeSearchTransport {
  Future<YoutubeTransportResponse> get(YoutubeSearchRequest request);
}

class YoutubeSearchClient implements YoutubeSearchRepository {
  const YoutubeSearchClient(this.transport);
  final YoutubeSearchTransport transport;

  @override
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request) async {
    final query = request.query.trim();
    if (query.length < 2) {
      throw const YoutubeSearchException('youtube_input_invalid');
    }
    try {
      final response = await transport.get(YoutubeSearchRequest(
          query: query, limit: request.limit.clamp(1, 10)));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = response.body;
        final code = body is Map<String, Object?> && body['errorCode'] is String
            ? body['errorCode'] as String
            : 'youtube_transport_error';
        throw YoutubeSearchException(code, httpStatus: response.statusCode);
      }
      return YoutubeSearchPage.fromResponse(response.body);
    } on YoutubeSearchException {
      rethrow;
    } catch (_) {
      throw const YoutubeSearchException('youtube_transport_error');
    }
  }
}
