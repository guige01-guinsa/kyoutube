// Labels for explicit inventory and receiving workflows.
const businessInventoryUiTranslations = <String, String>{
  '단위 환산': 'Unit conversion',
  '사용 가능': 'Available',
  '규격': 'Specification',
  '이 입고에서 반품 가능한 잔량': 'Remaining returnable quantity from this receipt',
  '재고 품목 등록': 'Add stock item',
  '실사·재고 조정': 'Count & adjust stock',
  '조리용 예약': 'Reserve for cooking',
  '실제 사용 기록': 'Record actual use',
  '남은 예약 해제': 'Release remaining reservation',
  '품목 입고 기록': 'Record item receipt',
  '반품 기록': 'Record return',
  '입고 마감': 'Close receiving',
  '현재고': 'On hand',
  '예약량': 'Reserved',
  '재고·조리 예약': 'Stock & cooking reservations',
  '실제 입고·반품·조리 사용을 기록해 재고를 관리합니다. 예약은 다른 작업이 사용할 수량을 확보하며, 판매 기록만으로 재고가 차감되지는 않습니다.':
      'Record actual deliveries, returns and cooking use. Reservations hold quantities for a task; sales records alone do not deduct stock.',
  '재료명·규격·단위 검색': 'Search ingredient, specification or unit',
  '일치하는 재고 품목이 없습니다.': 'No matching stock items.',
  '수불·예약 보기': 'View movements & reservations',
  '사용 대기 중인 예약': 'Reservations awaiting use',
  '남은 예약이 없습니다.': 'No remaining reservations.',
  '품목별 입고·반품': 'Item receipts & returns',
  '품목을 검수한 뒤 실제 도착한 양만 입력하세요. 구매 단위와 재고 단위가 다르면 환산량을 직접 확인합니다.':
      'Inspect each item and record only the quantity actually delivered. Confirm the conversion when purchase and stock units differ.',
  '구매요청서 확인': 'Review purchase request',
  '이전 방식으로 입고 완료한 요청입니다. 과거 입고는 재고에 자동 반영되지 않습니다. 실제 보유량은 재고 화면에서 실사 조정으로 기록하세요.':
      'This request was completed with the earlier receipt workflow. Past receipts are not imported into stock. Record an actual stock count in inventory.',
  '마감 사유': 'Closing reason',
  '마감 후 반품은 기록할 수 있습니다. 교환·추가 입고는 새 요청서로 관리하세요.':
      'Returns remain available after closing. Use a new request for replacements or further deliveries.',
  '취소 전에 입고한 재고는 그대로 남아 있습니다. 실제 반품했다면 아래 입고 이력에서 반품을 기록하세요.':
      'Stock received before cancellation remains on hand. Record actual returns against the receipt history below.',
  '입고 기록만으로 요청서가 마감되지는 않습니다. 잔량과 반품을 확인한 뒤 마감하세요.':
      'Receipts alone do not close the request. Review outstanding quantities and returns before closing.',
  '요청량': 'Requested',
  '누적 입고': 'Total received',
  '반품량': 'Returned',
  '순입고': 'Net received',
  '미입고': 'Outstanding',
  '재고 수불 이력': 'Stock movement history',
  '기록된 수불이 없습니다.': 'No recorded stock movements.',
  '현재고 증감': 'On-hand change',
  '예약 증감': 'Reservation change',
  '구매 1단위': 'purchase unit',
  '사용 가능 재고가 부족합니다. 최신 입고·예약량을 확인하세요.':
      'Available stock is insufficient. Review current receipts and reservations.',
  '재고 품목·단위 환산을 확인하세요. 첫 입고 이후에는 같은 품목과 환산량을 사용합니다.':
      'Check the stock item and unit conversion. Later receipts must use the same item and conversion as the first receipt.',
  '미입고 수량보다 많이 입력했습니다. 최신 입고·반품을 확인하세요.':
      'This exceeds the outstanding quantity. Review current receipts and returns.',
  '이 입고 기록에서 반품할 수 있는 수량을 초과했습니다.':
      'This exceeds the quantity still returnable from this receipt.',
  '용도·사유를 1~500자로 입력하세요.': 'Enter a purpose or reason using 1–500 characters.',
  '미입고 잔량을 확인하고 마감 여부를 선택하세요.':
      'Review and accept outstanding quantities before closing.',
  '남은 예약량을 확인하고 다시 입력하세요.':
      'Check the remaining reservation and enter the quantity again.',
  '요청 상태가 변경됐습니다. 품목별 입고 화면에서 최신 상태를 확인하세요.':
      'The request state changed. Review the latest item receipts.',
  '이 구매요청을 취소로 기록할까요? 업체와 별도로 확인해 주세요. 이미 입고한 재고는 유지되며 실제 반품은 따로 기록합니다.':
      'Record this request as cancelled? Confirm with the supplier separately. Received stock is retained; record actual returns separately.',
  '0이 아닌 수량을 소수 6자리 이내로 입력하세요.':
      'Enter a nonzero quantity with up to 6 decimal places.',
  '확인 항목을 체크해 주세요.': 'Check the confirmation box.',
  '필수 입력입니다.': 'This field is required.',
  '권한 확인 중': 'Checking access',
  '재료명·규격·재고 단위가 같으면 기존 품목을 사용합니다. 단위는 나중에 바꿀 수 없으므로 실제 관리 단위로 등록하세요.':
      'Matching names, specifications and units reuse an existing item. Units cannot be changed later; choose the unit you actually track.',
  '재고 단위': 'Stock unit',
  '현재고에 더하거나 뺄 차이 수량을 입력합니다. 기초 재고·실사 차이·폐기 등 사유를 남기세요. 예약량보다 현재고를 낮출 수 없습니다.':
      'Enter the quantity to add or subtract, with a reason such as opening count, count discrepancy or waste. On-hand stock cannot fall below reservations.',
  '메뉴·조리 일정 등 용도를 적고 필요한 양을 예약하세요. 실제 조리한 뒤 사용량을 별도로 기록합니다.':
      'Describe the menu or cooking schedule and reserve the quantity needed. Record actual use after cooking.',
  '남은 예약': 'Remaining reservation',
  '이 입고 기록에서 실제 반품한 양을 입력하세요. 이미 반품한 양과 예약 재고를 제외한 범위만 기록할 수 있습니다.':
      'Enter the quantity actually returned from this receipt. Previous returns and reserved stock limit the available return quantity.',
  '반영할 재고 품목': 'Stock item to update',
  '재고 품목을 선택해 주세요.': 'Select a stock item.',
  '구매 1단위당 재고량': 'Stock quantity per purchase unit',
  '이번 수량': 'Quantity this time',
  '재고 증가량': 'Stock increase',
  '실제 품목·수량·단위 환산을 확인했습니다.':
      'I verified the actual item, quantity and unit conversion.',
  '마감 후에는 이 요청에 추가 입고할 수 없습니다. 반품은 기존 입고 이력에서 기록하며, 교환·추가 납품은 새 요청서로 관리합니다.':
      'After closing, this request cannot receive further deliveries. Record returns against existing receipts and use a new request for replacements or additional deliveries.',
  '미입고 잔량을 확인하고 마감합니다.':
      'I accept the outstanding quantity and close receiving.',
  '용도·사유': 'Purpose / reason',
  '저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 저장하면 중복 기록되지 않습니다.':
      'The save result is uncertain. Retrying the same content will not create a duplicate.',
  '기록 저장': 'Save record',
  '재고·중복 요청 확인': 'Check stock & overlapping requests',
  '재고와 예약은 계속 바뀝니다. 조회한 가용량 중 이번 조리에 쓸 양만 아래에 입력하세요. 이 화면은 재고를 예약하지 않습니다.':
      'Stock and reservations can change. Enter below only the available quantity allocated to this cooking task. This screen does not reserve stock.',
  '같은 이름·규격·단위의 재고가 없습니다.':
      'No stock matches this name, specification and unit.',
  '조회 시 사용 가능': 'Available when checked',
  '진행 중 요청': 'Open requests',
  '같은 재료를 기준으로 만든 진행 중 요청을 최대 5개 표시합니다. 작성 후 수정됐을 수 있으므로 실제 품목·납품일을 확인하세요. 입고 예정량은 자동 차감하지 않습니다.':
      'Up to 5 open requests originally based on this ingredient are shown. They may have been edited; check actual items and delivery dates. Incoming quantities are not deducted automatically.',
  '최신 재고·요청 다시 조회': 'Reload current stock & requests',
  '입고·반품·실사·예약·조리 사용량을 함께 확인합니다.':
      'Review receipts, returns, stock counts, reservations and cooking use.',
};
