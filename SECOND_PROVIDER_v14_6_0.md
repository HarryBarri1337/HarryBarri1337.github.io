# Second earning provider — what to do next

Checked 13 September 2026. CPX remains the only active provider in this release.
No account application has been sent for you, and no unapproved provider has been added to the live site.

## 1. Apply to Torox first

My recommendation is based on product fit, not guaranteed approval or revenue. Torox's publisher FAQ explicitly gives game skins as an example of rewards bought with a platform's virtual currency. It supports a web offerwall and says publishers can choose offer categories. Confirm SkinQuest's exact model with their team before integration. [Torox publisher FAQ](https://torox.io/faq-monetise/)

1. Open [Torox registration](https://torox.io/register/) and choose **I'm a Publisher**, not Advertiser.
2. Website link: `https://skinquestcs.com`.
3. Use your real name/contact details and operating country. If you have a registered company, use its legal name; do not invent a company.
4. Daily active users and monthly revenue: use actual analytics/provider statements, not total registrations, coin balances or guessed numbers.
5. Business description (under the form's 255-character limit):

   SkinQuest is a CS2 reward website. Users complete verified partner tasks, earn coins and redeem fixed items through reviewed Steam trades. No deposits or random rewards. We seek a web offerwall with free tasks.

The publisher form currently asks for website, daily active users, monthly revenue and business description. Fields may change. [Registration form](https://torox.io/register/)

After applying, ask the publisher team:

- Do you approve fixed CS2 skin/case redemption through manually reviewed Steam trades?
- Which free offers are available to our real countries, devices and permitted age groups? Confirm age rules rather than assuming all users qualify.
- Can purchases, subscriptions, paid trials, deposits and gambling offers be excluded completely?
- What are the payout threshold, currency, payment cycle, fees and reversal rules for this account?
- How are callbacks signed/verified? How are duplicate callbacks, multi-step rewards and chargebacks identified?
- What user-share and currency-conversion settings will preserve SkinQuest's actual economics?

Do not enable offers with payment requirements while the site advertises free earning.

## 2. Lootably is a second application option

Lootably documents an application-and-approval step before creating a placement. An account/signup alone is not evidence of approval. If you already applied, check that account or follow up instead of making duplicate accounts. [Getting started](https://documentation.lootably.com/docs/getting-started-1)

- New application: [Lootably publisher signup](https://dashboard.lootably.com/authentication/signup).
- Once approved: create a website placement for SkinQuest.
- Currency names can be `coin` and `coins`, but conversion and user share must be calculated using the provider's actual settlement currency and payout terms. Do not copy Steam's EUR conversion blindly into USD provider settings.
- A verified postback integration is required for real completion information. [Placement settings](https://documentation.lootably.com/docs/configuring-your-placement)

Ask the same skin-redemption, age/country, free-offer and callback-security questions as above. I have not verified acceptance or actual offer availability for your account.

## What to send me after approval

Send the provider name, approval status and non-secret placement/application ID. Keep signing secrets and API keys private and put them in Supabase's configured secrets when an integration is ready; do not paste them into chat.

Then we can build and verify:

1. A provider launcher with the authenticated SkinQuest user ID.
2. A server-verified callback; browser messages never credit coins.
3. A unique provider/event ledger to prevent duplicate credits, with safe reversals.
4. Provider-labelled coin history, support context and honest availability states.
5. Separate staging tests for completion, duplicate callback, rejection and reversal.
6. Only after approval and successful tests, activate the provider for customers.

Until then, leave CPX, the existing provider secrets and Steam Cron alone.
