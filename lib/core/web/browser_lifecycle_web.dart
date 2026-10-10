import 'dart:js_interop';
import 'package:web/web.dart' as web;

void clearBrowserAuthParameters() {
  final page = Uri.parse(web.window.location.href);
  final query = Map<String, String>.from(page.queryParameters)
    ..removeWhere((key, _) => const {
          'code',
          'error',
          'error_code',
          'error_description',
          'type'
        }.contains(key));
  final fragment = page.fragment.contains('access_token=') ? '' : page.fragment;
  final clean = Uri(
      scheme: page.scheme,
      host: page.host,
      port: page.hasPort ? page.port : null,
      path: page.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: fragment.isEmpty ? null : fragment);
  web.window.history.replaceState(null, '', clean.toString());
}

void Function() warnBeforeBrowserClose() {
  final listener = ((web.Event event) {
    event.preventDefault();
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;
  web.window.addEventListener('beforeunload', listener);
  return () => web.window.removeEventListener('beforeunload', listener);
}
