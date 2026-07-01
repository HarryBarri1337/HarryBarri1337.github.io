SkinQuest v11.8 - Reward filters & settings polish

Install:
- Upload these files over the current site.
- Keep your existing assets folder. This ZIP intentionally does not include assets.
- The header logo expects: assets/interface/skinquestlogo.png

What changed:
- Made the SkinQuest logo slightly larger in the header.
- Replaced the reward price dropdown with typed Min coins / Max coins inputs.
- Replaced the rewards availability dropdown with smooth pill filters.
- Replaced the rewards sort select with a custom animated sort menu.
- Added reward results count and a Clear filters action.
- Added browser-saved reward browsing preferences in Settings.
- Added account readiness, quick actions, and a cleaner security checklist in Settings.
- Reduced visible future-service wording in Settings.

SQL:
- skinquest_full_setup_v11_8.sql = full setup for a fresh Supabase project.
- skinquest_upgrade_v11_8_from_v11_7.sql = no-op upgrade marker. No database changes are needed from v11.7.
