# v58 화면·한식 컬렉션 개선

2026-09-13. 사용자 요청에 따라 `1.0.1+58` production 서명 AAB를 생성했다.
상태: AAB 생성·서명·파일 무결성 검증 완료.

## 변경 사항

- 내 레시피의 큰 플로팅 새 레시피 버튼을 상단의 작은 ＋ 버튼으로 이동했다. 직접 작성과 저장 후 목록 갱신은 유지한다.
- 홈의 대표 한식을 10종에서 15종으로 늘렸다. 김치볶음밥·순두부찌개·제육볶음·닭볶음탕·미역국을 추가했다.
- 한국어용 15개와 영어용 15개의 서로 다른 YouTube 영상을 연결했다. 앱 언어에 맞춰 썸네일·출처·재생·AI 초안 입력을 함께 선택한다.
- 로그인 없이 영상 감상이 가능하며 AI 초안 생성에는 기존 로그인 정책이 적용된다.
- 셰프 작업실과 장보기 준비를 동일한 색·크기·강조의 카드형 버튼으로 배치했다. 좁은 화면과 큰 글자에서는 세로로 배치하고 긴 번역문에 맞춰 높이를 맞춘다.
- 긴 영어 음식명이 이미지 실패 영역을 넘치던 문제를 수정했다.

## 검증 범위

영상 30개는 YouTube 공개 메타데이터 응답의 제목·채널·링크를 확인했다. 모든 영상의 실기기 재생이나 조리 정확도, AI 생성 성공률을 재검증했다는 의미는 아니다. 전체 출처는 `docs/korean-classics.md`를 참조한다.

이번 작업은 앱 AAB 생성이다. 운영 DB·함수의 추가 배포, Play Console 업로드, 휴대폰 설치는 수행하지 않는다. v57에서 남은 서버 푸시 자격 증명 설정 등 운영 항목은 `docs/release-notes-v57-ko.md`의 상태를 따른다.

## Play Console 변경 문구 초안

한국어:
- 대표 한식 15종을 한국어·영어 영상으로 각각 만나보세요.
- 새 레시피 버튼을 작게 정리해 목록을 더 편하게 볼 수 있습니다.
- 셰프 작업실과 장보기 준비를 균형 있게 배치했습니다.
- 큰 글자와 작은 화면에서 표시를 개선했습니다.

English:
- Explore 15 Korean classics with separate Korean and English videos.
- A compact New recipe action keeps your recipe list clear.
- Chef studio and shopping preparation now have equal prominence.
- Improved layouts for smaller screens and larger text.


## 최종 배포 파일 및 검증

- 파일: release/recipe-scout-v58.aab
- 앱: com.kyoutube.app / 1.0.1+58 / production
- 크기: 65767353바이트
- SHA-256: C26882FC721E1C44B28F041B2AD6B2F727FEA95D121FDC14EA0DD2EB828A8612
- v57 업로드 서명과 일치. jarsigner 검증, ZIP 무결성, manifest 버전, provenance 대조 통과.
- 정적 분석 이상 없음. 전체 Flutter 테스트 216개 통과, 기존 선택 실행 테스트 4개 생략.
- 디버그 실행 비활성, 마이크 권한 없음.
- 빌드 로그: release/build-v58.log. 추가 검증: release/verify-v58.json.
- 기존 CupertinoIcons 폰트 경고가 표시됐으나 릴리스 빌드는 성공했다. 이번에 변경한 버튼은 MaterialIcons를 사용한다.
