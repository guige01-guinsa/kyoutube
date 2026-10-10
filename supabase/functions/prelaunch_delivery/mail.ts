import { signClaim } from "../prelaunch_growth/security.ts";
export type Job = {
  id: string;
  lease_id: string;
  lead_id: string;
  version: string;
  email: string;
  kind: "confirm" | "welcome" | "tip";
  locale: "ko" | "en";
  created_at: string;
  expires_at: string;
  newsletter: boolean;
};
export async function mail(
  job: Job,
  secret: string,
  site: string,
  senderNotice: string,
) {
  const en = job.locale === "en";
  const claim = {
    u: job.lead_id,
    v: job.version,
    e: Math.floor(new Date(job.created_at).getTime() / 1000) + 7 * 86400,
  };
  const url = new URL(site);
  url.searchParams.set("lang", job.locale);
  const withdraw = new URL(url);
  withdraw.hash = "withdraw=" +
    await signClaim(secret, {
      ...claim,
      p: "withdraw",
      e: Math.floor(new Date(job.expires_at).getTime() / 1000),
    });
  let subject: string;
  let text: string;
  if (job.kind === "confirm") {
    url.hash = "confirm=" + await signClaim(secret, { ...claim, p: "confirm" });
    subject = en
      ? "Confirm your Recipe Scout request"
      : "레시피 스카우트 신청을 확인해 주세요";
    text = en
      ? `You requested Recipe Scout beta and launch invitations. Confirm your email within 7 days:\n${url}\n\nIf this was not you, ignore this email or remove the request below.`
      : `레시피 스카우트 출시·베타 초대 안내를 신청하셨습니다. 7일 안에 이메일을 확인해 주세요.\n${url}\n\n직접 신청하지 않았다면 이 메일을 무시하거나 아래에서 삭제할 수 있습니다.`;
  } else if (job.kind === "welcome") {
    url.hash = "worksheet";
    subject = en
      ? "Your Recipe Scout request is confirmed"
      : "레시피 스카우트 신청이 확인되었습니다";
    text = en
      ? `Your email is confirmed. We recorded your request for beta and launch invitations. This does not grant app access or start a subscription.\nYou can use the public menu-cost worksheet now:\n${url}`
      : `이메일 확인을 완료했고 출시·베타 초대 안내 신청을 기록했습니다. 현재 앱 이용 권한이나 유료 구독이 생성된 것은 아닙니다.\n공개 메뉴 원가 계산 체험은 지금 이용할 수 있습니다.\n${url}`;
  } else {
    if (!job.newsletter) throw new Error("Consent required");
    url.hash = "worksheet";
    subject = en
      ? "[AD] Recipe Scout: try one menu cost calculation"
      : "(광고) 레시피 스카우트: 메뉴 하나의 원가부터 확인해 보세요";
    text = en
      ? `You opted in to practical tips and promotional email.\nTry one dish: enter ingredient spending, edible yield and portions, then compare a cost markup. Confirm actual labor, rent, tax and waste costs separately.\n${url}`
      : `실무 팁·프로모션 이메일 수신에 동의하셔서 보내드립니다.\n메뉴 하나의 재료비, 손질 수율, 인분을 입력하고 원가 가산율을 바꿔 보세요. 인건비·임대료·세금·추가 손실은 실제 운영 기준으로 따로 확인해 주세요.\n${url}`;
  }
  text += `\n\n${senderNotice}\n${
    en
      ? "Withdraw this request / unsubscribe (no login):"
      : "신청 철회·이메일 수신 거부 (로그인 불필요):"
  }\n${withdraw}`;
  return { subject, text };
}
