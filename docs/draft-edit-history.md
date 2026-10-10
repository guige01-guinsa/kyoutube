# 초안 편집 실행 취소·다시 실행

2026-09-12 소스 변경. 기존 v54 서명 AAB에는 포함되지 않는다.

초안 수정 후 저장으로 여는 레시피 편집 화면의 오른쪽 위에 왼쪽 화살표(실행 취소/Undo), 오른쪽 화살표(다시 실행/Redo)를 제공한다. 제목·요약·재료·단계·팁·YouTube 링크의 편집을 시간 순서로 최대 100건 복원한다. 되돌릴 작업이 없거나 저장 중이면 버튼을 비활성화한다.

글자 크기·굵기·색상, 커서/선택 영역을 함께 복원한다. 커서 이동만으로는 이력을 만들지 않는다. 실행 취소 뒤 새 편집을 하면 이전 다시 실행 이력을 지운다. 복원할 때 오래된 한글 IME 조합 범위를 제거한다. 저장된 서버 레시피를 되돌리거나 AI를 재호출하는 기능은 아니다. 화면을 닫으면 편집 이력은 끝난다.

핵심 코드: `recipe_edit_history.dart`, `advanced_recipe_text_field.dart`, `create_creator_recipe_page.dart`. 동작 검증: `recipe_edit_history_test.dart`, `recipe_edit_history_widget_test.dart`.

실제 UI 렌더: `.artifacts/draft-edit-ko.png`, `.artifacts/draft-edit-en.png`. 캡처는 Flutter 위젯 렌더이며 USB 휴대폰 실기기 캡처가 아니다.

검증 완료: 고정 Flutter 3.44.8로 `tools/dev/verify.ps1` 실행, analyze 문제 없음·전체 테스트 177개 통과. 별도 한글·영어 화면 캡처 2개 통과 후 아이콘을 눈으로 확인했다. 로그: `.artifacts/draft-edit-verify.log`, `.artifacts/draft-edit-capture.log`.
