SkinQuest v14.5.5 — upgrade from live v14.5.4
================================================
1. Back up your Supabase database.
2. Run ONLY skinquest_upgrade_existing_to_v14_5_5.sql.
   Do not run the full setup on an existing project.
3. Upload the website files and hard-refresh Admin.

No Edge Function, Cron, or secret changes.

Users now shows:
- Date created: actual auth account creation date, not profile migration date.
- Verified CPX rewards: existing unique offerwall_events with provider cpx and
  current status completed. Pending, rejected, and reversed events are excluded.
  The stored callback does not distinguish full survey completions from all
  screen-out compensation; therefore this is NOT labelled Surveys completed.
- CPX opens: observable authenticated launch clicks on Open CPX Research since
  v14.5.5. This is NOT an individual survey-open counter inside the cross-origin
  CPX widget. No historic open counts are fabricated. Page loads and widget
  rendering do not increment it. Counts are client-observed analytics, not proof
  of completion. Existing analytics write limits still apply.

Role/login filters, coin sorting, pagination and global user search are retained.
Activity counts appear under each user's details with explanatory text.

Fresh projects use skinquest_full_setup_v14_5_5.sql.
Local JavaScript and package checks passed. SQL consistency was checked locally;
live database execution, permissions and CPX analytics require deployment tests.
No live site or database was changed while preparing this archive.
