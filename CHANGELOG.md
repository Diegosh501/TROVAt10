# Candidato rc.7 / collaudo cloud-test.10 — 13 novembre 2026

- Nuovo controllo PostgreSQL 17.11 isolato in CI: replay delle 17 migrazioni, regressioni, nove scenari concorrenti e ripristino cifrato in un database nuovo, con confronto di dati e permessi effettivi. Backup operatori cifrato in streaming; otto prove e protezioni dell’ambiente di test. Nessun backup di dati reali o servizio a pagamento attivato.

- Assistenza disattivata: contatto email diretto, senza pulsante di invio non operativo. CAPTCHA caricato solo aprendo i percorsi pertinenti; la sua indisponibilità non impedisce il caricamento Google.
- Percorso supporto pronto per il server: origini esatte, sessione verificata due volte, corpo limitato, conferme esplicite, quota e ricevuta atomiche, protezione anti-riuso CAPTCHA e retry con la stessa ricevuta per 24 ore. Schema remoto non applicato: conferme tecniche scadute. Nessun falso invio riuscito.
- 27 suite Node, 16 moduli e 16 regressioni SQL locali. 33 controlli reali dei pin privati su coordinate presenti, prima/dopo ammissione e rimozione, più creatore e anonimo. Scenario H chiuso nell’ambito provato.
- Collaudo Cloudflare aggiornato e verificato; sito principale ancora rc.1. Nessun pagamento, purge, job o nuovo fattore MFA attivato.
- Istruzioni supporto, guida, checkpoint, pacchetti e sorgenti allineati. I risultati locali non equivalgono a CAPTCHA, assistenza o ripristino operativi.

# Candidato V1.0 - ripresa dell’11 novembre 2026

- Admin Edge v2 distribuita, confronto del sorgente remoto e rifiuto verificato di accessi senza credenziali/token falso. Nessun nuovo frontend pubblico.
- Nuovo ciclo account Free dal primo match, conferma esplicita, avvisi, grazia 48 ore, protezioni su Premium, Admin, dati condivisi, acquisti e pratiche. Migrazione richiesta ma non applicata per conferma scaduta; tutte le attivazioni restano spente.
- Test: 22 suite Node, 13 moduli SQL e 12 regressioni locali con rollback. Il browser ha provato creazione, modifica, richiesta dalla mappa, ricerca, storico, assistenza e download PNG con dati sintetici.
- Corretto conflitto CSS che riduceva i campi mobile a 11 px: ora 16 px/46 px. Struttura del form corretta, opzioni compatte, consenso a larghezza piena e nomi accessibili nel supporto.
- Informative pre-lancio v2 e versione delle conferme allineate nel candidato; README, stato, backend, readiness e guida illustrata aggiornati. Cache shell nuova per il prossimo deploy.
- Sincronizzazione GitHub e ricevute CI separate dal sito esistente; nessuna spesa, acquisto o cancellazione di account reale.

# 2.0.2 · 10 novembre 2026

## In preparazione - V1.0 cloud e amministrazione

- Confine cloud: niente lettura/scrittura dei dati demo nel browser e nessuna scelta sessione/dispositivo nel flusso online.
- Isolamento al cambio account, pulizia dei dati amministrativi e rifiuto di risposte tardive.
- Cache limitata alla shell pubblica senza token degli inviti o richieste autorizzate.
- Backend Admin con allowlist privata, sessione valida, TOTP recente, quote e audit atomico; migrazione installata ed Edge v1 pubblicata.
- Dieci suite locali, 24 scenari del gestore Edge e 21 gruppi SQL con rollback superati.
- Cronologia effettiva delle nove migrazioni preservata. Google, tutti Free, scadenza sette giorni e prove reali restano aperti: vedere V1-STATUS.md.
- La preview frontend pubblica resta 2.0.2; nessun rilascio V1.0 dichiarato.


- Logo runtime PNG da 480×160 e 74.898 byte; originale approvato 2172×724 conservato.
- Dimensioni intrinseche delle immagini, spazio iniziale della lista riservato per evitare il salto del footer.
- Contrasto della navigazione corretto, marchio azionabile da tastiera e target touch secondari almeno 44px.
- Workflow CI verificato localmente: controlli Node, installazione da lock, pacchetti, Wrangler dry-run e confronti degli archivi. Nessun deploy automatico o segreto CI.
- I pacchetti includono workflow e regole per escludere credenziali e file generati.

# 2.0.1 · 10 novembre 2026

- Correzioni raggruppate dopo il primo deploy 2.0.0: focus nelle finestre, Escape, mappa, CTA Auth unica e recupero password/CAPTCHA.
- Prefisso telefono Italia +39 selezionabile e normalizzazione numeri incollati.
- Rientro dopo uscita/rifiuto sottoposto ad approvazione, nessuna partecipazione duplicata dell’organizzatore.
- Richieste non ammesse nascoste agli altri partecipanti da policy server.
- Date future/capienza validate, coordinate assenti escluse, invito visibile nel riepilogo e PNG privato generabile senza invito.
- Dipendenze Supabase fissate a 2.119.0, integrità per SDK browser e Leaflet, lock Wrangler completo.
- Protezioni HTTPS/frame/CSP e pacchetti confrontati con i sorgenti prima dello ZIP.
- Audit, evidenze e rollback registrati.

# Changelog TROVAT1O

## 2.0 · 10 novembre 2026

- Allineati logo PNG, palette, icone, favicon, manifest e cache PWA.
- Rifiniti ricerca, lista, mappa demo, schede evento, onboarding, ruoli, I miei match e CTA mobile.
- Aggiunti nel client i flussi cloud per feed, inviti privati, richieste/approvazioni, roster, pin, contatto Host, segnalazioni e stato evento.
- Applicato su Supabase lo schema V2 con RLS, feed che oscura il luogo privato, limiti OTP e funzioni server per le operazioni evento. Tabella applicativa vuota; cloud client ancora spento.
- Aggiornate istruzioni, stato di readiness, sicurezza e pacchetto per la preview.

La release online `workers.dev` resta una demo statica finché non viene aggiornata col pacchetto e non si configurano SMTP, Turnstile e funzioni server. Non presentarla come servizio multiutente attivo.

## Candidato non pubblicato — checkpoint Google e Premium, 2026-11-10

- Google PKCE e completamento profilo, invito preservato, gate pubblico senza SMS quando Google è verificato.
- Billing annuale 4,99 EUR con Checkout/portale, firme SDK, deduplicazione, separazione test/live e gestione rinnovi/rimborsi/contestazioni. Pagamenti disabilitati e funzioni Edge ancora da distribuire.
- Dodici migrazioni effettive preservate; nuove prove OAuth e Billing, lockfile Deno e istruzioni di ripresa.
- Nessun deploy frontend e nessun pagamento reale. Provider Google e collaudi reali ancora aperti.
