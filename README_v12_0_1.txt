SkinQuest v12.0.1

Release focus
- Light polish release after v12.0.0.
- Keeps the main SkinQuest interface colors consistent across map themes.
- Makes map themes slightly more visible through background mood, glows, borders, and theme selector cards.
- Reduces navigation/profile flicker between pages.
- Cleans up Settings Steam connection layout.

What changed
- Version references updated to v12.0.1.
- Cache-busting updated to styles.css?v=1201 and app.js?v=1201.
- Added an early inline theme loader in HTML so the saved map theme is applied before CSS renders.
- Added lightweight cached navigation rendering so the account area does not jump as much during auth refresh.
- Moved Steam connected status into a proper green pill layout in Settings.
- Renamed the main navigation label from Earn to Surveys while keeping earn.html as the URL.
- Updated changelog with v12.0.1 notes.

Completed setup notes
The following setup work has already been completed in the live project and should not be re-run unless the Supabase project is rebuilt from scratch:
- Support notification setup
- Steam auth setup

SQL notes
- No database schema changes were made in v12.0.1.
- The upgrade SQL file is included only as a no-database-changes marker.
- The full setup SQL file is included as the current full setup baseline.

Expected external assets
These files are expected to already exist in assets/interface/ and are not included in this release zip:
- skinquestlogo.png
- nuke-background.png
- train-background.png
- mirage-background.png
- dust2-background.png
- ancient-background.png

Not included in this release zip
- .git
- .github
- supabase
- assets
