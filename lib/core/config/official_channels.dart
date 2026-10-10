/// Public destinations; never append account or session data.
enum OfficialChannel {
  youtube('https://www.youtube.com/@guige01'),
  blog('https://blog.naver.com/toktoknr');

  const OfficialChannel(this.url);
  final String url;
  Uri get uri => Uri.parse(url);
}
