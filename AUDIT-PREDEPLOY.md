# Audit corrente — candidato rc.7 / cloud-test.10, 13 novembre 2026

Questa sezione prevale sulle verifiche storiche. 27/27 suite Node e 16/16 regressioni SQL locali. Handler supporto reale con trasporti controllati: 17 scenari; UI: 14; bootstrap: 7. Due mutazioni locali negative rilevate. Nuovo supporto non attivo: due conferme migration scadute e schema remoto invariato, 17 migrazioni. Nessun aggiramento della conferma tecnica.

Pin privato sintetico realmente salvato dall’Host; 33/33 controlli sul database con sessioni ordinarie nei cinque stati creatore, pending, ammesso, rimosso e anonimo. Coordinate e sede nascoste quando non consentite; base events, roster e profili altrui non utilizzabili per aggirare il feed. Prove prive di JWT/coordinate nei risultati.

HTTPS cloud-test.10: 19/19 file corrispondenti, cinque percorsi riservati negati, intestazioni verificate. La prima verifica durante la propagazione ha trovato un vecchio index-v2; il controllo ripetuto dopo l’allineamento passa integralmente. Principale non aggiornato. TOTP Admin rinviato e servizi indicati in V1-STATUS restano gate reali: non è una certificazione di invulnerabilità o di V1 completata.

---

# Stato aggiornato e cronologia di audit

Per lo stato corrente dell’11 novembre leggere V1-STATUS.md. Le sezioni seguenti sono una cronologia delle prove del 10 novembre e non dichiarano che tutti i vecchi blocchi siano ancora presenti. Ora Admin Edge v2 è distribuita; 22 suite Node, 13 moduli SQL e 12 regressioni locali sono passati. Provider, account reali, job, privacy operativa e rilascio V1.0 restano aperti. La migrazione account candidata non è applicata per conferma scaduta. Nessun nuovo frontend pubblico.

# Audit TROVAT1O V2 · 10 novembre 2026

## Prodotto, ambienti e limiti del rilascio

Web app statica HTML/CSS/JavaScript, con manifest PWA e service worker. Non esiste un progetto Android né un APK/AAB: i controlli di compilazione e distribuzione nativi Android non sono applicabili. Il frontend non ha una fase di build/compilazione: viene distribuita la cartella `public/` da Wrangler. Supabase è il backend opzionale; il client pubblicato resta con `onlineReady: false` e `pushReady: false`.

Ambienti ispezionati: workspace locale (escludendo `sources/` in sola lettura), anteprima HTTP 127.0.0.1:4173, Worker HTTPS Cloudflare e progetto Supabase `nrixslotansgrtrosaof`. Il repository pubblico `Diegosh501/trovato` è stato letto: al controllo contiene README, manifest npm, configurazione Wrangler e archivio statico; il checkout locale non ha `.git`. Non esiste quindi un commit locale che identifichi questi sorgenti. Il rilascio è identificato da hash e Version ID in RELEASES.md.

## Rilascio iniziale

La versione pronta 2.0.0 è stata pubblicata prima delle correzioni senza refactoring: Cloudflare `9dbc71ac-657a-4102-bfc3-7d2c8b547d12`, exit 0. Home HTTPS 200 e SHA-256 identico al file caricato. Una copia degli asset iniziali è conservata localmente per ripristino. Le correzioni successive sono raccolte in 2.0.1.

## Criticità corrette

