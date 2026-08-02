SkinQuest v12.2.6

Release focus:
- Added five neutral campaign URLs: /01, /02, /03, /04 and /05.
- Every campaign URL serves the homepage while keeping the numbered path visible.
- GA4 can compare the links by landing page / page path without exposing platform names.
- Uses internal Apache rewrites, not redirects, so no UTM parameters appear in the browser.

Tracking in GA4:
- Reports > Engagement > Landing page, then search for /01 through /05.
- Realtime can be used to test each link immediately.

Deployment:
- Upload all files to the same web root as index.html.
- Make sure .htaccess is uploaded and replaces the previous version.
- No SQL changes are required.
