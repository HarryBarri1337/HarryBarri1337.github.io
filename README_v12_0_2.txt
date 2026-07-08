SkinQuest v12.0.2

Release focus
- Release-polish version after v12.0.1.
- Keeps the main SkinQuest interface colors consistent across map themes.
- Makes map themes slightly more visible without turning the whole UI into that map color.
- Reduces AI-looking heavy typography by keeping bold mainly for headings, buttons, badges, and key stats.
- Makes the header logo slightly larger while keeping the navbar balanced.
- Moves Themes above Notifications in Settings.

What changed
- Version references updated to v12.0.2.
- Cache-busting updated to styles.css?v=1202 and app.js?v=1202.
- Added lighter typography polish so regular text, descriptions, and small copy feel less over-bold.
- Increased the brand logo size a little, with responsive sizes for tablet and mobile.
- Strengthened theme mood slightly through background glow, subtle header/page accents, and theme cards.
- Kept the default SkinQuest interface colors stable instead of recoloring the whole interface per map.
- Moved the Theme settings panel above Notifications.
- Added extra navbar/profile stability CSS to reduce layout movement while auth refreshes.
- Updated changelog with v12.0.2 notes.

Completed setup notes
The following setup work has already been completed in the live project and should not be re-run unless the Supabase project is rebuilt from scratch:
- Support notification setup
- Steam auth setup

SQL notes
- No database schema changes were made in v12.0.2.
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
