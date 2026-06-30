SkinQuest v11.1

Review/fix pass over v11.0 before opening.

Changes:
- Cache bumped to v=111.
- Support widget copy no longer exposes backend/dev wording.
- Support requests can now save to the new support_requests Supabase table when the final SQL is installed and the user is signed in.
- If support_requests is not available or the user is signed out, the widget falls back to copying a ready-to-send support draft.
- Settings notification switches now prefer saved profile values from Supabase, then browser fallback.
- Supabase SQL hardened with sequence grants and future linked_services/support_requests tables.
- README notes added for required custom assets.

Required custom assets still expected from your project:
- assets/interface/coin_logo.png
- assets/rewards/weapons/...
- assets/rewards/cases/...
