# Google Play 출시 준비 — 현재 기준 2026-10-02

최신 확인 산출물은 **v94 (1.0.1+94)**다. [산출물 기록](release-v94.md)과 [신규 보완·외부 검증 대기 목록](completeness-hardening-20261002.md)을 먼저 확인한다. 운영 배포, Play 업로드/심사, 실제 결제/알림 검증은 AAB 파일 생성과 별도로 확인해야 한다. 연결된 휴대폰의 설치본은 v86이며 최신 소스 실기기 검사는 아직 수행하지 않았다.

아래 v53 표는 당시 이력이며 현재 출시 완료를 의미하지 않는다.

## v53 이력

갱신: 2026-09-12. Android com.kyoutube.app, 1.0.1+53.

후속 v54 서명 AAB가 생성되었다. 아래 표는 v53 기준 기록이며 최신 산출물은
[CURRENT_STATUS.md](CURRENT_STATUS.md)와 [v54 안내](release-notes-v54-ko.md)를 따른다.
v54의 중앙 운영 기능은 운영 DB·함수 적용 대기 상태다.

| 항목 | 확인 상태 |
| --- | --- |
| 서명 AAB | 완료: release/recipe-scout-v53.aab 및 provenance JSON |
| v53 검사 | analyze 오류 없음·Flutter 테스트 164개 통과 |
| 서명·버전 | 이전 업로드 인증서 일치·versionCode 53 |
| 홈·튜토리얼 | 한식 영상 10종·한/영 8개 학습 과정 포함 |
| 영문 AI 초안 | 사용자 실사용 확인 |
| Play 업로드·승격 | 별도 확인 필요 |
| 구매·FCM 실기기 | 별도 확인 필요 |
| 중앙 관측 | 후속 소스 구현·기존 v53 미포함·배포 전 |

해시·빌드 증거는 [현재 상태](CURRENT_STATUS.md) 참조. 과거 AOT/서명 차단은 현재 출시 차단 사유가 아니다.

## 출시 조건

- [ ] 승인된 테스트 트랙에 정확한 파일 업로드·처리·설치.
- [ ] 현재 Console 운영 액세스·테스터 조건 확인. 과거 테스터 수·트랙 버전을 현재 값으로 사용하지 않음.
- [ ] [내부 검사](internal-track-release-checklist.md)·[UAT](staging-uat-checklist.md) 완료.
- [ ] Play 구매·복원·갱신·취소·환불·만료 및 서버 권한 회수 검증.
- [ ] 공개 개인정보·계정 삭제 URL이 비로그인 브라우저에서 열리고 앱과 일치함.
- [ ] Data safety·권한·타깃 SDK·등급·국가·이미지가 실제 파일 및 현재 Console 요구사항과 일치함.
- [ ] 실제 TTS 비활성 상태에 맞춰 홍보 문구 점검.

후속 운영 기능은 [운영 안내서](OPERATIONS_RUNBOOK.md)의 DB·함수·신규 앱·보관 정리·정책 적용을 함께 진행한다. 같은 versionCode로 v53을 교체하지 않는다. 빌드는 승인 후 [보호 스크립트](AAB_RELEASE_RUNBOOK.md)로만 실행한다. iOS 출시는 이 Android 판정 범위 밖이다.
