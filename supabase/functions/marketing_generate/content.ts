export const topics = {
  youtube: '3분 이내 요리 영상을 검색하고 원하는 레시피를 저장',
  shopping: '레시피의 재료를 확인하고 장보기 목록으로 정리',
  ingredients: '가지고 있는 재료로 레시피 검색',
} as const;

export function parseContent(value: unknown) {
  if (!value || typeof value !== 'object') throw new Error('invalid_content');
  const v = value as Record<string, unknown>;
  const valid = (s: unknown, max: number): s is string =>
    typeof s === 'string' && s.trim().length > 0 && [...s].length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(s);
  if (!valid(v.title, 80) || !valid(v.description, 2000) ||
    !Array.isArray(v.scenes) || v.scenes.length !== 3 ||
    !v.scenes.every(s => valid(s, 72))) throw new Error('invalid_content');
  return { title: v.title.trim(), description: v.description.trim(), scenes: v.scenes.map(s => s.trim()) };
}

export function buildPrompt(topic: keyof typeof topics) {
  return `한국어 앱 홍보 초안을 JSON으로 작성하세요. 사실 근거는 다음 기능 한 개뿐입니다: ${topics[topic]}.
앱 이름: Recipe Scout / 레시피 스카우트. 기능 사용법을 소개하는 24초 세로 영상입니다.
사용자 수, 할인, 가격, 건강 효과, 요리 시간, 지원하지 않는 기능을 만들지 마세요.
외부 레시피, 영상, 이미지, 음악을 복사하거나 검색하지 마세요. URL 및 해시태그는 넣지 마세요.
마지막 장면은 반드시 "채널 프로필의 링크에서 Recipe Scout 확인"으로 끝내세요.
형식: {"title":"80자 이내","description":"앱 기능 소개 2000자 이내","scenes":["첫 장면 72자 이내","둘째 장면 72자 이내","마지막 장면 72자 이내"]}`;
}