| Problema osservato | Correzione e prova |
|---|---|
| ZIP completo con index e cache più vecchi dei sorgenti | Copia di tutti i file web, cartella deploy completa e confronti prima della compressione. L’integrità dello ZIP da sola non prova l’allineamento. |
| Chiusura della mappa Host su un elemento form assente | Guardie DOM; test runtime e selezione/salvataggio reale di un pin nel browser. |
| Due CTA Auth con lo stesso ID | Un’unica azione nel footer; test delle funzioni che generano la finestra. |
| Escape senza overlay, focus fuori dalle finestre | Chiusura del solo overlay superiore, focus iniziale, ciclo Tab/Shift+Tab e ripristino del controllo iniziale. Verificato nel browser. |
| Recupero password chiuso dalla callback di sessione | Stato recovery protetto; simulazione delle callback reali e risposte provider. |
| Reset/reinvio email senza CAPTCHA e successo mostrato anche su errore | Token nuovo passato a Supabase; controllo della risposta e messaggio di errore effettivo. Consegna email reale ancora da provare. |
| Prefisso telefonico manuale | Italia +39 selezionata, elenco paesi e normalizzazione +/00 senza doppio prefisso. |
| Evento locale nel passato o capienza sotto gli ammessi | Validazione prima di cambiare i dati e test negativi che verificano l’assenza di mutazioni. |
| Coordinate mancanti convertite in 0,0 | Validazione esplicita di assenza, valori finiti e limiti geografici. |
| Rientro impossibile dopo uscita locale e riammissione automatica via RPC | Riga esistente riportata a pending; solo il proprietario approva e incrementa i posti una sola volta. |
| Organizzatore conteggiato anche come nuovo partecipante | Azione Gestisci partita; nessuna nuova riga o incremento se il proprietario aziona il join. |
| Partecipanti che potevano leggere richieste rifiutate/pendenti | Policy server limita la lettura degli altri membri alle sole righe approved. Self e proprietario conservano i rispettivi accessi. |
| Invito implementato senza azione visibile | Una CTA nel riepilogo per eventi pubblici e proprietario privato; immagine privata senza token nei metadata. |
| PNG privato dipendente da un token non necessario | Generazione immagine indipendente dalla creazione del link; privacy metadata invariata. |
| Librerie runtime Supabase a versione variabile | SDK client e 4 funzioni fissati a 2.119.0; SRI client/Leaflet; lock Wrangler completo. |
| Protezioni frame/HTTPS assenti | X-Frame-Options DENY, HSTS e CSP per origini utilizzate. CSP mantiene unsafe-inline per gli handler esistenti: non equivale a eliminare ogni rischio XSS. |
| Click push con URL protocol-relative | URL risolto e verificato contro l’origine; test anche su //evil e backslash. |

È stato applicato anche il file notifiche, che mancava nel progetto live: quattro tabelle con RLS, trigger e coda privata. Il trigger avvisa l’Host anche sulle nuove richieste dopo rimozione/rifiuto; il claim ricontrolla consenso push e preferenze di categoria. Verificati via query i grant (solo read_at aggiornabile dal destinatario e consegna service-only). Il test sintetico è passato anche con questi trigger attivi; dopo ROLLBACK utenti/eventi/membership/notifiche/coda sono tutti a zero. Non sono stati inviati messaggi push.

## Controlli e copertura effettiva

