# Stato corrente — 13 novembre 2026, collaudo multiutente

Questa sezione prevale sullo storico conservato sotto. Stato dettagliato: **V1-STATUS.md**.

- **Collaudo cloud:** https://v1-check-trovato.diegolucentedesign.workers.dev/, `1.0.0-cloud-test.11`, Cloudflare `efaa577e-d2aa-47ba-bbae-92c2c06ef11f`. Candidato sorgente `1.0.0-rc.8`, cache pubblica v22. Il principale resta `1.0.0-rc.1`, preview locale: nessun nuovo traffico di produzione è stato attivato.
- **Due account Google e due profili Free reali.** Quattro eventi di prova: un privato programmato, un privato annullato e due pubblici conclusi. Nessuna prenotazione o pagamento. Pubblicazione, richiesta, ammissione, avvio, conclusione e storico sono stati provati fra account distinti.
- **Inviti:** copia effettiva del link, ingresso anonimo e ritorno da Google verificati. Sede privata mascherata per ospite, pending e rimosso; visibile solo dopo ammissione. Una nuova richiesta dopo rimozione resta pending. Il token resta in memoria, non nell’archivio locale dei match; generare un nuovo invito dopo una nuova sessione sostituisce quello precedente, con avviso.
- **Sicurezza reale:** 11/11 controlli HTTP con Sportivo e 11/11 con Host ordinario. Admin SQL/Edge negati, profili altrui invisibili, sede/roster/contatto privati protetti e azioni altrui respinte. Due sonde del titolare confermano `mfa_required`. Nessun enrollment MFA simulato: il titolare lo ha rinviato.
- **Backend:** progetto `nrixslotansgrtrosaof`, 17 migrazioni. Nuova migrazione `20261113121927_trovat1o_event_status_notification_copy`: testo corretto per avvio e conclusione; tipo, permessi e coda invariati. Admin Edge v4 e contatto Host v1 attivi. Nessun job di purge/retention/push attivo.
- **Controlli:** 28 suite Node; 16 moduli SQL e 16 regressioni locali, compresi avvisi di stato. Le fixture non provano Auth gestita, concorrenza HTTP, Cron o ripristino. Quattro larghezze già controllate: 320, 390, 768 e 1440 px.
- **Master R3:** 15/25 criteri verificati nel collaudo = 60% dei criteri, non del tempo o del codice. Scenari A, B, D e H chiusi nell’ambito documentato: 3/11. Pin riservati verificati con coordinate presenti: 33/33 controlli reali nei cinque stati creatore, pending, ammesso, rimosso e anonimo. Persistenza su altro dispositivo, concorrenza, automatismi e recupero restano aperti.
- **Assistenza nuova:** handler, UI, quote e registri anti-riuso/idempotenza verificati localmente. Migrazione pendente: due conferme del connettore scadute, nessun DDL applicato. Il modulo resta spento e la UI presenta il contatto email. Leggere [SUPPORT-SETUP.md](SUPPORT-SETUP.md). CAPTCHA caricato solo su richiesta, indipendente dall’accesso Google.
- **Residui:** TOTP e uso completo Admin, email/password con SMTP/conferma/reset/anti-abuso, assistenza, push/promemoria, retention/account lifecycle, cancellazione effettiva, backup/ripristino, informative e rilascio sul principale. Acquisti Premium €4,99/anno spenti. Nessun servizio a pagamento acquistato.
- **Advisors:** 18 tabelle private con RLS senza policy (diniego intenzionale), due RPC anonime e 43 autenticate SECURITY DEFINER da mantenere con gate/grant stretti. Protezione password compromesse segnalata: percorso email e configurazione anti-abuso remota restano un gate; il flag UI spento non prova la disattivazione del provider.
- Sorgenti, CI e integrità degli archivi hanno ricevute separate nel checkpoint privato. Un vecchio verde non verifica nuove modifiche. Non eseguire i test che richiedono un DB remoto vuoto: contiene account reali.

