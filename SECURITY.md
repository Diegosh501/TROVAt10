# Stato autorevole — 13 novembre 2026

Questa sezione prevale sui checkpoint storici sottostanti.

- Pubblico aggiornato: **1.0.0-rc.1**, anteprima interattiva, https://trovato.diegolucentedesign.workers.dev/ . Versione Cloudflare `959a4c70-a070-4ee8-aa21-b306260b3165`, pubblicata l’11 novembre. Non è ancora V1.0 cloud.
- Nuova verifica HTTPS del 13 novembre: **17/17 asset identici**, intestazioni corrette, **5/5 percorsi riservati negati**. Ricevuta: `output/audit/2026-11-13/live-verification.json`.
- Supabase corretto `nrixslotansgrtrosaof`: **15 migrazioni**. Ciclo account applicato e **enabled=false, purge_enabled=false**. Nessun job installato, nessuna cancellazione attiva. Utenti/eventi reali ancora zero.
- Nuovo modulo `supabase/session-security.sql` applicato: sessione Auth esatta e viva, account valido, **10 policy RLS restrittive** con USING/WITH CHECK. Non annulla richieste già in corso o snapshot MVCC precedenti.
- Test locale aggiornato: **14 moduli SQL / 13 regressioni** con rollback, compresa session-security. Due controlli negativi rilevano un bypass intenzionale dei gate/RLS. Auth e JWT sono fixture, non login reali. Ultima esecuzione Node: **22/22**.
- Il tentativo Google del 13 novembre, dopo la conferma «Impostazione modificata», è ancora negato dalla regola salvata/gestita del browser. Nessun aggiramento. Provider Google non completato; frontend mantiene tutti i Ready=false.
- Master aggiornato: `output/handoff/OBIETTIVO-MASTER-R3.md`, **25 criteri V1 e 11 scenari reali** A–I,L,M. Nessuno scenario integralmente collaudato online: **0/11**. V2=PUBLIC BETA; V3=STABLE; V4=COMPLETE PLATFORM. Le vecchie barre 0/7 descrivono il precedente obiettivo.
- Cancellazione volontaria ancora mancante: audit `output/audit/2026-11-11/erasure-readiness-review.md`. Non equiparare scadenza Free a diritto di cancellazione. Conservazione Billing/dipendenze da risolvere prima del purge.
- Prossime priorità: Google–Supabase sul progetto corretto; Admin reale TOTP; due identità Host/Sportivo e persistenza; export/erasure/supporto e retention server; ripristino; poi collaudo V1. Push e apertura beta V2 successive. Premium/Stripe predisposti ma pagamenti spenti, tutti iniziano Free.
- Nessun nuovo costo, SMS, acquisto o account Admin creato. Il dominio acquistato resta futuro.

---

## Documento e checkpoint precedenti

# Sicurezza e limiti del checkpoint

Aggiornato l’11 novembre 2026. Non è una garanzia di assenza di vulnerabilità o un penetration test completo. Stato operativo e criteri finali: [V1-STATUS.md](V1-STATUS.md).

## Perimetro attuale

Il frontend pubblico è ancora la preview 2.0.2 con dati locali. Il candidato nuovo non è pubblicato e mantiene tutti i flag di attivazione su false. Il progetto Supabase corretto contiene tredici migrazioni applicate, zero account/profili/eventi osservati, nessun Admin reale assegnato e nessun job attivo. `admin-console` versione 2 è distribuita con verifica JWT. Gli altri gestori restano da configurare e distribuire.

Il browser ha negato accesso alla console Google e, in seguito, ulteriori operazioni sull’anteprima locale. Non sono state aggirate le autorizzazioni usando altri browser, comandi, richieste indirette o strumenti. La nuova migrazione account ha richiesto una conferma del connettore poi scaduta: non è applicata.

## Identità e autorizzazioni

Il percorso V1.0 usa Google OAuth PKCE con profilo completato esplicitamente. Un’identità verificata e un profilo completo permettono il gioco pubblico senza SMS. Non viene usato il dominio Gmail come sostituto dei controlli contro abusi. Email/password, SMTP e CAPTCHA appartengono a un percorso opzionale distinto e non bloccano il bootstrap Google.

Google non conferma un numero WhatsApp scritto in un form. La condivisione del recapito Host richiede consenso esplicito e corrispondenza HMAC al numero effettivamente verificato. Il flag del browser non basta. I client non scrivono direttamente il recapito; il gestore server verifica identità e sessione. OTP/SMS restano opzionali e spenti; il loro uso può avere costi, non autorizzati automaticamente.

Host e Sportivo non possono scegliere Admin o Premium alla registrazione. La console è protetta da allowlist UUID privata, account valido/non bloccato, sessione Auth ancora attiva, TOTP aal2 verificato recente (15 minuti), quote e audit. L’Edge usa il JWT del chiamante per RPC specifiche; non usa service-role per aggirare i controlli Admin. Un’email incorporata nel frontend non concede privilegi.

## Visibilità della console

Nel candidato gli utenti normali, compresi i Premium e i profili demo, non hanno l’ingresso amministrativo. L’app_metadata server è soltanto un indizio per evitare sonde inutili: il client richiede comunque una risposta valida dal dashboard protetto o un rifiuto MFA qualificato dopo il controllo dell’allowlist. Prima del secondo fattore non mostra metriche, navigazione o pratiche. Il risultato è legato a account, generazione di sessione e client attuali; logout, cambio identità, aggiornamento del token o revoca lo eliminano. Ventitré scenari delle funzioni reali coprono questi confini con trasporti controllati.