| Area | Esito ed evidenza |
|---|---|
| Controlli locali | Le suite in `tests/*.cjs` passano: controlli strutturali, funzioni applicative eseguite in DOM simulato e handler service worker eseguiti in VM. Non sono tutte E2E. |
| Installazione pulita | npm ci con lock Wrangler in cartella temporanea nuova: 36 pacchetti, exit 0. Script d’installazione disabilitati. |
| Dipendenze | npm audit sul lock completo, registro ufficiale: 0 vulnerabilità note rilevate, 91 dipendenze incluse 60 opzionali. Questo non prova assenza di vulnerabilità sconosciute. |
| Tipi Edge | Deno 2.9.6 / TypeScript 6.0.3: i quattro sorgenti locali superano deno check. Il controllo --all fallisce con 29 diagnostiche nelle dichiarazioni browser WebAuthn di auth-js 2.119.0 sotto librerie server Deno. Nessun workaround introdotto. |
| Lint | Nessuna configurazione lint nel progetto; non è stato inventato un gate superato. |
| Segreti | Scansione mirata di sorgenti/config/documenti senza stampare valori: nessuna corrispondenza ai formati privati cercati. Config pubblico con chiavi vuote; credenziali Wrangler escluse dal pacchetto. |
| Supabase | Progetto ACTIVE_HEALTHY, tutte le tabelle applicative con RLS. Lettura/update diretti events negati ai client. Health advisor senza rilievi. Avvisi SECURITY DEFINER intenzionali per RPC controllate e indici inutilizzati su DB vuoto registrati. |
| Test SQL autorizzato | Tre utenti sintetici, evento e membership in transazione: nuovo join aperto, rimozione/rifiuto, pending, privacy peer, self/owner e approvazione. Nessuna asserzione fallita; ROLLBACK. Verifica successiva: 0 users, 0 events, 0 members. Nessuna email/SMS inviata. |
| Prove browser | Host demo, scelta storage sessione, creazione privata dal FAB, ricarica/persistenza, I miei match/limite Free, Tab/Shift+Tab/Escape/focus, pin Host, ricerca città/vuota/reset, filtro 5v5, join 7→8, uscita 8→7, nuova richiesta pending senza aumento, export PNG scaricato. |
| Responsive | Browser a 320×568, 390×844, 844×390 e 1280×800; nessun overflow orizzontale nelle viste misurate. Screenshot locali nel rapporto output/audit. Non sono prove su hardware iOS/Android fisico. |
| Export | PNG scaricato 1080×1350; Website https://trovat10.app, metadata privati senza EventLink né invito. Test su logo e conteggi. |
| Errori browser | Nessun console error/warning raccolto durante la sequenza locale verificata. |
| PWA | Manifest valido, icone PNG, file precache presenti; test runtime install/activate/cache/fallback offline e click push. Ricaricamento reale con rete Offline, ricerca e dettagli verificati in Chrome; installazione homescreen su dispositivo fisico non eseguita. |
| Core Web Vitals | Su2.0.2: Lighthouse mobile LCP 2141,992 ms, CLS 0. Sessione interattiva distinta con CPU 4×: INP 120 ms. Sono misure lab/sessione, senza dati field o percentile75. |
| HTTPS/intestazioni | HTTP 200 e intestazioni iniziali verificate. Rilascio 2.0.1: 16/16 asset coincidenti, CSP/HSTS/frame attivi e versione applicazione 2.0.1 verificata nel browser. |

## Verifiche mancanti prima di utenti reali

1. SMTP/redirect Auth/Turnstile e consegna conferme/recupero; login e sessioni reali separati, inclusi logout e scadenza.
2. Edge Functions pubblicate e configurate con segreti, Origin esatto, risposte d’errore e rate limit provati sulla rete. I sorgenti compilati non equivalgono a funzioni online.
3. Twilio Verify per SMS, solo se attivato: non esiste una garanzia di costo zero. OAuth social e Stripe non configurati.
4. Dispatcher push e processo promemoria periodico, rispetto opt-out e retention/cleanup. La coda SQL non consegna messaggi da sola.
5. Backup e ripristino completo su ambiente separato; riconciliazione cronologia migration con source control.
6. Dati CWV degli utenti reali, installazione PWA su dispositivo, accessibilità con screen reader e dispositivi fisici. Le etichette dei form sono state rese più leggibili; non è una certificazione WCAG.
7. Aggiornare le informative per i provider, conservazione e funzionalità effettivamente attivati. Le pagine attuali descrivono la preview e non certificano conformità legale.

Altri rilievi operativi da risolvere con il backend: salvataggio ticket e relativo audit non atomico; gestione amministrativa delle segnalazioni giocatore incompleta; nessun alert applicativo configurato. Il frontend si presenta come demo, non promette consegna del supporto o push online.

## Fonti tecniche consultate

- Supabase: changelog ufficiale e [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security), [resetPasswordForEmail](https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail).
- Registro npm ufficiale per SDK 2.119.0, Wrangler 4.158.0 e Deno 2.9.6; impronte degli script CDN calcolate sui file scaricati.
- Help locale della versione Wrangler installata per deploy/rollback. Procedura, rollback e limiti backup in RELEASES.md.


## Verifica finale del rilascio 2.0.1

Versione Cloudflare 8f4bfd35-00dd-4a83-9192-c221273fc607. Tutti i 16 asset pubblici coincidono byte per byte con il pacchetto locale. La registrazione demo genera una sola CTA principale. Home mobile 390px senza overflow; console senza errori/warning nella sequenza provata. Screenshot: output/audit/2026-11-10/live-mobile-2.0.1.png.