**Prove PostgreSQL native aggiuntive:** [run verificato](https://github.com/Diegosh501/TROVAt10/actions/runs/43481338497), PostgreSQL 17.11 isolato: 17 migrazioni registrate riprodotte, 16 regressioni, nove scenari realmente concorrenti e dump cifrato ripristinato in un secondo database. Confrontati dati e sicurezza di 42 tabelle, 42 policy, 96 funzioni, 177 vincoli, 11 trigger, 84 indici e quattro sequenze. Quattro modifiche negative ai permessi/RLS vengono rilevate; sei guardie locali e quattro sonde native proteggono l’isolamento. Le otto prove di cifratura passano. Auth resta un fixture e non è stato eseguito un recupero completo del progetto Supabase reale. [Procedura backup](BACKUP-RESTORE-SETUP.md).


**Nuove verifiche effettive:** sei race HTTP e 18 operazioni nel collaudo. Caricamento lento, offline, recupero e uscita verificati nel browser; otto nuove regressioni proteggono i confini della sessione. Contesa remota dell’ultimo posto, MFA personale, servizi e gate di produzione ancora aperti.


---

## Documento e checkpoint precedenti

# Preparare il rilascio V1.0

Stato dell’11 novembre 2026. Il sito pubblico è ancora l’anteprima 2.0.2. La cartella pubblica locale e i pacchetti sono candidati successivi e non attestano un nuovo deploy.

## Gate ancora aperti

1. Google OAuth sul progetto Supabase corretto e login/logout reali. Il client non richiede SMTP/SMS/Turnstile per il percorso Google; configurare solo i percorsi opzionali realmente offerti.
2. Allowlist dell’Admin verificato, enrollment TOTP e controllo della sessione e della scadenza di 15 minuti. L’Edge Admin v2 è distribuita ma non sostituisce questo test.
3. Distribuzione delle funzioni necessarie, segreti nelle impostazioni dei provider, limiti e origini corrette. Non impostare valori segreti nel frontend o nel repository.
4. Prove con account Host/Sportivo separati: persistenza, invito privato, capienza concorrente, richieste, ammissioni, espulsione/riammissione, modifiche e conclusione.
5. Cron e vere esecuzioni di storico, promemoria e push. Esportazione e cancellazione su richiesta devono funzionare; la durata automatica degli account ha una migrazione separata da approvare ed è disattivata.
6. Prima degli acquisti: ambiente Stripe test autorizzato, prezzo annuale previsto e stato pagato verificato, webhook, portale, rinnovo/annullamento, dati fiscali/contrattuali pertinenti. Non usare un acquisto live per provare l’integrazione.
7. Verifica finale delle informative aggiornate, accordi con i responsabili, trasferimenti e conservazione delle pratiche. I testi non sono una certificazione legale. Backup dati e ripristino completo ancora da provare.
8. Solo dopo i controlli necessari abilitare i flag appropriati, distribuire una versione coordinata e provare online i flussi A-G. Le funzioni opzionali non disponibili restano spente e non devono mostrare falsi successi.

## Pacchetto e controlli

Da una copia completa dei sorgenti:

```sh
cp config.example.js config.js
bash scripts/package-release.sh
```

La configurazione reale va predisposta prima del rilascio e non va sostituita alla cieca se esiste già. Il workflow CI crea solo una configurazione di preview e non pubblica. I test Node, il driver PostgreSQL locale obbligatorio e i controlli Deno sono descritti nel README e nel workflow.

Gli archivi escludono `.env`, `.dev.vars`, `.npmrc`, `node_modules`, `.wrangler` e Git. Prima di usarli confrontare sorgenti, copie ed entrypoint, non soltanto l’integrità dello ZIP. Il pacchetto locale include la documentazione, le prove e la guida PDF; quello statico contiene i file del sito.

## Pubblicazione e verifica

Il progetto Cloudflare già autorizzato usa asset statici da `TROVAT1O-Cloudflare-Deploy/public/` e il dominio gratuito esistente. Dopo aver superato i gate:

```sh
cd TROVAT1O-Cloudflare-Deploy
npm ci --ignore-scripts --no-audit --no-fund
npx wrangler deploy
```

Non confondere `deploy --dry-run` con pubblicazione e un deploy riuscito con accesso Google o sincronizzazione funzionanti. Registrare versione Cloudflare, commit, configurazione senza segreti, data ed esito. Controllare asset, console, sessioni, autorizzazioni e prove reali sullo stesso URL pubblico.

## Recupero e costi

Conservare la versione hosting precedente e un backup dati verificato. Disattivare i job di eliminazione prima di interventi di rollback; una cancellazione fisica non si annulla cambiando configurazione o ritirando una migrazione. Le tredici migrazioni registrate non sono un backup dei dati e non sono state riprodotte da zero.

Non acquistare servizi o aumentare piani automaticamente. Verificare le quote e la continuità dei servizi Free correnti; in caso di crescita il titolare decide un eventuale incremento. Il dominio comprato non è necessario per il primo collaudo pubblico; collegarlo successivamente richiede aggiornare origine, redirect, link, metadata, CORS e informative.
