SkinQuest v15.0.0 — uppgradering från en fungerande v14.6.2

INGET i paketet är driftsatt åt dig. Din live-databas, Steam-synk och Cron har
inte ändrats. Gör uppgraderingen när trafiken är låg och ha kvar v14.6.2 som
webbplatsbackup. Databasbackup behövs separat.

GÖR DETTA I ORDNING
1. Ta databasbackup i Supabase och backup på nuvarande webbplatsfiler.
2. Kör ENDAST skinquest_upgrade_existing_to_v15_0_0.sql i SQL Editor.
   Kör INTE skinquest_full_setup_v15_0_0.sql på din befintliga databas.
   Deltat förutsätter att v14.6.2-uppgraderingen redan har körts.
3. Uppdatera koden och deploya dessa TRE befintliga Edge Functions:
   survey-feed
   timewall-postback
   reward-order-status-notify
   Koden finns i supabase/functions/<namn>/index.ts. Verify JWT ska vara AV
   för just dessa funktioner. survey-feed kontrollerar inloggningen själv,
   status-notify kontrollerar inloggning OCH administratörsrollen och
   timewall-postback verifierar TimeWalls callback-hash.
4. Behåll befintliga CPX-, TimeWall- och mejl-secrets. Ingen ny secret behövs
   för Surveys i denna version. TIMEWALL_COINS_PER_USD ska fortfarande matcha
   TimeWalls placement, normalt 1000 i din befintliga installation.
5. Ladda upp hela webbplatsinnehållet, inklusive .htaccess, nya orders.html,
   surveys.html, earn.html, skinquest-v15.js/css, assets/providers/ och sw.js.
   Ladda helst upp versionerade JS/CSS och tillgångar före HTML-filerna, eller
   använd webbhotellets atomiska publicering. Låt .htaccess komma med:
   /surveys, /earn och /orders är tre olika sidor nu.
   Ladda inte upp SQL, dokumentation eller supabase-källkod som publika
   webbplatsfiler om webbhotellet låter dig välja; de är driftsättningsmaterial.
6. Ladda om efter att du avslutat eventuell pågående orderåtgärd. Testa med
   ett vanligt konto och med ägarkontot enligt checklistan längre ner.

DU SKA INTE ändra Steam Cron, steam-market-sync eller dess secret för v15.
CPX:s befintliga survey-postback och dess URL är oförändrade.

TIMEWALL SURVEYS
Den godkända placementen cbade60b064c1284 är förinställd i survey-feed:
https://timewall.io/users/login?oid=cbade60b064c1284&uid={user_id}
Funktionen ersätter {user_id} med den inloggade SkinQuest-användarens UUID.
Om du redan har TIMEWALL_IFRAME_URL_TEMPLATE använder den inställningen
företräde; kontrollera att den pekar på denna placement och innehåller exakt
en {user_id}, inte {UNIQUE_USER_ID}. Inget hemligt värde ska stå i mallen.
TimeWall öppnas först när användaren trycker på en startknapp. På mobil finns
också öppning i vanlig webbläsarflik; laddning av en iframe är inte ett bevis
på att en survey är genomförd eller ens att leverantörens inloggning fungerat.

Behåll redan konfigurerad TimeWall Surveys-postback:
https://ubvkupqgigfxehprsoit.supabase.co/functions/v1/timewall-postback?userid={userID}&txid={transactionID}&revenue={revenue}&hash={hash}&type={type}&original_txid={original_txid}
Makronas stavning måste matcha TimeWalls dashboard. Lägg aldrig Secret Key i
URL:en. Auto Redeem och survey-only-sektioner hanteras i TimeWall.

EARN — FÖRBEREDD, INTE AKTIVERAD NU
/earn är en separat sida för framtida tasks/övriga erbjudanden. Den visar
tydligt Not connected. Den återanvänder inte survey-only-placementen.
När du senare har en ANNAN godkänd TimeWall-placement för tasks:
- sätt TIMEWALL_EARN_URL_TEMPLATE med den andra placementens oid och
  exakt en {user_id} i uid-parametern;
- sätt TIMEWALL_EARN_SECRET_KEY till den placementens egen Secret Key;
- använd samma callback ovan men med &placement=earn på slutet;
- aktivera relevanta sektioner i TimeWall, undvik dubbla surveys i båda väggarna;
- verifiera en riktig callback och källmarkering innan du publicerar den.
Backend kräver separat placement-id och konfigurerad Earn-secret innan den
returnerar en Earn-länk. Skicka inte secret-värden hit.

