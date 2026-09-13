SkinQuest v14.5.7 — interface correction from live v14.5.6
========================================================
Upload the website files, then hard-refresh the browser.
No SQL, Edge Function, Cron, or secret changes are needed for this release.

Changes:
- Entire user row opens its account: no View user action button.
- Native row buttons support mouse, touch, Enter and Space, with visible focus.
- Account identity, three totals and history have separately spaced cards.
- Explicitly styled text tabs replace browser-default history buttons.
- Back/refresh/copy controls styled consistently.
- Contextual empty states replace Showing 0 of 0 and irrelevant warnings.
- CPX data explanations appear only in the Survey results section.
- Compact mobile layout; tabs scroll horizontally within their own strip.

CPX counts, Last active, history RPCs, balances, orders and access checks
are unchanged from v14.5.6. Historical survey tracking limits still apply.
Local browser QA uses mock accounts and does not access your live database.
Desktop and mobile were rendered and inspected; whole-row mouse/Enter/Space,
tab styling, card spacing, account switching and overflow checks passed locally.

Only brand-new installations use skinquest_full_setup_v14_5_7.sql.
The upgrade file is comments only because this release changes no database schema.
