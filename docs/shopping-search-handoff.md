# Shopping search handoff

Status: local changes, not deployed. Production remains v75; the previously prepared staff-management migration 0064 is still separate and pending release approval. No schema, credentials, affiliate IDs, or package-version changes.

## Behavior

- Shopping assistant tabs use wrapping choices with short labels (구매 준비 / 구매 기록 / 저장 상품). Ingredient actions keep a 48px minimum touch area.
- Find a store opens an account-scoped, scrollable dialog. The shopper can edit the product name and optionally add a package size or brand, then choose Naver or Google Shopping.
- Total purchase quantity is reference only. It is not silently treated as a package size, converted from cooking units, or appended to the search.
- Android/iOS Naver searches use `https://msearch.shopping.naver.com/search/all?query=…`; other platforms use the desktop host. The mobile host is also visible in the user's supplied screenshot.
- Google uses `/search?q=…&tbm=shop&hl=ko|en`. It no longer forces the English phrase “buy groceries” onto Korean ingredient names. The language follows the app, without forcing a purchase country.
- Links still launch via the existing externalApplication provider directly from a button press. Search links contain product terms only, without user/workspace identifiers. Existing saved product links retain HTTPS validation and direct opening.
- A failed launch preserves the dialog and provides an exact retry-link copy action. Search-term copy supports using another browser or shopping app. Editing terms clears any stale failure link.
- Opening, copying, cancelling and switching accounts never creates a purchase record. Recording a purchase remains a separate user action.
- Webpage text-size/desktop-view help is collapsed by default. Browser settings and third-party webpage layouts cannot be altered by Recipe Scout. No user-agent spoofing, cookie collection or injected JavaScript was added.

## Verification and remaining device check

Unit and widget checks cover encoded Korean/English terms, explicit package-size terms, empty input, mobile Naver hosts, Google shopping mode, safe saved links, launch failures, cancellation and account isolation. Layout checks use 320px width with 200% text and 360px with 115% text in Korean and English.

External search pages rejected automated page inspection in this environment. Actual search availability, checkout and layout under the reported Samsung Internet configuration still need a device check; passing URI/widget tests does not establish those outcomes. Browser instructions describe settings to inspect, not a confirmed diagnosis of the user's browser.

## Affiliate revenue (proposal only)

The current links are plain search URLs and generate no configured affiliate revenue. No affiliate links, tracking or program enrollment were added in this change.

Naver Shopping Connect issues eligible product links and settles revenue from attributed orders. Recipe Scout's independent app/web placement must be confirmed with the program before integration; SNS/creator eligibility alone is not approval of an app placement. Rates, cancellations, attribution and settlement depend on the agreement.

Google's documented YouTube Shopping affiliate program is for eligible YouTube creators and tagged products. It should not be represented as revenue from a generic Google Shopping search link.

Recommended future model: keep ordinary search; separately label approved partner products, offer negotiated member benefits, and reconcile commission only from confirmed partner transactions. Do not count clicks or the user's manual purchase-history entry as an affiliate settlement. Keep user-selected price/quality ordering independent of commission.

Sources checked 2026-09-19:

- [Naver Shopping Connect](https://help.naver.com/service/30027/contents/24098?osType=COMMONOS)
- [Naver link placement and disclosure guidance](https://help.naver.com/service/30027/contents/24104?osType=COMMONOS)
- [Naver official launch details](https://www.navercorp.com/media/pressReleasesDetail?seq=33116)
- [YouTube Shopping affiliate eligibility](https://support.google.com/youtube/answer/13376398?hl=ko)
- [Google Shopping product surfaces](https://support.google.com/merchants/answer/13889434?hl=en)
- [Samsung Internet browser release notes](https://developer.samsung.com/browser/release-note/android-release-note.html)

## Validation result (2026-09-19)

- Focused shopping domain/widget tests: 21 passed.
- Real-font UI checks: 12 passed; final tab contrast and initial dialog capture: 2 passed. Korean/English 360px/115% and 320px/200% previews were visually reviewed.
- Full `tools/dev/verify.ps1`: doctor and analyzer passed; the suite completed with 492 passed, 4 existing skipped, and 1 failure for newly introduced Korean literals missing from the central translation catalog.
- Added 17 missing catalog entries. Reran the entire localization test file: 3 passed, including the initially failing whole-presentation-source scan. Analysis of the final changed catalog: no issues.
- The full suite was not repeated after this isolated catalog fix; no other failing tests were reported. No known unresolved failures remain. Release-build checks must still run in the normal release workflow.
- No production DB changes, web deployment, release AAB generation, external purchase, affiliate enrollment or partner messages were performed.

Evidence: `.artifacts/shopping-search-focused.log`, `shopping-search-visual.log`, `shopping-search-final-visual.log`, `shopping-search-verify-final.log`, `shopping-search-localization.log`, `shopping-search-catalog-analyze.log` and `shopping-search-validation.json`.
