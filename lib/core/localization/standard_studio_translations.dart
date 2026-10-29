// Admin interface labels only. Produced scripts and media remain Korean-only.
const standardStudioTranslations = <String, String>{
  "영상 주소로 원고 자동 준비": "Automatically prepare a script from a video URL",
  "음식 이름과 기준 유튜브 주소만 입력하세요. 원문 정보가 부족하면 같은 음식의 한국어 영상 최대 5개를 확인하고, 레시피가 공개된 한 영상으로 기준을 변경합니다. 적합한 영상이 없으면 멈춥니다.":
      "Enter the dish and source YouTube URL. If source information is missing, check up to five Korean videos of the same dish and select one with a published recipe. Stop if none qualifies.",
  "입력한 영상의 원문 정보가 부족하여, 레시피가 공개된 같은 음식의 한국어 영상으로 기준을 변경했습니다. 아래 기준 영상과 원고를 확인해 주세요.":
      "The requested video lacks source information. The reference was changed to a Korean video of the same dish with a published recipe. Review the selected video and script below.",
  "처음 요청한 영상": "Originally requested video",
  "유튜브 영상 주소를 확인해 주세요.": "Check the YouTube video URL.",
  "다음 화면에서 원고 준비 비용을 확인합니다. 영상 제작과 업로드는 아직 시작하지 않습니다.":
      "Confirm script preparation costs next. Video production and upload have not started.",
  "원고 자동 준비": "Prepare script automatically",
  "원고 준비 상태를 확인하지 못했습니다. 새로고침 후 확인해 주세요.":
      "Could not check script status. Refresh and check again.",
  "즉시 실행 요청을 전달했습니다. 진행 상태는 새로고침으로 확인하세요.":
      "Immediate execution requested. Refresh to check progress.",
  "작업은 저장됐지만 즉시 실행 연결은 확인되지 않았습니다. 정기 실행을 기다릴 수 있으므로 새 제작 요청을 반복하지 마세요.":
      "The task is saved but immediate execution is unconfirmed. Scheduled execution may take time; do not submit another production request.",
  "기존 한국어 여성 목소리로 제작합니다. 새 시험 음성 청취는 생략합니다.":
      "Use the existing Korean female voice without listening to a new sample.",
  "확인한 원고로 자동 제작": "Produce automatically from the reviewed script",
  "원본 레시피 직접 입력": "Enter original text manually",
  "원본 레시피로 한국어 3분 이내 영상 한 편을 제작합니다.":
      "Produce one Korean video up to three minutes from the original recipe.",
  "안녕하세요. 오늘은 원본 영상의 분량과 순서대로 함께 요리해 볼게요.":
      "Hello. Today we will follow the quantities and steps in the original video.",
  "재료표와 원본 영상을 함께 확인하며 한 단계씩 따라 해 보세요.":
      "Follow each step with the ingredient list and original video.",
  "원본 유튜브 주소": "Original YouTube URL",
  "원본 영상 제목": "Original video title",
  "채널 이름": "Channel name",
  "원본의 인분 표시": "Original serving size",
  "재료와 원본 분량 · 한 줄에 하나씩": "Ingredients and original quantities, one per line",
  "원본 조리 순서 · 한 줄에 한 단계씩": "Original cooking steps, one per line",
  "인사말": "Introduction",
  "마무리 말": "Closing narration",
  "유튜브 원본으로 3분 이내 기획": "Plan a source-based video up to three minutes",
  "재료의 양·단위·선택 사항과 조리 순서를 원본 그대로 옮겨 주세요. 약간은 약간으로 유지합니다. 저장은 무료이며 음성·영상 제작 전에 비용을 확인합니다.":
      "Copy original quantities, units, options and steps without alteration. Keep approximate amounts as written. Saving is free; confirm costs before voice or video production.",
  "원본 내용을 입력하세요.": "Enter the original content.",
  "재료는 2~24줄, 한 줄 100자 이내로 입력하세요.":
      "Enter 2 to 24 ingredient lines, up to 100 characters each.",
  "조리 순서는 1~12줄, 한 줄 160자 이내로 입력하세요.":
      "Enter 1 to 12 cooking steps, up to 160 characters each.",
  "원본 영상과 재료·분량·단위·선택 사항·조리 순서가 같은지 대조했습니다.":
      "I checked the ingredients, quantities, units, options and steps against the original video.",
  "새 그림 생성 없이 재료표·조리 안내 중심으로 제작합니다. 원고 확인 후 처리 목표 5분이며, 외부 서비스와 대기 시간에 따라 더 걸릴 수 있습니다.":
      "Use ingredient and cooking cards without new illustrations. Target processing is five minutes after script review; services and queues can add delays.",
  "따뜻하고 또렷한 한국어 여성 진행자. 원본의 계량과 조리 순서를 바꾸지 않는다.":
      "Warm, clear Korean female presenter. Preserve the original quantities and cooking order.",
  "원고 저장": "Save script",
  "원본 영상을 열지 못했습니다. 주소를 확인해 주세요.":
      "Could not open the original video. Check the URL.",
  "한국어 레시피 제작소": "Korean recipe studio",
  "한국어 · 원본 레시피 → 원고 확인 → 음성 → 3분 이내 영상 검토":
      "Korean: source recipe, script review, voice, video review up to three minutes",
  "재료와 조리 순서는 원본 그대로 사용합니다. 제작 처리 목표 5분 · 대기·외부 서비스 지연은 별도 확인합니다. 공개 게시와 유료 재시도는 자동 실행하지 않습니다.":
      "Preserve original ingredients and steps. Target processing is five minutes; track queue and service delays separately. No automatic public posts or paid retries.",
  "유튜브 원본으로 3분 기획": "Plan three minutes from a YouTube source",
  "기존 1분 시험 기획": "Legacy one-minute pilot",
  "기준 유튜브 원본 영상 보기": "Open the original YouTube reference",
  "원본 레시피 영상 제작 · 3분 이내": "Produce source recipe video, up to three minutes",
  "5분 목표 달성": "Five-minute target met",
  "5분 목표 달성 미확인": "Five-minute target not confirmed",
  "레시피 영상 · 원고와 완성본": "Recipe videos: scripts and completed previews",
  "유튜브 원본의 재료와 순서로 제작하고, 완성 영상을 여기에서 확인하세요.":
      "Use the original YouTube ingredients and steps, and find finished previews here.",
  "원고 편집·영상 제작 열기": "Open script editing and production",
  "제작소를 열어 관리자 인증과 연결 상태를 확인해 주세요.":
      "Open the studio to check admin authentication and connection.",
  "미리보기를 열지 못했습니다. 제작소에서 다시 확인해 주세요.":
      "Could not open the preview. Check it in the studio.",
  "레시피 제작·완성 영상": "Recipe production and completed videos",
  "작업 기록": "Job history",
  "한국어 1분 제작": "Korean one-minute production",
  "한국어 1분 제작소": "Korean one-minute studio",
  "새 음식 · 한국어 1분": "New dish · one minute in Korean",
  "아름답고 단정한 한국인 할머니. 따뜻하고 또렷한 여성 목소리, 가벼운 유머. 실존 인물을 모사하지 않는다.":
      "An elegant Korean grandmother with a warm, clear female voice and gentle humor. Do not imitate a real person.",
  "한국어 시리즈": "Korean series",
  "한국어 시리즈가 필요합니다.": "A Korean series is required.",
  "음식 이름": "Dish name",
  "음식 이름을 입력하세요.": "Enter the dish name.",
  "진행자·목소리·지킬 설정": "Presenter, voice and story guidelines",
  "설정을 입력하세요.": "Enter the guidelines.",
  "기획 저장은 무료입니다. 유료 작업은 견적 확인 후 별도로 시작합니다.":
      "Saving a plan is free. Paid tasks start separately after estimate confirmation.",
  "기획 저장": "Save plan",
  "비공개 업로드 확인": "Confirm private upload",
  "작업 비용 확인": "Confirm task cost",
  "예상 예약액: USD": "Estimated reservation: USD",
  "실제 청구 상한이 아닙니다. 실패 작업도 예약액을 보존하며 자동 재시도하지 않습니다.":
      "This is not a billing cap. Failed jobs retain their reservations and are not retried automatically.",
  "첫 장면의 짧은 시험 음성만 생성합니다.":
      "Generate only a short voice sample for the first scene.",
  "한국어 60초 영상 한 편을 제작합니다.": "Produce one 60-second Korean video.",
  "확인한 영상만 비공개로 업로드합니다.": "Upload only the reviewed video as private.",
  "출처를 조사하고 한국어 원고를 작성합니다.": "Research sources and write a Korean script.",
  "미리보기를 열지 못했습니다. 다시 확인해 주세요.":
      "Could not open the preview. Please try again.",
  "한국어 원고 수정": "Edit Korean script",
  "수정하면 이전 시험 음성 승인은 해제됩니다. 출처 연결은 유지됩니다.":
      "Editing clears the previous voice sample approval. Source references are retained.",
  "제목을 입력하세요.": "Enter a title.",
  "읽어 줄 말": "Narration",
  "원고를 입력하세요.": "Enter the script.",
  "화면 글": "On-screen text",
  "화면 글을 입력하세요.": "Enter the on-screen text.",
  "한국어만 · 60초 · 원고 → 시험 음성 → 영상 → 비공개 검토":
      "Korean only · 60 seconds · script → voice sample → video → private review",
  "제작 서버 연결됨": "Production server connected",
  "운영 연결 대기 · 새 유료 작업은 잠겨 있습니다.":
      "Awaiting production connection · new paid tasks are locked.",
  "3분·5분 제작은 안정화 후 추가합니다. 공개 게시와 유료 재시도는 자동 실행하지 않습니다.":
      "Three- and five-minute formats will follow stabilization. Public posting and paid retries are never automatic.",
  "같은 요청 결과 확인": "Check the same request",
  "새 음식 기획": "Plan a new dish",
  "기존 제작소에서 한국어 시리즈를 먼저 만들어 주세요.":
      "First create a Korean series in the existing studio.",
  "예상 예약 USD": "Estimated reservation USD",
  "자료 조사와 원고 작성": "Research and write script",
  "원고 수정": "Edit script",
  "원고와 음식 정보의 출처를 검토했습니다.":
      "I reviewed the script and sources for the food information.",
  "첫 장면 시험 음성 만들기": "Create first-scene voice sample",
  "시험 음성 듣기": "Listen to voice sample",
  "직접 듣고 발음·속도·목소리를 확인했습니다.":
      "I listened and checked pronunciation, pace and voice.",
  "이 음성으로 제작": "Use this voice",
  "실제 앱 안내 화면 준비 중 · 유료 영상 제작은 아직 시작하지 않습니다.":
      "Preparing a real app guide screen · paid video production has not started.",
  "한국어 60초 영상 제작": "Produce Korean 60-second video",
  "영상 미리보기": "Preview video",
  "영상·음성·자막·음악을 확인했습니다.": "I reviewed the video, voice, captions and music.",
  "비공개 업로드": "Private upload",
  "실패·응답 유실 가능성이 있어 자동 재시도하지 않습니다. 작업 기록과 저장된 파일을 확인해야 합니다.":
      "The task may have failed or its response may be lost. No automatic retry; check the job history and saved files.",
};
