SkinQuest v9.4

What changed:
- Added auth-confirm.html for email confirmation redirects.
- Signup now sends users to auth-confirm.html after clicking the Supabase email link.
- Added a profile fallback RPC call so normal users can redeem even if their profile row was missing.
- Added clearer redeem error messages for normal users.
- Added admin coin adjustment tool for testing friends' accounts.
- Added cache-busting ?v=94 to app.js/styles.css links.
- No assets folder is included. Keep your existing assets folder in GitHub.

Supabase steps:
1. Run skinquest_v9_4_supabase_patch.sql in Supabase SQL Editor.
2. Go to Supabase Authentication -> URL Configuration.
3. Set Site URL to your GitHub Pages site.
4. Add this redirect URL:
   https://YOUR-GITHUB-PAGES-URL/auth-confirm.html
   If your site is in a repo subfolder, use:
   https://YOUR-USERNAME.github.io/YOUR-REPO/auth-confirm.html

Testing:
- Ask a friend to confirm email, sign in, save Steam trade URL, and redeem a 1 coin test reward.
- If they have 0 coins, use Admin -> Adjust user coins to give them test coins.
