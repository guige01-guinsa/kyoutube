# Recipe Scout v64 — 2026-09-14

사용자 승인으로 **1.0.1+64 production 서명 AAB** 생성과 검증을 완료했다. 휴대폰 설치는 사용자가 직접 진행하기로 변경했다. 이번 작업에서 Play Console 업로드·배포, 휴대폰 앱 설치·삭제·데이터 초기화, 운영 DB·함수 추가 배포는 수행하지 않았다.

## 변경 사항

- 하단 첫 메뉴를 발견에서 **검색 / Search**로 바꿨다. 내 레시피·장보기·셰프의 네 메뉴를 유지한다.
- 음식 분류를 왼쪽 전체 버튼과 오른쪽 2×2 분류로 정렬했다. 기존 한영 영상 선택과 필터 결과를 유지한다.
- **업소·전문가 9개 실습 / 일반 사용자 5개 실습**을 분리하고 한영 안내를 제공한다.
- 전문가 과정은 표준 레시피·인분·수율·원가·판매가·매출·구매 요청·버전 관리·AI 활용을 다룬다.
- 일반 과정은 검색·초안 검토·저장·장보기·반복 조리를 다룬다.
- 인분·수율·가산율 예제는 기존 셰프 계산을 재사용하고 실제 레시피·매출에 저장하지 않는다.
- 선택한 과정과 과정별 진도를 기기에 저장하고, 셰프 화면에서 전문가 과정으로 바로 이동한다.
- 사전 모집 관리 소스가 포함되지만 DB 0057·모집 관련 함수와 공개 페이지 배포는 이번 작업에 포함되지 않는다. 실제 모집 접수·발송 활성화는 별도다.

상세 과정: [사용자별 튜토리얼](hands-on-tutorial.md).

## 검증

- 고정 Flutter 3.44.8 / JDK 17, 기존 업로드 키와 production 설정 유지.
- 릴리스 스크립트에서 `git diff --check`, 정적 분석 **0건**, Flutter **300개 통과·기존 선택형 4개 건너뜀**.
- 기존 검사에서 한영 두 과정 진도 분리/복원, 320px·200% 글자 크기의 14개 실습, 숫자 예제, 화면 이동 후 복귀와 검색 필터/네 메뉴 동작을 확인했다.
- 실제 Flutter 위젯의 한영 튜토리얼·검색 화면 캡처를 확인했다.
- AAB `jarsigner` 검증, ZIP 무결성, 패키지·버전·production 빌드 출처 해시 일치 확인.
- **v63 업로드 서명 일치**, 디버그·앱 백업 비활성, 주소록·마이크 권한 없음, 공유 Provider 비공개.
- 한글 PDF 글꼴/OFL 라이선스 원본 일치, Gemini 비밀키 및 환경/키 저장 파일의 AAB 미포함 확인.
- 기존 v63에도 있었던 CupertinoIcons 글꼴 경고가 남는다. 이번에 새 의존성이나 서명 키를 변경하지 않았다. 실기기 시각 검증은 수행하지 않았다.
- 로그: `.artifacts/v64-build.log`, 검증 스크립트: `.artifacts/verify_aab_v64.py`.

## 배포 파일

- [recipe-scout-v64.aab](../release/recipe-scout-v64.aab)
- `com.kyoutube.app` / **1.0.1+64** / `production`.
- 크기 **72,704,895 bytes** (69.3 MiB).
- SHA-256: `3B2F92CBF0AEAC0224BF46683DE9170651C0B035F31B3A8DB9357169F09A5544`.
- [검증 기록](../release/verify-v64.json), [빌드 출처](../release/recipe-scout-v64.aab.provenance.json).
- [한국어 출시 안내](../release/recipe-scout-v64-notes-ko-KR.txt), [영어 출시 안내](../release/recipe-scout-v64-notes-en-US.txt).

## 휴대폰 설치 상태

USB 연결된 SM-G977N에서 Google Play 설치본 v63을 읽기 전용으로 확인했다. 설치 APK의 서명은 유효하지만 로컬 업로드 서명과 다르다. 인증서 값은 출력하지 않았으며 비교 결과는 `.artifacts/phone-signing-v64.json`에 기록했다.

사용자가 휴대폰 설치를 직접 진행하겠다고 명시했다. 기존 앱과 데이터를 유지하려면 v64를 Play 테스트 트랙에 업로드해 업데이트하거나, Play Console에서 해당 버전의 **서명된 범용 APK**를 내려받아 설치할 수 있다. 해당 APK는 설치 전 패키지·버전·기존 앱과의 서명 일치를 확인한다. 일반 로컬 업로드 키로 서명한 APK로 기존 Play 앱을 덮어쓰지 않는다.

Google 공식 안내: [앱 서명](https://developer.android.com/studio/publish/app-signing), [서명된 범용 APK 다운로드](https://support.google.com/googleplay/android-developer/answer/9844279?hl=ko).

운영 DB/함수는 v63 배포 기록을 따른다. Google Play 실제 결제 활성화와 사전 모집 백엔드 배포는 별도 남은 작업이다.