Rilievi minori ancora aperti: hamburger mobile largo 40px e pulsanti della scelta storage alti 42px, sotto l’obiettivo progettuale 44 px; il logo cliccabile non è un controllo da tastiera. Non sono blocchi al caricamento della demo e restano nel prossimo gruppo di accessibilità. I test regex che rilevano regole CSS 44 px non provano che ogni controllo renderizzato raggiunga quella misura.

Dopo l’installazione notifiche sono stati aggiunti i tre indici delle chiavi esterne segnalati dall’advisor e una policy esplicita di diniego client sulla coda. Verifica finale: nessuna chiave esterna senza indice, nessuna tabella applicativa RLS senza policy; restano gli avvisi SECURITY DEFINER delle RPC intenzionali e gli indici inutilizzati del database vuoto. Indicazioni advisor: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable e https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable.

Il repository GitHub letto durante l’audit contiene ancora il pacchetto precedente e non è stato aggiornato da questo rilascio diretto Wrangler. La sincronizzazione completa dei sorgenti/CI resta un’attività aperta; gli ZIP locali sono la consegna aggiornata di questa iterazione.


## Continuazione audit · prestazioni e accessibilità 2.0.2

È stato possibile usare Lighthouse nativo di Chrome in una finestra Incognito isolata. Rapporto iniziale 2.0.1: Lighthouse 13.5.0, Moto G Power emulato, navigazione iniziale, Slow 4G simulato; Performance 74, Accessibility 96, Best Practices 100, SEO 66 (indicizzazione disabilitata intenzionalmente). LCP 7.701,832 ms, CLS 0, TBT 109 ms. File: output/audit/2026-11-10/lighthouse-before-mobile.json.

L’audit ha segnalato il PNG del marchio da 1.177.089 byte, 2172×724, sproporzionato alla visualizzazione. È stata riutilizzata la variante PNG da 480×160 già presente: 74.898 byte, circa 94% in meno. Il file originale è conservato. Aggiunte dimensioni alle immagini e sistemati contrasti della vista mappa e barra inferiore. Il marchio è un button accessibile; hamburger e scelte storage hanno target44 px.

Una prima prova locale ha esposto un movimento del footer prima che JavaScript popolasse la lista. È stato riservato spazio solo alla lista inizialmente vuota. Nuova prova locale: Performance 94, Accessibility 100, Best Practices 100, CLS 0, LCP 2703 ms, TBT 0. Il semplice server Python non comprime i documenti: questo risultato non viene presentato come misura HTTPS di produzione. Rapporto: output/audit/2026-11-10/lighthouse-local-2.0.2.json. Le misure sul rilascio pubblico e sulle interazioni sono registrate nella sezione Esito verificato 2.0.2. Il TBT non sostituisce INP.

Il workflow .github/workflows/ci.yml è stato verificato su una copia pulita (nove suite, installazione da lock, pacchetti, dry-run, confronti archivi). Le azioni ufficiali sono fissate a commit completi. Non contiene segreti né pubblica automaticamente. GitHub API create_blob ha rifiutato la prima scrittura con 403 Resource not accessible by integration: nessun blob/commit/ref creato. La sincronizzazione remota resta da completare con un accesso effettivamente abilitato alla scrittura.


## Esito verificato 2.0.2

Il deploy 79bbea69-3511-400e-8603-5de3c9acacdb è attivo. Confronto HTTPS16/16 asset superato. Rapporti JSON nativi: lighthouse-before-mobile.json e lighthouse-after-mobile-2.0.2.json in output/audit/2026-11-10. Il confronto su HTTPS passa da Performance 74/LCP 7701,832 ms ad Performance 96/LCP 2141,992 ms; CLS 0 in entrambe le prove. Accessibility 96→100; console audit senza errori e nessun runtimeError Lighthouse.

INP è stato misurato separatamente dal TBT, nel pannello Performance di Chrome:120ms per le interazioni provate con CPU 4× rallentata, rete senza throttling, sessione locale del browser. Non è una statistica field. Evidenza testuale e screenshot inp-session-2.0.2.

PWA provata realmente nella stessa finestra Incognito isolata: Network Offline, ricaricamento completo; documento, configurazione e logo risultano Served from ServiceWorker. Ricerca Monza e apertura del torneo hanno funzionato senza connessione. Un tentativo di aggiornamento del worker fallito per assenza rete è atteso durante questo test. Rete e CPU riportate a No throttling, DevTools chiuso. Evidenze offline-session-2.0.2.txt/png. La finestra di test non contiene account reali.

