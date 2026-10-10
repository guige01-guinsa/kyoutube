# 영어 초안 생성 안정성 개선

목표는 영어 검색부터 편집 가능한 초안 생성까지 90% 이상 성공하는 것이다. 2026-09-12 사용자 승인으로 서버 수정본을 운영 배포했다. 실서비스 90% 달성은 아직 확인하지 않았으며 생성 성공과 조리 정확도는 따로 측정한다.

## 실기기 관찰

USB 기기 SM-G977N / Android 12 / 앱 1.0.1+54에서 사용자가 제공한 화면으로 다음을 확인했다.

- 실패 화면: `invalid_selected_video`에 해당하는 영상 정보 오류. 영어 화면에서 한국어가 섞여 표시됨. 정확한 영상 링크 및 제목은 추가 확인 대기.
- 성공 화면: `Three Bibimbap Variations` 영어 초안 편집 화면. 전체 재료·단계, 선택 영상, 소요 시간은 제공되지 않아 조리 정확도는 미평가.

영상이 서로 다르고 전체 시도 횟수를 모르므로 두 화면으로 성공률을 계산하지 않는다. 사전 평가표의 기능 결과는 아직 채우지 않았다.

## 수정 내용

| 영역 | 이전 | 수정 |
| --- | --- | --- |
| 검색 언어 | 실제 검색 경로에서 기본 ko/KR 사용 | 앱과 동일하게 기기 언어 en이면 en/US, 나머지는 ko/KR. 요청마다 확인 |
| 제목 검증 | 영어 요청에 남은 한국어 홍보 문구를 서버가 거부 | 클라이언트와 서버에서 홍보 문구 정리. 기존 v54 요청도 서버 수정으로 처리 가능 |
| 간단한 요리 | 3재료·3단계 미만 거부, 프롬프트에서도 개수 요구 | 2재료·2단계 요리 허용, 근거 없는 항목 추가 금지 |
| 편집 가능한 응답 | 빈 요약을 서버가 성공 처리하지만 앱은 거부 | 빈 요약 및 중복 재료·단계를 보정 대상으로 분류. 한 번 보정 후에도 부족하면 실패 처리 및 사용량 미차감 |
| 오류 언어 | 동적 오류 문구가 부분 번역됨 | 해당 오류 전체 번역 및 서버 en-US 오류 응답 추가 |

서버의 영상 ID·URL 일치, 지원 언어, 길이, 영상 시간, 로그인·할당량 검증은 유지했다. 원문과 다른 수량·온도·시간을 완전히 판별하는 기능을 추가한 것은 아니다. 누락된 근거는 경고와 null로 남기며, 조리 정확도 검토를 생략하지 않는다.

## 검증 근거

- 운영 함수를 읽기 전용으로 `.artifacts/deployed-youtube-review`에 다운로드했다. 로컬 비교에서 영어 `Bibimbap` 제목은 기존/수정 모두 입력 검증 통과, `초간단 Bibimbap`은 기존 소스가 400 거부하고 수정 소스는 통과했다.
- 비교는 API 키 없이 검증 단계까지만 실행했다. 결과의 503 `ai_not_configured`는 의도된 로컬 환경이며 실제 운영 설정 오류가 아니다. `.artifacts/english-title-validation-comparison.json` 참조.
- Deno 44개 회귀 테스트 통과: `.artifacts/english-reliability-deno.log`. 7개 새 사례에 제목 정리, 간단한 요리, 빈 요약·중복 보정, 지속 실패 미차감, 잘못된 영상 ID 거부가 포함된다.
- 초기 Flutter 검사에서 기기 언어 모의 설정을 읽지 못한 테스트 2개가 실패했다. 앱과 같은 `WidgetsBinding.platformDispatcher`를 사용하도록 수정했고 검색 전용 5개 테스트가 통과했다.
- 최종 Flutter 분석은 문제 없음, 전체 테스트 179개 통과. 전체 재검증 결과는 `.artifacts/english-reliability-final-tests.log`, 분석 로그는 `.artifacts/english-reliability-final-analyze.log`에 기록했다.
- 단일 함수 배포 패키지의 실제 진입점 타입 검사 통과: `.artifacts/english-hotfix-check.log`. 패키지 handler.ts와 회귀 테스트한 소스의 SHA-256이 일치한다.

## 운영 반영 결과

`.artifacts/english-draft-hotfix`는 운영 중인 index.ts와 membership.ts를 그대로 사용하고 수정된 handler.ts만 교체한 단일 함수 패키지다. 사용자 명시적 승인 후 ai_youtube_recipe_assistant를 **버전 24 → 25**로 배포했다. ACTIVE, verify_jwt=true를 확인했으며 실제 운영 소스를 다시 다운로드해 3개 파일 모두 manifest.json의 SHA-256과 일치함을 확인했다. 익명 POST는 HTTP 401로 차단된다. 로그인한 사용자의 실제 AI 생성 성공률을 검증한 결과는 아니다.

배포 전 소스는 .artifacts/v55-before, 배포 후 소스는 .artifacts/v55-after에 보관했다. .artifacts/v55-english-deploy.json, v55-deployed-source-check.json, v55-function-auth-smoke.json에 증거를 기록했다. 데이터베이스 마이그레이션 및 미배포 운영 관측 기능은 이 함수 패키지에 포함하지 않는다.

기존 v54 AAB는 보존한다. 승인된 v55 앱에는 영어 검색/제목/오류 표시 수정, 편집 실행 취소·다시 실행 아이콘, 셰프 작업실이 포함된다. 서명 빌드의 최종 상태와 검증은 CURRENT_STATUS.md 및 release-notes-v55-ko.md를 확인한다.

## 90% 검증 절차

`tools/test/english-phone-cases.csv`의 40개 검색어를 고정해 각각 첫 시도 결과와 시간을 기록한다. 검색 성공, 편집 화면 진입, 조리 근거 일치 여부를 분리하고 재시도 성공을 첫 시도 성공으로 바꾸지 않는다. 36/40은 관측 생성률 90%이며 일반적인 90% 보장은 아니다. 현재 도구로 휴대폰 화면을 직접 조작할 수 없어 앱 조작 및 생성 결과 제공은 사용자 협조가 필요하다.
