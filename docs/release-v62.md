# Recipe Scout v62 — 2026-09-13

사용자 승인 범위: DB 0051·0052·0053 운영 적용 및 구매처 관리 기능을 포함한 v62 서명 AAB 생성.
운영 DB 적용과 v62 서명 AAB 생성·검증을 완료했습니다. Play Console 업로드와 휴대폰 설치는 수행하지 않았습니다.

## 사용자 변경 사항

- 장보기 도우미: 여러 목록의 미구매 재료 확인, 구매처 검색/상품 링크 저장, 보유량 확인과 실제 구매 기록.
- 구매 요청서: 목록의 재료를 선택해 수량·단위·납품 정보를 작성하고 한영 텍스트/PDF로 공유. 받는 사람과 최종 전송은 사용자가 공유 앱에서 선택합니다.
- 반복 요청서 복제와 전달·업체 수락·입고 상태의 수동 기록. 공유 호출을 결제/업체 수락/재고 반영으로 간주하지 않습니다.
- 내 구매처 관리: 온라인 쇼핑몰·동네 매장·협력업체 추가/수정/삭제, 웹사이트·연락처·주소·개인 메모, 검색과 즐겨찾기, 해당 업체를 선택한 요청서 작성.
- 개인 구매처 메모·주소·웹사이트·즐겨찾기 설정은 요청서 데이터와 공유 문서에서 제외합니다. 납품 주소는 요청서에서 따로 입력합니다.
- 구매처 관리·요청서는 무료/유료 로그인 회원이 사용할 수 있습니다. 기존 셰프 원가/매출의 유료 제한은 유지합니다.

## 운영 DB 적용 완료

- 대상 프로젝트: `dfczeudklykypysiseck`.
- 2026-09-13 21:07 KST에 0051 `shopping_assistant`, 0052 `supplier_purchase_requests`, 0053 `shopping_supplier_directory`를 한 트랜잭션으로 적용했습니다.
- DDL·권한 검증·적용 이력을 함께 기록했고, 서버의 마이그레이션 SQL 3개가 로컬 원본과 일치합니다.
- 기존 재고 수량이 numeric(18,6) 변환 범위를 벗어나거나 정밀도를 잃는 행이 없음을 적용 전에 확인했습니다.
- 네 테이블의 RLS·소유자 정책, 제한된 수정 열, authenticated RPC 권한, 익명 권한 제거, URL 제약과 자료형 검증을 통과했습니다.
- 실제 REST API에서 네 테이블이 인식되고 익명 조회가 각각 HTTP 401 / PostgreSQL 42501로 차단되는 것을 확인했습니다.
- 테스트 계정·주문·구매·재고 데이터를 운영에 생성하지 않았습니다. 로그인한 실제 회원의 저장/공유/입고 전체 흐름은 단말 확인이 필요합니다.
- 다른 마이그레이션 이력은 전후 동일합니다. 보류된 0047·0048은 적용하지 않았고 Edge Function·비밀값·예약 실행 설정도 변경하지 않았습니다.
- 증거: `.artifacts/v62-db-preflight.json`, `.artifacts/v62-db-deployment.json`, `.artifacts/v62-production.sql`, `.artifacts/v62-http-verification.json`.

마이그레이션 원본 SHA-256:

- 0051: `c424d9eb3f0e29f0fc8a6138363a1558001dff1e4c3358b47525a0274c7dfb0b`
- 0052: `ca0a0f38a3219ea2a8154b1743dc04a9ecdd5d9505516db45e1a86716f06b82e`
- 0053: `6d78a353e3ca2360d35660a7523974b04a4992dca1d70841f3e2dcd461cbe5d0`

## 출시 검증

- 고정 Flutter 3.44.8 / JDK 17. 운영 환경 및 기존 업로드 서명 설정 사전 점검 통과.
- 출시 게이트 정적 분석 오류 없음(143.9초). Flutter 전체 테스트 266개 통과·기존 선택형 테스트 4개 건너뜀(4분 26초).
- Android 릴리스 빌드 성공(Gradle 468.9초). 이전 v61에서도 기록된 CupertinoIcons 글꼴 경고가 로그에 남아 있습니다. 실제 단말 시각 확인은 별도입니다.
- 앞선 로컬 DB 장보기·구매처 관리·구매 요청서 계약 검사 통과 및 전체 트랜잭션 롤백.
- 실제 휴대폰 카카오톡 파일 수신, 실제 구매/입고 및 Play 테스트 트랙 설치 확인은 남아 있습니다.
- 공개 개인정보처리방침과 Play 데이터 보안 신고는 새 배포 범위에 맞춰 확인해야 합니다. 저장소의 정책 문서는 갱신했고 공개 사이트/Play 양식 게시는 수행하지 않았습니다.

## AAB

- [recipe-scout-v62.aab](../release/recipe-scout-v62.aab)
- 패키지 `com.kyoutube.app`, 버전 `1.0.1+62`, 환경 `production`.
- 크기 **72,414,036 bytes** (약 69.1 MiB).
- SHA-256: `27868A557CD5CF9331E7A70F5ADDD9C810EC6BC11FBBCB9EA75874E1A370FD14`.
- 기존 v61 업로드 서명 인증서 일치, jarsigner·ZIP 무결성·매니페스트·빌드 출처 해시 검증 통과.
- 디버그/앱 백업 비활성화, 주소록/마이크 권한 없음. 공유 Provider는 외부 공개 없이 수신 앱에 URI 접근 권한을 부여하도록 설정됐습니다.
- 한글 PDF 글꼴과 OFL 라이선스가 AAB에 원본과 동일하게 포함됐습니다. 실제 Gemini 키가 AAB에 포함되지 않았음을 메모리 검사로 확인했으며 키 값은 출력하지 않았습니다.
- [검증 기록](../release/verify-v62.json), [빌드 출처](../release/recipe-scout-v62.aab.provenance.json).
- [한국어 출시 안내](../release/recipe-scout-v62-notes-ko-KR.txt), [영어 출시 안내](../release/recipe-scout-v62-notes-en-US.txt).
- 빌드 기록: `.artifacts/release-v62-build.log`. DB 0051·0052·0053은 운영 적용 완료이므로 앱 업데이트 후 새 저장 기능을 사용할 수 있습니다.

참고: [장보기 도우미](shopping-assistant.md), [구매 요청서](supplier-purchase-requests.md), [내 구매처 관리](shopping-store-management.md).
