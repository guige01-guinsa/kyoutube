# Recipe Scout v67 — 2026-09-16

사용자 승인으로 **1.0.1+67 production 서명 AAB** 생성·검증을 완료했다.
기존 v66 업로드 인증서를 유지했다. Google Play 업로드와 휴대폰 설치는 수행하지 않았다.

## 포함 기능

- 공급업체 검색 조건 겹침 수정·기본 펼침, 업체·상품 등록 진입과 회원 공개 안내.
- 공개 자료 기반 공급업체 20곳 조회, 품목·지역·취급 상품과 배송 조건 확인, 내 거래처 추가.
- 관리자 인터넷 검색 → 업체 선택 → 정보/출처 검토·수정 → 공개 저장. 중복·수정 충돌 검사.
- 로그인한 일반 회원은 공개 정보만 조회하며 관리자 검색·수정·공개는 관리자 역할과 2단계 인증이 필요하다.
- 업체 직접 등록 정보와 공개 자료 기반 정보를 구별한다. 가격·평점·상품 사진을 임의로 생성하지 않는다.

## 검증

- 고정 Flutter 3.44.8 / JDK17, 정적 분석 0건, 전체 Flutter **359개 통과·기존 선택형 4개 건너뜀**.
- 릴리스 가드의 production 설정, git diff --check, 전체 테스트, Android manifest, jarsigner 검증 통과.
- ZIP 무결성, 이전 v66 업로드 인증서 일치, production 서버 URL 및 신규 공급업체 검색 코드 포함 확인.
- 빌드 시작 전 소스 218개 해시와 빌드 후 파일이 일치한다.
- 디버그·백업 비활성, 주소록·마이크 권한 없음, 공유 Provider 비공개. PDF 글꼴·라이선스 일치.
- Gemini 비밀키 및 환경 파일·서명키 파일 미포함 확인.
- 기존 Flutter doctor 경고(FVM 경로 별칭, Android 라이선스 상태, Windows Visual Studio 구성)와 CupertinoIcons 글꼴 경고는 남아 있다. Android 릴리스 빌드는 성공했다.

## 파일

- [recipe-scout-v67.aab](../release/recipe-scout-v67.aab): `com.kyoutube.app`, **1.0.1+67**, **73,905,407 bytes**.
- SHA-256: `523E7AAC475B352162038381C25BC0BEDE0FFAB10767BC62F118136FCD7573AD`.
- [검증 기록](../release/verify-v67.json) · [출처 기록](../release/recipe-scout-v67.aab.provenance.json) · [체크섬](../release/recipe-scout-v67.aab.sha256).
- [한국어 출시 안내](../release/recipe-scout-v67-notes-ko-KR.txt) · [영어 출시 안내](../release/recipe-scout-v67-notes-en-US.txt).

## 운영 상태와 남은 확인

DB0060·업체 20곳·검색 함수 v1·운영 웹은 이전 승인 단계에서 이미 반영했다.
이번 작업은 Android AAB 생성이며 웹을 다시 배포하지 않았다. [서버·웹 검증](../release/verify-web-v66-public-suppliers.json).

관리자 실제 로그인·2단계 인증 후 유료 인터넷 검색 1회 검증이 남아 있다.
로컬 모의 함수 테스트와 운영 인증 차단/RLS 검증을 실제 관리자 검색 성공으로 대신 표시하지 않는다.
Play 테스트 트랙에 이 AAB를 업로드한 뒤 사용자 휴대폰에서 기존 앱을 업데이트하고,
업체 조회·내 거래처 추가·관리자 검색/검토/공개 화면을 확인한다.
