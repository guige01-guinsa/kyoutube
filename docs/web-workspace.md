# 앱·웹 통합 작업실 — v65 소스 기반

> 2026-09-15 후속: 공개 웹 빌드와 Firebase 배포·읽기 전용 검증을 완료했다. 명시적 승인을 받아 운영 OAuth 복귀 주소 4개도 추가했다. 최신 상태는 [공개 웹 배포](web-public-release.md)를 따른다. 아래 내용은 최초 로컬 개발 단계의 기록이다.

2026-09-15. 별도 회원/DB를 만들지 않고 기존 Flutter 앱을 브라우저로 확장했다. 이번 변경은 로컬 개발이며 운영 웹 주소 발행, 운영 DB 변경, 새 AAB 생성은 포함하지 않는다. 기존 1.0.1+65 AAB는 그대로다.

## 사용 흐름

PC는 작업 홈 → 내 레시피 → 셰프 작업실 → 장보기/구매처/구매 요청서/매출로 이어진다. 폭 1100px 이상에서 왼쪽 업무 메뉴를 사용하고, 작은 화면에서는 기존 모바일 메뉴를 사용한다. 한글/영어를 지원한다. 웹 글꼴은 포함된 NanumGothic을 사용해 외부 글꼴의 늦은 다운로드에 따른 한글 깨짐을 방지한다.

- 작업 홈: 셰프·구매 준비·구매 요청서 바로가기와 내 레시피.
- 내 레시피: PC에서는 두 열로 표시하며 기존 검색/정렬을 공유한다.
- 셰프: 충분한 폭에서 재료를 표로 편집하고 옆에 원가·판매가 요약을 표시한다. 인분, 수율, 추가 비용, 버전 관리와 서버 계산/검증 규칙은 앱과 동일하다.
- 구매 요청서: 웹에서는 텍스트 복사와 PDF 파일 다운로드를 사용한다. 사용자가 카카오톡 등에 붙여 넣거나 파일을 첨부해 전송한다. 복사/다운로드만으로 요청서를 전송 완료 처리하지 않는다.
- 회원권: 기존 서버 권한을 조회한다. 웹 신규 결제는 아직 제공하지 않고 Google Play 복원 버튼도 웹에서 표시하지 않는다.

## 데이터와 보안

Flutter의 기존 Supabase Auth, PostgreSQL/RLS, Edge Functions와 저장소를 함께 사용한다. 운영 웹 배포 시 앱과 **같은 운영 프로젝트**를 지정해야 실제 회원 데이터가 이어진다. 현재 localhost 미리보기는 로컬 Supabase에만 연결되므로 운영 앱의 계정/자료가 표시되지 않는다.

저장된 레시피·셰프 문서·구매 자료가 공유된다. 서버에서 다시 불러올 때 최신 내용을 읽으며 실시간 공동 문서 편집 기능은 아니다. 셰프 문서는 기존 revision 검증으로 오래된 저장을 거절한다. 저장 전 편집과 장보기 준비 초안은 다른 기기로 동기화하지 않는다. 셰프와 레시피 편집에 화면 이탈 확인 및 브라우저 종료 경고를 연결했다. 브라우저 경고는 사용자의 페이지 상호작용과 브라우저 정책에 따라 표시되며 자동 저장을 대체하지 않는다.

원가·판매가·매출은 Business 권한을 서버에서 판정한다. 영상 분석과 AI 한도도 같은 서버 한도를 사용한다. API 비밀키와 service_role은 웹 번들에 넣지 않는다. 구매 단위와 조리 단위를 분리한 v65 규칙을 유지하며 조리 완료로 재고를 차감하지 않는다.

OAuth는 브라우저의 현재 origin/path로 복귀한다. 다른 origin/path의 콜백은 교환하지 않고 성공 후 인증 query/fragment를 주소에서 제거한다. 휴대폰 전용 callback은 유지한다. 공개 배포에서는 Supabase Auth의 허용 복귀 주소에 정확한 HTTPS 웹 주소를 추가하고 Google/Kakao 및 비밀번호 재설정의 실제 왕복을 검증해야 한다.

## 로컬 실행

고정 Flutter 3.44.8과 기존 개발 안내를 따른다. 현재 로컬 DB의 0035 기준을 운영 v65에 해당하는 0058까지 준비하려면 `python tools/dev/prepare-web-local.py`를 사용한다. 이 스크립트는 로컬 Docker DB만 대상으로 하며 reset하지 않는다. 운영 이력에 없는 0047·0048·0057은 적용하지 않는다. 새 환경은 먼저 저장소의 로컬 Supabase 기본 환경을 준비해야 한다.

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/bootstrap.ps1
# 기존 로컬 Supabase 시작 후, 별도 터미널에서 Edge Functions 실행
supabase functions serve recipe_api
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local -Device web-server -WebPort 8766
```

모듈 개발 서버는 8766이며 8765의 모집 페이지와 별개다. Windows 환경에서 개발 JS 모듈의 개별 로드가 느린 경우 다음의 묶음 미리보기를 사용한다.

```powershell
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local -StaticWeb -WebPort 8767
```

확인용 웹 주소는 `http://127.0.0.1:8767/`이다. `--debug --no-wasm-dry-run --no-web-resources-cdn`으로 `.artifacts/web-preview`만 빌드하고 이 디렉터리를 루프백으로 제공한다. 비밀 설정 파일이나 저장소 전체를 웹으로 제공하지 않는다. 공개 릴리스용 빌드가 아니므로 이 미리보기의 크기/시간을 배포용 성능 수치로 해석하지 않는다.

