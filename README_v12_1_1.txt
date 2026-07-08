SkinQuest v12.1.1

Release focus:
- Steam-only users now get a dashboard prompt to add a real email address.
- The email prompt uses Supabase Auth updateUser with email confirmation redirect to auth-confirm.html.
- Notification toggles were restyled as custom animated switches.
- Settings save buttons now show clearer Saving/Saved feedback.
- Version references updated to v12.1.1.
- Cache-busting updated to styles.css?v=1211 and app.js?v=1211.

Assets:
- Not included in this package.
- Keep your existing assets/interface files on the server.

Excluded from package:
- .git
- .github
- supabase
- assets

SQL:
- Full setup SQL is included.
- Upgrade SQL is included.
- No required database schema changes in v12.1.1 beyond the v12.1.1 notification views already used.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
