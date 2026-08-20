# YouTube Recipe Search

독립 Flutter UI/계약 모듈입니다. `flutter test`와 `flutter analyze`를 이 폴더에서 실행합니다. 호스트는 `YoutubeSearchTransport`, `YoutubeSearchController`, `onOpenUrl`, `enabled`를 주입합니다. 패키지는 인증·라우터·API 키·K-youtube 모델을 알지 못합니다. Transport body는 이미 UTF-8로 decode된 JSON object여야 하며, HTTP bytes를 읽는 host adapter가 UTF-8 decode를 담당합니다.

Edge endpoint는 `GET ?q=&limit=`에 `{status:"ok",data:{items,nextPageToken:null}}`를 반환합니다. 키는 `YOUTUBE_DATA_API_KEY`를 우선하고, 호환 목적의 `YOUTUBE_API_KEY`를 fallback으로 사용합니다. query/key/URL/body/video 값은 로그나 오류에 기록하지 않습니다. 기본 5개·최대 10개이며 429/5xx만 각각 한 번 재시도합니다.

title/channelTitle의 YouTube HTML entity는 순수 Dart helper로 일반 문자열에만 decode합니다. HTML로 렌더링하지 않으며 videoId와 URL은 변경하지 않습니다. 후속 단계에서 호스트의 Supabase HTTP adapter와 URL launcher adapter를 연결하고 recipe import adapter를 별도로 추가합니다.