## 검증

- `tools/dev/verify.ps1`: Flutter doctor, analyze, 전체 Flutter 테스트.
- `test/features/workspace/workspace_test.dart`: 실제 앱 라우트 구성, OAuth 복귀 origin/path, 화면 이탈 취소/중복 방지, 한영 PC·모바일 배치, PC 인분 수정/저장.
- `tools/test/web_workspace_local.py`: 로컬 Auth의 두 계정과 같은 계정의 두 세션으로 서버 회원권, 공유 저장, revision 충돌, 타 계정 격리, 구매 소수 수량과 미입력 수량, 중복 생성 방지 검증. 생성한 계정은 finally에서 삭제한다. 결과는 `.artifacts/web-backend-verification.json`.
- `tools/test/web_workspace_browser.cjs`: 로컬 미리보기와 Playwright/Edge가 필요하다. 실제 이메일 로그인 → 내 레시피 → 셰프 인분 수정/저장 → 별도 세션 조회, 회원권 응답/웹 결제 안내, 한영 PC·모바일 화면을 검증한다. `SUPABASE_CLI`로 로컬 CLI 경로를 지정할 수 있다. 비밀키는 로컬 CLI 결과에서 메모리로만 읽으며 생성 계정은 finally에서 삭제한다.
- 브라우저 기록은 `.artifacts/web-browser.log`, 결과 JSON은 `.artifacts/web-browser-verification.json`에 남는다.

2026-09-15 검증 결과:

- 전체 Flutter: **323개 통과, 기존 선택형 4개 건너뜀** (`.artifacts/web-final-full-tests.log`).
- 이후 웹 회원권의 사용 불가능한 Play 구매/가격/오류 표시를 정리하고 **정적 분석 0건**, 관련 회원권 검사 **24개 통과** (`.artifacts/web-final-analyze.log`, `.artifacts/web-membership-tests.log`). 해당 변경은 웹 표시 분기에만 적용했다.
- 실제 로컬 백엔드: **8개 통과**, 두 테스트 계정 삭제 완료 (`.artifacts/web-backend-verification.json`).
- 최초 브라우저 자동화에서 Flutter 접근성 요소의 마우스 클릭 판정/입력 문제가 있어 키보드 입력·활성화로 검사 절차를 수정했다. 전체 Flutter 검사와 병행한 로컬 함수에는 CPU 제한 초과/503 기록이 있었으므로, 공개 운영 성능이나 성공률을 이 개발 환경으로 판단하지 않는다.


- 최종 정적 웹 빌드 성공 후 Edge 실제 브라우저 **8개 검사 통과**, 콘솔 오류 0건, 테스트 계정 삭제 완료. 로그인, 내 레시피 불러오기, 목표 인분 10→20 저장, 별도 세션의 revision 2/인분 20 조회, 회원권 정상 응답, 웹 구매 버튼/복원 버튼 미노출, 한영 1440px/390px 화면을 확인했다. 함수 첫 기동을 확인한 뒤 진행한 최종 단독 검사에서는 앞선 503이 재현되지 않았다.
- 실제 화면: `.artifacts/web-desktop-ko.png`, `web-chef-desktop.png`, `web-chef-mobile.png`, `web-desktop-en.png`, `web-mobile-en.png`, `web-membership.png`. 모두 합성 테스트 자료이며 실제 회원 자료가 아니다.

## 공개 전에 남은 작업

1. 호스팅 프로젝트/HTTPS 주소 확정 및 공개용 빌드 검증. `web/_headers`는 이를 지원하는 정적 호스팅용 템플릿이며 다른 서버에서는 동등한 응답 헤더를 설정한다. 현재 템플릿은 frame/object/base 제한을 제공하며 전체 script/connect 정책은 호스팅과 Flutter 렌더러를 정한 뒤 검증한다.
2. 운영 프로젝트의 웹 OAuth 복귀 주소 허용 및 Google/Kakao/복구 메일의 실제 로그인 시험. 기존 모바일 복귀 주소는 삭제하지 않는다.
3. 운영 웹에서 Business/무료 계정별 UAT, PDF 다운로드/외부 공유, 브라우저별 입력·키보드·접근성 검증, 배포 번들의 크기/첫 로딩 측정.
4. 웹 결제 공급자와 중복 구독 처리 정책은 별도 결정한다. 현재 Play 상품도 실제 결제 활성화가 남아 있으며 웹 신규 결제를 제공한다고 안내하지 않는다.

초기 웹은 온라인 작업을 전제로 한다. 오프라인 업무, 실시간 동시 편집, 웹 푸시 알림, 다매장/직원 권한은 이번 단계의 구현 범위에 포함하지 않는다. 홍보/검색 노출용 모집 사이트와 로그인 후 작업실은 분리해서 운영한다.