I rilievi grafici citati nella sezione2.0.1 sono stati corretti nella2.0.2: hamburger, storage e marchio hanno minimi44 px; marchio azionabile da tastiera; contrasto della navigazione corretto. Il punteggio automatico100 non certifica tutta l’accessibilità manuale.

La causa del403GitHub è stata identificata: l’installazione è selezionata per TROVAt10, mentre il precedente tentativo scriveva nel diverso trovato. Il titolare ha scelto esplicitamente Diegosh501/TROVAt10 come repository sorgente. La scrittura dei blob è riuscita su quel repository, con hash verificati; nessuna modifica è stata fatta al repository precedente. Il workflow è pronto; gli esiti delle esecuzioni ospitate vanno verificati nella pagina Actions.

Restano da attivare per 1.0 ONLINE: SMTP/Turnstile/OTP dove necessario,4 Edge Functions configurate, prove con sessioni Auth reali, dispatcher push e processo promemoria, backup/ripristino e aggiornamento delle informative per i servizi attivati. Nessun servizio a pagamento è stato attivato in questa iterazione.


## Preparazione V1.0 - sicurezza Admin e confine dei dati cloud

L'obiettivo aggiornato include Google OAuth, tutti Free, account non soggetto a scadenza e storico delle sessioni Free per sette giorni dalla conclusione/annullamento. Queste funzioni non sono ancora operative. Le impostazioni pubbliche Auth verificano Google=false, email=true, phone=false; il vecchio trigger richiede metadati email e deve essere adattato prima dell'attivazione OAuth. La matrice dei venti criteri è V1-STATUS.md.

Applicata migrazione 20261110164243_trovat1o_platform_admin_security: allowlist privata, controlli account/sessione/MFA recente, 60 operazioni Admin/minuto e audit atomico dei ticket. Prima dell'applicazione tutti i 21 gruppi di regressione sono passati con DDL e fixture annullati; dopo l'applicazione la stessa suite è passata sul codice installato. Conteggi finali Auth utenti/eventi/admin/quota/audit: zero. Nessuna email o SMS inviati. La suite prova l'autorizzazione database con claim di test, non la firma JWT o un vero login; i trasporti sono separatamente simulati nei 24 scenari del gestore Edge.

Controllo locale Deno 2.9.6 sul sorgente admin-console: superato. Dieci suite Node passate, inclusi nuovi casi reali delle funzioni client: nessun storage demo letto/scritto in cloud, nessuna scelta locale online, dati privati e modali puliti al cambio account, feed/profili tardivi scartati. Service worker v11 in preparazione: solo shell pubblica, nessuna cache API/richieste autorizzate/parametri invito e rispetto di no-store/private.

admin-console Edge v1 pubblicata con verify_jwt=true; origine HTTPS esatta predefinita. Non usa service-role per leggere/modificare dati Admin. Le prove HTTP del perimetro anonimo sono in output/audit/2026-11-10/admin-edge-http.json. Nessun account Admin assegnato o login Google/MFA reale provato. Supporto/OTP restano non pubblicati.

Gli advisor dopo la migrazione mostrano due RPC anonime e 24 autenticate SECURITY DEFINER intenzionali, più tre INFO per tabelle private con RLS senza policy: diniego predefinito e assenza di privilegi client voluti. Il nuovo test SQL conferma l'impossibilità di scrivere l'elenco privato o eseguire il provisioning come utente normale. La CSP inline e il flusso di gestione ruoli/report più esteso restano da completare.

Cronologia effettiva esportata: nove file, i primi otto 88.812 byte verificati e l'ultimo 12.242 byte MD5 a0c8bac492bc42747e3452ae5f85d751, identico al record del database. Conservata in supabase/recorded-migrations/. È una storia SQL con dipendenze Supabase, non un backup né un replay validato.

Questo blocco frontend è ancora in preparazione: la preview pubblica resta 2.0.2 con i propri risultati di prestazione/CI. Non attribuire alla nuova interfaccia un collaudo browser o un deploy che non è stato eseguito.