## Database e privacy

RLS, grant minimi e RPC con controlli di proprietà proteggono il database. La tabella eventi non è leggibile o scrivibile direttamente dai client; feed e inviti mascherano luogo e coordinate dei privati prima dell’ammissione. I token invito sono casuali di 256 bit e solo il loro hash viene conservato. L’ammissione, il ritiro, i cambi di stato e la capienza sono validati dal server, non dalla sola UI.

Le tabelle private non hanno grant ai client; RLS senza policy di lettura è un diniego intenzionale, non una richiesta di aprirle. I linter segnalano anche RPC SECURITY DEFINER accessibili ai ruoli applicativi: ciascuna deve mantenere search path chiuso, controllo caller/proprietà e grant stretti. Non rimuovere protezioni o concedere permessi generici soltanto per azzerare un avviso.

Quote limitano creazioni, nuove richieste e gestione ripetuta. Il ritiro volontario resta sempre possibile. Contatori, notifiche e job sono limitati per batch e non copiano contatti nei log operativi.

Nel cloud il client ignora i dati demo nel browser e non salva localmente match/account/report. Cambio account e logout puliscono anche console e modali nascosti e scartano risposte tardive. La gestione push del dispositivo viene serializzata per evitare associazioni con l’account precedente. La cache v12 del candidato conserva solo la shell pubblica, senza API, richieste autorizzate o token di invito. Le risposte riservate usano no-store.

L’esportazione è limitata ai dati del chiamante e richiede una sessione viva. Il nuovo export del profilo contiene anche i dati del ciclo account; la modifica remota è nell’operazione pendente. I limiti di dimensione/paginazione evitano un falso download parziale. Nessun token Auth, impronta telefono, invito o rubrica altrui entra nell’export.

## Scadenze e acquisti

La retention dei match usa il termine effettivo e preserva partecipanti Premium, report e vincoli. Il nuovo ciclo account parte dal primo match, ha conferma esplicita, avvisi e almeno 48 ore prima della pulizia fisica. Match necessari, partecipanti, pratiche, piano ignoto, collegamenti Billing, Storage e dipendenze nuove trattengono l’account. Il job non forza cancellazioni di report o dati condivisi per superare un errore. Nessuna pulizia è attiva automaticamente.

Billing isola test/live, verifica firma del webhook sul corpo originale, gestisce eventi duplicati e rilegge lo stato dal provider. Solo un acquisto live pagato e valido conferisce una scadenza Premium. Non fidarsi di `billing=success`, metadata, sessionStorage o di un piano scritto dal client. Nessun acquisto o addebito reale è stato eseguito.

Il dispatcher push verifica consenso e destinatario al claim e prima dell’invio; usa payload generico, endpoint consentiti, timeout, lease e retry limitati. Un segreto server protegge la chiamata del job. Non abilitarlo senza una consegna reale di prova e verifica dei dispositivi supportati.

## Segreti e dipendenze

`config.js` è pubblico ed escluso da Git. Deve contenere soltanto URL, chiave publishable/anon e opzioni pubbliche. Service-role, segreti OAuth/Stripe/VAPID/OTP, credenziali e token Management restano nelle impostazioni sicure del provider. Non stamparli nei log, nei comandi condivisi o in chat. La vecchia password proposta in chat non è una credenziale da distribuire.

SDK e tool sono fissati a versione o commit e hanno lockfile. L’integrità delle risorse browser Supabase e Leaflet è stata confrontata con le risposte effettive. I pacchetti escludono credenziali locali, dipendenze installate e cartelle interne. Servire la sola directory pubblica anche nei test sulla Wi-Fi.

## Evidenze e gate aperti

Ventidue suite Node verificano sorgenti, funzioni client e gestori con trasporti controllati. Tredici moduli SQL e dodici regressioni passano su PostgreSQL PGlite con rollback completo; sei casi di firma Stripe usano l’SDK reale. Il perimetro HTTP anonimo dell’Admin v2 rifiuta credenziali mancanti e token falso. Il browser locale ha provato i principali percorsi di creazione/richiesta/export e individuato un reale conflitto CSS corretto.

Restano necessari: OAuth/MFA reali, ruoli e sessioni distinti, concorrenza tra connessioni, abuso e gateway effettivi, job/consegna push, firma/webhook nel sandbox autorizzato, cancellazione e ripristino nel servizio gestito, verifica contratti/trasferimenti e collaudo post-deploy. Non attivare il frontend cloud e non dichiarare il 100% prima dei controlli essenziali. La disponibilità del codice non equivale a servizio operativo.

## Limite residuo delle sessioni ordinarie

Il controllo delle sessioni vive è esplicito per Admin, Billing, export, scrittura del contatto Host e nuove RPC del ciclo account. Le normali RPC e alcune letture self usano invece `is_email_confirmed`, che verifica utente vivo/confermato/non sospeso ma non `auth.sessions`. Un JWT già emesso e poi revocato può mantenere la propria autorità ordinaria fino a exp; non acquisisce proprietà altrui o Admin. Anche la lettura del recapito Host segue le policy di ammissione senza una verifica ulteriore della sessione.

Questo è un limite materiale da provare nella configurazione Auth reale, con durata JWT appropriata e valutazione di guardie di sessione aggiuntive sulle normali operazioni. Il test di sessione revocata sul lifecycle non viene presentato come copertura di tutte le RPC. La cancellazione Auth fa comunque fallire i controlli di utente esistente; una revoca della sola sessione è un caso diverso.
