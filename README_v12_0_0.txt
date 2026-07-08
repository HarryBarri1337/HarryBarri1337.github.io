SkinQuest v12.0.0

Theme and cleanup release.

What changed:
- Added selectable CS-inspired themes: Nuke, Train, Mirage, Dust2, and Ancient.
- Theme choices update the full-page background and interface color palette.
- Theme choices are saved locally in the browser with localStorage.
- Fixed the Steam Disconnect button not responding because it called the removed confirmAction helper.
- Removed the completed support notification setup instruction file from the release package.
- Updated changelog/version references to v12.0.0.

Required asset files:
Place these files in assets/interface/ before testing the themes live:
- nuke-background.png
- train-background.png
- mirage-background.png
- dust2-background.png
- ancient-background.png

Notes:
- site-background.png is no longer the active theme background target. Nuke uses nuke-background.png instead.
- The SkinQuest logo can stay at assets/interface/skinquestlogo.png. Replacing that file with a transparent version does not require code changes.
- No new Supabase SQL migration is required for v12.0.0.
- Support notification setup was already completed in v11.9.3, so SUPPORT_NOTIFY_SETUP_v11_9_3.txt is intentionally not included.

Release contents:
- Website HTML/CSS/JS files
- Changelog
- README_v12_0_0.txt
- Existing Steam auth setup notes and SQL reference files from v11.9.3, if you still want them for reference

Not included in this release zip:
- assets folder
- .git folder
- .github folder
- supabase folder
