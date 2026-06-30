SkinQuest v11.3

Changes from v11.2:
- Added a proper data-loading state so wallet/dashboard values do not flash as 0 before Supabase data loads.
- Re-enabled a subtle top loading bar for page/auth/data transitions.
- Dashboard and Settings now keep account content hidden until real user/profile data is prepared.
- Home wallet preview uses dash placeholders instead of fake 0 values during session checks.
- Mobile header is forced onto one row: SkinQuest brand, menu button, and account area.
- Mobile header hides the nav coin pill to avoid wrapping; full wallet remains on Dashboard.
- Added more spacing under Settings pills/labels.
- Updated planned Google/Steam sign-in labels from 11.5 to v12.

Notes:
- Admin access still requires inserting your user UUID into public.admin_users.
- Coin logo path remains assets/interface/coin_logo.png.
- Reward images should use web paths like assets/rewards/cases/recoil.png.
