# Aggiornamento strumenti operativi — 14 novembre 2026

Preflight Auth e documentazione: sorgenti del controllo dei provider e istruzioni aggiornate, frontend e backend distribuiti invariati. La lettura reale segnala email server abilitata con UI spenta; configurazione ancora da correggere in console dopo il consenso specifico richiesto dalla revisione automatica al salvataggio. I risultati e il commit effettivo sono nel checkpoint. La PR #1 è integrata e push-dispatch v1 è pubblicato spento. Nessuna nuova pubblicazione è implicata dall’aggiornamento degli strumenti.

## Storico rilasci e candidati precedenti

# Candidato corrente — 14 novembre 2026, rc.10 non pubblicato

Correzioni di avvio e configurazione del dispatcher push, verificate con libreria reale: otto prove crittografiche/runtime e 19 scenari del gestore. Dettagli in [PUSH-SETUP.md](PUSH-SETUP.md). Dopo il consenso specifico del titolare, push-dispatch v1 è stata pubblicata inizialmente disattivata. Boot gestito e corrispondenza delle due sorgenti applicative verificati; tre richieste ricevono 503/push_unavailable. Nessun segreto persistente, job o invio reale attivato. Le ricevute del checkpoint identificano commit e CI effettivamente testati.

Il collaudo resta cloud-test.11 dal candidato rc.8/cache v22, principale rc.1 preview. Il candidato rc.10/cache v24 include il precedente percorso di cancellazione, ancora disabilitato. La guida v4 descrive il servizio già online. Nessun nuovo dominio o acquisto.

# Candidato corrente — 14 novembre 2026, rc.9 non pubblicato

Il collaudo online resta **cloud-test.11**, derivato da rc.8/cache v22; il principale resta rc.1. Il candidato rc.9/cache v23 integra il percorso di cancellazione revisionata con tre gate disabilitati. Nessuna nuova migrazione remota, funzione Edge pubblicata, attivazione di job, spesa o cancellazione reale. Test e limiti: [ERASURE-REQUESTS.md](ERASURE-REQUESTS.md), [V1-STATUS.md](V1-STATUS.md). Le ricevute nel checkpoint privato identificano il commit e l’esito CI effettivamente provati; non attribuire il vecchio verde a modifiche successive.

La guida v4 descrive il servizio di collaudo operativo. La preparazione rc.9 è un aggiornamento dei sorgenti, non un rilascio online della nuova cancellazione. Il passaggio all’indirizzo gratuito indicizzabile avverrà insieme al rilascio pubblico dopo i gate; il collaudo resta noindex.

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

---

## Documento e checkpoint precedenti

# Checkpoint dell’11 novembre 2026

Nessun nuovo rilascio frontend: il pubblico resta 2.0.2, versione Cloudflare 79bbea69-3511-400e-8603-5de3c9acacdb. La nuova UI è solo nel candidato e negli archivi aggiornati.

Aggiornamento server eseguito: admin-console versione 2, verify_jwt=true, bundle SHA-256 9fafb5f00f143e58fb9a798469a6179ad2cfc1e2d11adf1c89ab6659c49bf4ee. Il sorgente letto dal servizio coincide con quello candidato. Richieste senza credenziali o con token falso:401; preflight origine autorizzata:204. Il sorgente precedente è conservato nell’audit privato per un ritorno controllato, non è un rollback eseguito.

Sincronizzazione sorgenti iniziale: commit 7c78c6277e7fd2d390c1267e21b220598aefc9a2 con CI verde. Le modifiche successive hanno un commit e una ricevuta separati. Nessun acquisto, nuovo Admin o cancellazione account attivati. Vedere V1-STATUS.md e ACCOUNT-LIFECYCLE.md.

## 13 novembre 2026 — collaudo cloud-test.11

Caricato con `wrangler versions upload --preview-alias v1-check`; versione Cloudflare `efaa577e-d2aa-47ba-bbae-92c2c06ef11f`. Candidato rc.8, cache v22. 19 asset HTTPS confrontati integralmente, cinque percorsi riservati negati, intestazioni effettive controllate e principale rc.1 confermato. `_headers` è interpretato dal servizio e resta non scaricabile. Browser: attesa con rete lenta, errore offline, recupero e uscita concorrente con Profilo verificati; rete ripristinata e sessione finale disconnessa. Non è un rilascio della V1 completa in produzione.

## Cronologia dei rilasci frontend

# Registro rilasci TROVAT1O

## 10 novembre 2026 · 2.0.0 pubblicata prima dell’audit

