# Android R8 최적화 — v85

## 변경 이유

Play Console v84 경고: DEX 최적화 낮음, 난독화2%, 최적화/축소 비율 미표시, R8 메타데이터 없음. 원본 v84 AAB는 DEX12,067,960 bytes이며 R8 JSON과 매핑이 없다. android/app/build.gradle.kts에서 minify/shrinkResources가 false로 명시되어 있었다.

## 변경 범위

- release의 isMinifyEnabled / isShrinkResources를 true로 변경.
- 고정 Flutter3.44.8 플러그인이 주입하는 proguard-android-optimize.txt, Flutter 규칙 및 Android 라이브러리의 consumer rules 유지.
- 임의의 전체 패키지 keep, dontwarn, dontoptimize, dontobfuscate 규칙을 추가하지 않음.
- AGP9.0.1/JDK17/Gradle9.1.0 유지. 라이브러리·서명·패키지 ID·권한·업무 로직 변경 없음.
- 기존 아이콘 문제의 재발을 막기 위해 --no-tree-shake-icons 및 AAB 자산 검증 유지.
- pubspec 버전1.0.1+85. 운영 웹/DB/함수 배포 불필요.
- tools/release/verify-aab-optimization.ps1에서 최종 AAB의 R8 JSON, 난독화 매핑과 DEX가 존재하고 비어 있지 않은지 필수 검사. 이 구조 검사가 Play 점수나 실제 기기 기능 검사를 대신하지 않는다.

## 검증 및 배포 원칙

전체 Flutter 분석/테스트, 서명 AAB 빌드, bundletool 구조 검사, 실제 DEX의 플러그인 진입점, 기존 글꼴/서명 유지, R8 메타데이터와 DEX 크기를 확인한다. 최종 결과: DEX87.2% 감소, 분석·648개 테스트 통과, AAB/서명/글꼴/16개진입점 검사 통과. 상세 제한은 [release-v85.md](release-v85.md)에 기록했다.

연결된 SM-G977N(Android12/API31)은 Google Play v82가 설치되어 있고 Play 앱 서명과 로컬 업로드 서명이 다르다. 직접 덮어쓰기 설치를 시도하거나 기존 앱을 삭제/초기화하지 않았다. Play 내부 테스트로 v85를 업로드한 뒤 동일 계정으로 테스트에 참여해 업데이트하여 실제 로그인·사진/파일 선택·공유/PDF·알림·구매/복원·식단 저장을 확인해야 한다. 유료 결제/주문 발송은 사용자 승인 없이 테스트하지 않는다.

v84는 사용자가 제공한 화면에서 프로덕션 심사 제출이 확인됐다. 이 최적화 작업은 해당 심사를 취소하거나 v84를 삭제하지 않는다. v85 운영 출시 완료 또는 무위험 상태라고 표현하지 않는다.

## 공식 근거

- https://developer.android.com/topic/performance/issues/code-optimization
- https://developer.android.com/topic/performance/app-optimization/enable-app-optimization
- https://developer.android.com/topic/performance/app-optimization/test-the-optimization
- https://support.google.com/googleplay/android-developer/answer/17492799?hl=ko

2027년2월 최소 기준은 DEX10MB 초과 일반 앱에 적용된다. 화면의 난독화2%는 앱 속도가2%라는 뜻이 아니다. R8 JSON의 코드별 수치, DEX 전체 크기 감소율, 사용자 체감 속도는 서로 다르다.