LEVERANSER OCH ORDERS
Admin > Shared deliveries: markera flera ej skickade ordrar från SAMMA kund,
skapa en leveransgrupp och gör en gemensam statusuppdatering. Varje order
behåller sitt eget sparade coin-pris, historik och kund. En ogiltig order gör
att hela gruppuppdateringen stoppas utan delvis ändrade ordrar. Återbetalning
görs på respektive order, inte som en blind massåtgärd.
Trade locked = bekräftelse att du köpt varorna. Utan egen tid blir sluttiden
exakt 192 timmar från sparningen. Det är er standard, INTE en kontroll mot
Steam. Använd den riktiga upplåsningstiden för varje föremål om den skiljer
sig. En blandad grupp med lagerföremål kan inte massmarkeras Trade locked.
Gamla upplåsningstider ändras INTE av SQL-uppgraderingen. Att bara gruppera
ordrar startar inte om deras lås. Att spara en ny Trade locked-gruppåtgärd
utan egen tid sätter däremot ett nytt gemensamt 192-timmarslås: gör det bara
om det faktiskt motsvarar inköpet.
Kundens /orders visar status, nästa steg, sparat pris och registrerad
upplåsningstid/nedräkning. Nedräkningens slut är inte ett löfte om omedelbar
leverans. Admin får inte markera Ready to trade före registrerat låsslut.
Kundens ändrade tradelänk flaggas på ej skickade ordrar. Staff måste granska
och godkänna aktuell länk innan Trade sent. En redan skickad orders
tradelänksnapshot skrivs aldrig om av en ändring i Settings.
Samlade statusmejl kräver den uppdaterade reward-order-status-notify och era
befintliga fungerande mejl-secrets. Ett gruppmejl listar alla sparade orders
och priser. Misslyckat mejl rullar inte tillbaka en lyckad statusuppdatering.
Resend-idempotency skyddar överlappande försök i sitt begränsade tidsfönster;
SQL-markörer sparar skickad gruppstatus. Ingen obegränsad exactly-once-garanti.
En eventuell separat gammal reward-order-ready-sweep kan fortfarande skicka
individuella mejl när den själv körs; den funktionen och dess schema ändras inte.
Reward orders-badgen räknar Needs action: pending/reviewing/ordered/ready.
Trade locked och Trade sent finns kvar i All active orders men kräver inte
nya beställningsåtgärder just nu.
Ett utgånget lås eller en ändrad tradelänk på en Trade locked-order räknas
däremot som Needs action. Det ska granskas, inte döljas som vanlig väntan.

STATISTIK OCH BEGRÄNSNINGAR
Admin > Users > konto: tre separata källor med registrerade öppningar,
visningar, godkända reward-events, coins och reverserade events.
Owner > Earning statistics: per källa och totalt, periodfilter och dagsrader.
Samma positiva ledgerpost och dess callback räknas bara en gång. Äldre
CPX-märkta ledgerposter kan användas när callback-logg saknas.
Verified reward events är INTE säkert antalet fullständiga surveys: en
provider kan ge exempelvis ersättning för screen-outs eller deluppgifter.
Recorded opens mäter era startkontroller; alla klick inne i en tredjeparts-
iframe/CPX-widget kan inte observeras. Saknade historiska klick återskapas
inte. Nya mätpunkter börjar först när nya webbplatsfilerna används.
Reported callback revenue visar endast verkliga USD-fält som finns i sparade
callbacks. CPX kan sakna USD-fält i er integration: då står Not reported och
antal saknade intäktsfält visas. Inga påhittade USD från användarnas coins.
Totala unika användare är avduplicerade över källorna. Summan av unika
användare PER källa kan därför vara större än det gemensamma totalantalet.
Detta är INTE kontant utbetalning eller vinst. Verkliga betalningar och
kostnader fortsätter hanteras separat i Finance & funding.

TIMEWALL RISKMODELL ÄR KVAR
Gränser: högst 5000 coins per TimeWall-credit och 15000 per användare under
rullande 24 timmar. Hold/hold_cancelled ger inga coins; chargeback reverserar
ursprungseventet. Ett reverserat event kan inte krediteras igen med samma id.
TimeWalls hash täcker inte alla callback-fält, bland annat transaktions-id.
Ett korrekt hashvärde plus nya id:n är därför inte kryptografiskt skyddat mot
all replay. Kontrollera verkliga TimeWall-transaktioner och USD per användare
innan ni köper/skickar Steam-föremål. Ingen automatisk skin-leverans införs.

KORT LIVETEST EFTER UPPGRADERING
- Vanligt konto: CPX laddar, TimeWall öppnar rätt placement, logout tömmer
  iframe, Earn säger Not connected, andra användares order-URL visar inget.
- En riktig godkänd TimeWall-survey: rätt kund/coins och källan Surveys.
  Återlevererat samma provider-event ska inte betala igen. Inte syntetiska
  signerade testcredits i produktion.
- En liten leveransgrupp: kontrollera sparade priser, gemensamt kundmejl,
  riktig Steam-tid, ändrad tradelänk och individuell coin history.
- Mobil: Safari/Chrome samt installerad PWA på riktig iPhone/Android. Testa
  kamera/notch, öppet tangentbord, nav, redeem-bekräftelse och orders.
- Owner-statistik syns bara för owner; klick/coins stämmer mot nya loggar.
- Steam-importens framsteg och Cron fortsätter enligt ert befintliga schema.

Lokala tester är dokumenterade i RELEASE_CHECKS_v15_0_0.txt. Ingen testsvit
har gjort riktiga provider-callbacks, skickat mejl eller ändrat er live-databas.
