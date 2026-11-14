# Amministrazione e assistenza

Stato operativo e versioni: [V1-STATUS.md](V1-STATUS.md). Admin-console v4 è distribuita nel progetto corretto; il titolare è assegnato all’allowlist privata. Google e profilo reale sono provati. TOTP personale rinviato: console completa e metriche reali restano da collaudare.

## Ingresso dedicato

Dopo Google aprire Profilo. Solo l’account con indizio server e conferma dell’allowlist riceve **Accesso Admin**. Prima del secondo fattore non compaiono dashboard o ticket. Utenti ordinari, anche Premium, non ricevono questa sezione o una Console demo.

Il titolare completa TOTP nella pagina e nella propria app. QR, chiave e codici restano sui suoi dispositivi, mai in chat, screenshot, log o checkpoint. Non creare un fattore al suo posto. Dopo 15 minuti serve una nuova verifica per operazioni privilegiate.

## Controlli server

- private.platform_admins è autorevole e inaccessibile ai client. Email nel browser, pulsanti e user_metadata non concedono Admin.
- RPC: account confermato/non bloccato, allowlist attiva, sessione viva, fattore verificato e aal2 recente. Revoca ruolo/sessione/fattore impedisce le operazioni successive.
- L’Edge usa JWT del chiamante e chiave pubblica; non service-role per aggirare RLS.
- Quote, audit e transazioni proteggono letture/modifiche. Metriche aggregate; recapiti ticket solo se forniti volontariamente. Ricerca e risultati limitati.
- Risposte no-store e cache della shell pubblica. Logout/cambio account invalidano anche lo stato nascosto e risposte tardive.

Le sonde cloud di Host/Sportivo ordinari rifiutano RPC privilegiate; il titolare senza secondo fattore riceve mfa_required. Fixture SQL/Edge non provano TOTP personale.

## Provisioning in un nuovo ambiente

L’account attuale è già assegnato: non ripetere provisioning per aprire la console.

In un nuovo ambiente autorizzato completare Google/profilo, verificare ID/email e predisporre nel solo contesto privato SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TROVAT1O_ADMIN_USER_ID, TROVAT1O_ADMIN_EMAIL:

```sh
node scripts/promote-admin.mjs
```

Lo script verifica corrispondenza ID/email e chiama provisioning server. Non passare segreti come argomenti o salvarli nel repository. Per una revoca autorizzata usare TROVAT1O_ADMIN_ACTION=revoke: allowlist aggiornata prima dell’indizio metadata. Conservare audit ed eventuale successione amministrativa.

## Configurazione e limiti

APP_ORIGIN ed eventuale origine collaudo HTTPS esatti, senza wildcard. Metriche utilizzo API richiedono opzionalmente token Management minimo e riferimento progetto nei soli segreti server. Senza di essi il dato risulta non disponibile; non è CPU in tempo reale.

Support-request e migrazione assistenza restano da attivare con Turnstile reale e conferma tecnica valida. Modificare un ticket non invia automaticamente email. [Assistenza](SUPPORT-SETUP.md).

Il sorgente candidato aggiunge cancellazione revisionata dietro tre gate false; il gestore distribuito v4 non si aggiorna tramite merge GitHub. Le 44 prove Edge del sorgente usano trasporti controllati, senza attestare cancellazione nel progetto gestito. [Cancellazione](ERASURE-REQUESTS.md).

Non eseguire sul remoto popolato vecchi test che esigono zero utenti. Prove sintetiche isolate e rollback non raccolgono fattori personali o inviano email/SMS.