- Ambiente: Worker Cloudflare `trovato`, asset statici in `TROVAT1O-Cloudflare-Deploy/public/`.
- URL: https://trovato.diegolucentedesign.workers.dev/
- Versione Cloudflare: `9dbc71ac-657a-4102-bfc3-7d2c8b547d12`.
- Procedura: `npx wrangler deploy` dalla cartella Cloudflare, nessuna modifica funzionale prima del rilascio.
- Esito: exit 0, HTTP 200; hash del documento scaricato uguale al documento caricato.
- SHA-256 index: `530bbd5ac1c53d25cc16aa28dcf4a99b74bd6b4d4ce99060723f1a98f9a33d4b`.
- Ora: circa 01:28 UTC / 02:28 Europe/Rome; verifica HTTP alle 01:29 UTC.
- Il rilascio è una demo locale ospitata su HTTPS: `onlineReady: false`, nessun account multiutente attivato.
- Evidenze e copia degli asset iniziali: `output/audit/2026-11-10/releases/` nel workspace originale.

## 2.0.1 · aggiornamento correttivo raggruppato

- Pubblicata il 10 novembre 2026; verifica HTTPS: 2026-11-10T01:54:01.988Z.
- Versione Cloudflare: 8f4bfd35-00dd-4a83-9192-c221273fc607, procedura npx wrangler deploy, exit 0.
- Home 200; tutti i 16 asset pubblici coincidono con il pacchetto caricato. CSP, HSTS e blocco frame verificati sulla risposta reale.
- SHA-256 index: 776629b5ee2cc5577c202e758ee338291f8d7be23c9a31833740814b2bb1b446.
- Browser: metadata 2.0.1, una sola CTA Auth principale, schermata mobile e nessun console error/warning nella sequenza provata.
- Tutte le correzioni sono elencate in CHANGELOG.md e AUDIT-PREDEPLOY.md. Il cloud resta disattivato nella configurazione pubblica.

## Procedura di rilascio

1. Eseguire i controlli in `tests/*.cjs`; mantenere cloud e push disabilitati finché non verificati con provider reali.
2. Eseguire `bash scripts/package-release.sh` dalla root. Lo script confronta i file distribuiti con i sorgenti prima di creare gli archivi.
3. Dalla cartella `TROVAT1O-Cloudflare-Deploy`: `npm ci`, poi `npx wrangler deploy`. L’autenticazione Cloudflare resta nella configurazione locale di Wrangler, esclusa dai pacchetti.
4. Registrare Version ID, data, hash e risultato. Verificare home, config, service worker e intestazioni via HTTPS; poi eseguire smoke nel browser.

## Rollback frontend

Il comando disponibile e verificato con Wrangler 4.158.0 è:

```sh
cd TROVAT1O-Cloudflare-Deploy
npx wrangler rollback 9dbc71ac-657a-4102-bfc3-7d2c8b547d12 --message "Ripristino preview 2.0.0"
```

Il rollback modifica il rilascio online: usarlo soltanto in caso di regressione. Non è stato eseguito durante l’audit per non sostituire una versione funzionante. Se si ripubblicano asset manualmente, incrementare la versione cache di `sw.js` e verificare anche un browser che aveva già installato la PWA.

## Database e backup

Schema base e notifiche sono separati in `supabase/schema.sql` e `supabase/notifications.sql`. Sono blueprint per un progetto vuoto: non rieseguire l’intero baseline su un database popolato. Le modifiche live passano da migration mirate registrate da Supabase. Esportare e riconciliare la cronologia prima di usare `db push` da un nuovo checkout.

Nessun backup dati o ripristino completo è stato verificato. Prima di accogliere utenti reali, verificare i backup effettivamente disponibili nel piano Supabase, conservare un export protetto e provare il ripristino in un ambiente separato. La transazione di test con ROLLBACK verifica l’assenza di righe residue, non un backup/restore dell’intero servizio. Correggere le policy con migration successive; non annullare le protezioni per recuperare compatibilità.


## 2.0.2 · gruppo prestazioni e accessibilità

- Pubblicata sullo stesso Worker; versione Cloudflare 79bbea69-3511-400e-8603-5de3c9acacdb.
- Verifica HTTPS: 2026-11-10T11:34:03.833Z,16/16 asset coincidenti e intestazioni corrette.
- SHA-256 index: 75f728b8ae0b8a91d5d5fdebb5d3fc2a1e6020285520592d21cc7cf787cd382b.
- Lighthouse mobile: Performance 96, Accessibility 100, LCP 2141,992 ms, CLS 0, TBT 150 ms.
- Sessione interattiva CPU 4×: INP 120 ms; ricaricamento, ricerca e dettagli offline verificati con risorse Servite dal ServiceWorker.
- Include PNG ottimizzato, contrasto/navigazione tastiera, stabilità del caricamento e workflow CI. Cloud e push restano disabilitati nel client.
- Il sorgente ufficiale scelto dal titolare è Diegosh501/TROVAt10; verificare commit e job sulla pagina Actions. I risultati del caricamento sono conservati nei report locali output/audit/2026-11-10/.
