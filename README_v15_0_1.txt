SkinQuest v15.0.1 — rättad navigation och reward-interface

Du har redan v15.0.0-webbplatsen och dess SQL. Gör bara detta:
1. Ta databasbackup.
2. Kör ENDAST skinquest_upgrade_existing_to_v15_0_1.sql.
   Kör inte full setup och kör inte v15.0.0-deltat igen.
3. Ladda upp nya webbplatsfiler inklusive nya skinquest-v151.css och sw.js.
   Tillgångar/JS/CSS först, HTML därefter eller atomisk publicering.
4. Ladda om och kontrollera Rewards, en enskild reward, Surveys och menyn.

INGA Edge Functions, secrets eller Cron-jobb ska ändras för v15.0.1.
Behåll de tre funktionerna från v15.0.0. reward-order-ready-sweep är inte ett
nytt krav och behöver inte installeras för denna uppdatering.

Vad som rättats:
- Huvudnavet visar Rewards/Surveys/Earn/My orders utan att pressa ihop loggan,
  länkar och konto. Dashboard och Admin nås via konto; mobilens Dashboard
  finns också i bottennavet. Hjälp finns i sidfoten.
- Alla fyra availability-filter är åtkomliga; de kan radbrytas i smala vyer.
- Kortare, lugnare sorteringsalternativ och en enda synlig fokusmarkering.
- Providerknappar heter CPX Research och TimeWall, utan dubbla survey-etiketter.
- Rewardbilden är inte sticky och följer inte med över underliggande innehåll.
- Enskild reward har enklare layout, ingen meny när endast en variant finns,
  ett huvudpris och inte samma pris på den valda variantens rad igen.
- Kort visar priset en gång, utan en extra total/remaining-prisrad och utan
  ytterligare Need X coins under knappen. Progress visar procent i stället.
- Sticker Slabs döljs från försäljningen och hoppas över av katalogimporten.

Sticker Slabs RADERAS INTE från databasen. Gamla ordernamn, coin-priser,
wallets, lager och historik behålls. Triggern hindrar även ett gammalt
sync-anrop eller en manuell Active-ändring från att publicera en Slab igen.
Vanliga stickers, cases, agents, charms och wear-varianter spärras inte.
Synkens befintliga cursor/schema lämnas kvar. Den normala importen fortsätter.

Lokala browser-/databastester är isolerade; inga riktiga mejl, trades eller
providerbetalningar har utförts. Se RELEASE_CHECKS_v15_0_1.txt.
Testa också Safari/Chrome och installerad PWA på era riktiga telefoner.
