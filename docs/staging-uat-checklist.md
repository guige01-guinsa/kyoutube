# Staging UAT Checklist

Last update: 2026-07-19

## Purpose
Use staging to catch P1/P2 issues before internal test promotion or production rollout.

## UAT rules
- Use a staging Supabase project and staging Firebase config.
- Clear local app data before the first run.
- Record every failure with screen, step, and exact message.
- Block promotion on any P1 issue.

## P1 defects
- App launch failure.
- Login or session recovery failure.
- Public recipe browse failure.
- Copy-to-my-recipes failure.
- Creator CRUD failure.
- Delete or undo failure that causes data loss.

## P2 defects
- Incorrect empty state.
- Missing loading state.
- Confusing error copy.
- Minor layout issues that do not block task completion.
- Notification/voice guide inconsistencies that have a workaround.

## UAT sequence
1. Fresh install and launch.
2. Login and logout.
3. Public recipe search and detail.
4. Copy to personal recipes.
5. Bookmark add/remove.
6. Creator create/edit/delete.
7. Personal note save/delete undo.
8. Voice guide start/stop.
9. FCM permission and token check.
10. Review ops report and close the session.

## Exit criteria
- No open P1 defects.
- Any P2 defects have a workaround or an approved fix date.
- All checklist items are signed off by QA or the product owner.
