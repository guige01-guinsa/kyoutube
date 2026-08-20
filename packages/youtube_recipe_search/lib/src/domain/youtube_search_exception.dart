/// A deliberately non-diagnostic exception safe to show in a host UI.
class YoutubeSearchException implements Exception {
  const YoutubeSearchException(this.code, {this.httpStatus});

  final String code;
  final int? httpStatus;

  @override
  String toString() =>
      'YoutubeSearchException(code: $code${httpStatus == null ? '' : ', httpStatus: $httpStatus'})';
}
