# v85 Android R8 최적화 및 AAB (2026-09-26)

사용자의 최적화 승인으로 Android 코드·리소스 최적화를 적용했다. **새 서명 AAB 생성 및 정적/구조 검증 완료, Play 업로드·실제 기기 업데이트·기능 검증 전** 상태다. 운영 웹은 v84이며 DB·함수·업무 로직을 변경하지 않았다. 무위험 또는 실기기 검증 완료라고 표현하지 않는다.

## 결과

| 항목 | v84 | v85 |
|---|---:|---:|
| 압축 전 DEX | 12,067,960 bytes | 1,544,840 bytes |
| DEX 파일 수 | 2 | 1 |
| 전체 AAB | 81,018,976 bytes | 78,239,272 bytes |
| R8 정보·난독화 매핑 | 없음 | 포함 |

DEX 크기 **87.2% 감소**. 이 수치는 앱 실행 속도 향상률이나 전체 다운로드 감소율이 아니다. 최종 DEX는 현재 공지된 일반 앱10MB 기준보다 작다. Play Console 표시 및 경고 해소 여부는 업로드 후 재확인이 필요하다.

R8 9.0.32 메타데이터: 최적화·난독화·축소 활성, release/full mode, optimized resource shrinking 활성. 제외 비율(noObfuscation7.57%, noOptimization8.89%, noShrinking7.54%)을 원본 JSON으로 보관했다. 이를 실제 삭제된 바이트 비율과 혼동하지 않는다.

## 산출물

- [서명 AAB](../release/recipe-scout-v85.aab): com.kyoutube.app / 1.0.1+85.
- [출시 문구](../release/recipe-scout-v85-release-notes.txt).
- [검증 보고서](../release/recipe-scout-v85-optimization.json).
- SHA-256: `659ac1aea7e4dbc75b0ec41dc01a70b54eed593eafa9d63b1723b9c03f7c5533`.

## 검증

- 고정 Flutter3.44.8/JDK17. 분석 성공, 전체 Flutter **648개 통과·기존 조건부4개 제외·실패0**.
- R8 릴리스 빌드 성공. Google bundletool1.18.3 validate 성공.
- 최종 AAB의 버전85·버전명1.0.1·패키지 ID 및 jarsigner 서명 검증 성공.
- v84와 업로드 인증서 동일. 한국어/MaterialIcons 폰트·FontManifest 바이트 동일. Flutter 엔진 등을 포함한 네이티브 라이브러리9개 바이트 동일(libapp.so는 APP_BUILD85로 재컴파일).
- 실제 DEX class definitions와 난독화 매핑을 비교:13개 Flutter 플러그인 및 MainActivity·GeneratedPluginRegistrant·FlutterJNI 총16개 진입점 존재. 이는 동적 기능의 실기기 테스트를 대신하지 않는다.
- AAB 자산·R8 JSON/매핑·DEX 필수 검사. R8의 세 최적화 옵션 활성과 release mode 확인.
- 검증기 회귀12개: 실제84/85 버전, 고의 버전 불일치, 원본 미최적화 AAB 거부, 최적화 AAB 수락, JSON/매핑/DEX 누락·손상·비활성 거부.
- 빌드 이후 앱 관련324개 입력 해시가 동일함을 확인했다.
- flutter doctor의 기존 전역SDK PATH, Android 라이선스 상태, Windows 개발도구 구성 경고3종은 남아 있으나 고정 도구 릴리스 빌드는 성공했다.

## 발견하여 수정한 릴리스 검사 문제

첫 빌드는 AAB 생성과 R8/글꼴 검사를 통과했지만, 검증기가 최적화 전의 오래된 중간 Manifest(84)를 읽어 전달을 차단했다. 공식 bundletool로 실제 AAB가85임을 확인했다. 검증기를 최종 패키지 직접 검사로 바꾼 뒤 실제84/85 및 불일치 회귀검사를 통과했다.

앱 빌드 입력이 바뀌지 않았음과 전체 테스트 성공을 확인하고 일회성 .artifacts/release-v85/finalize-verified-build.ps1로 검증/서명/복사 단계만 재개했다. 일반 build-production-aab.ps1의 분석·전체 테스트·빌드 검사는 유지한다. 이후 변경은 검증 스크립트와 문서뿐이다.

## 연결된 휴대폰과 다음 단계

SM-G977N(Android12/API31), Google Play에서 설치한82번. 로컬 업로드 서명과 실제 Play 설치 서명이 다름을 값 출력 없이 비교했다. 기존 앱을 삭제·초기화·교체하지 않았다. bundletool로 이 기기의 사양에 맞는 APK 5개가 포함된 설치 세트를 생성했다. 이 APK 세트는 디버그 서명된 **로컬 구조 검증용**이며 배포하거나 설치하지 않는다.

휴대폰 데이터를 보존한 검증 경로: **Play Console → 테스트 및 출시 → 테스트 → 내부 테스트 → 새 버전 만들기 → v85 AAB 업로드 → 테스트 출시 → 해당 테스터 계정으로 Play 업데이트**. 기존에 내부 테스트 대상에 포함되어 있고 참여한 계정을 사용한다.

그 후 로그인/콜백, 사진·파일 선택, 저장·재실행, PDF·공유, 알림, 구매/복원과 업소 식단 작성·확정·구매 준비를 확인한다. 실제 결제나 주문 발송은 승인 없이 진행하지 않는다. 검증한 뒤 프로덕션으로 승격한다. 이번에 Play 업로드는 수행하지 않았다. 사용자 화면에서 v84 프로덕션 심사 제출은 확인되었으며 그 심사를 취소하지 않았다.

[상세 변경 범위](android-r8-optimization.md). 증거는 .artifacts/release-v85/의 빌드·doctor·최종검증·게이트검사·기기호환 보고서다.
