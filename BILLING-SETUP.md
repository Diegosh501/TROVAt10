# Premium Stripe: stato e configurazione

Checkpoint del 10 novembre 2026. Il Premium costa 4,99 EUR/anno ed è facoltativo. Tutti gli account iniziano Free. **Gli acquisti non sono attivati nel sito pubblico.**

## Risorse effettive

- Conto Stripe autorizzato: `trovat10.app`, `acct_1PdoAhFoPhAyQ2Ya`; titolare indicato: `diegolucente2000@gmail.com`.
- Ambiente separato creato: `TROVAT1O sviluppo`, `acct_1UaJJtFvMNykzCOW`. Il tentativo di selezione CLI ha confermato che richiede ancora una propria autorizzazione.
- Nessun prodotto, prezzo, cliente, abbonamento o pagamento Stripe è stato creato durante questa implementazione.
- La migrazione Supabase `20261110181941_trovat1o_stripe_billing_isolation` è applicata. Le due funzioni Edge di pagamento sono nei sorgenti, non ancora distribuite.
- CLI ufficiale 1.55.9; SDK `stripe@23.1.0`; API `2026-10-28.endive`. Il comando `stripe agent setup` non è necessario per usare la CLI autorizzata. L'installazione del plug-in Codex via quel comando non è riuscita per indisponibilità del marketplace atteso; non è un collegamento di pagamento completato.

## Flusso implementato nei sorgenti

`billing` verifica il token, il profilo Google, la sessione ancora presente e la quota del chiamante. Il prezzo viene riletto da Stripe e deve essere attivo, EUR 499 centesimi, ricorrenza annuale singola. Il browser non può scegliere prezzo, cliente, identità, piano o URL di ritorno.

Checkout usa un cliente mappato privatamente, idempotenza e un blocco per acquisti concorrenti. Un Checkout aperto viene riutilizzato; un abbonamento esistente porta alla gestione. Il portale permette annullamento al termine pagato e aggiornamento dei dati di pagamento; il backend rifiuta configurazioni che cambiano prezzo o cancellano immediatamente il periodo pagato.

`stripe-webhook` verifica firma sul corpo originale con tolleranza 300 secondi, modalità e versione API. Registra gli ID evento per duplicati/riprova, serializza la riconciliazione per cliente e rilegge lo stato Stripe dopo il blocco. Solo fatture pagate con il prezzo previsto concedono un termine finito. La pagina `billing=success` non concede Premium.

Eventi gestiti: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.subscription.created/updated/deleted/paused/resumed`, `invoice.paid`, `invoice.payment_failed`, `charge.refunded`, `charge.dispute.created/closed`, `radar.early_fraud_warning.created`.

Rimborsi integrali revocano la fattura interessata; quelli parziali mantengono il servizio residuo. Una contestazione blocca il Premium e una contestazione vinta rimuove soltanto quel blocco. Un segnale di frode mantiene una sospensione da esaminare; il relativo strumento operativo di revisione è ancora da completare. Il mapping passa da Charge/PaymentIntent a InvoicePayments, Invoice e Subscription, non da metadata modificabili dal browser.

Le tabelle `private.billing_*` contengono ID opachi, termini pagati, blocchi e deduplicazione. Nessuna copia di nomi, email, indirizzi o dati di carta del cliente. Gli acquisti `test` non modificano mai il piano reale in `public.subscriptions`.

## Configurazione ancora necessaria

Autorizzare la CLI nella sandbox già creata; verificare `stripe whoami --format json` e modalità prima di creare risorse. Non usare `config --list`, non stampare chiavi e non confondere una sandbox con un account Connect.

Creare nella sandbox un solo prodotto Premium, il prezzo annuale EUR 499 e una configurazione del portale con cancellazione `at_period_end`, aggiornamento del piano disabilitato e URL dell'app. Creare un endpoint webhook con versione API ed eventi sopra. Queste risorse non esistono ancora.

Usare una **restricted key** distinta per ambiente, con i soli permessi richiesti dalle chiamate di `billing-core.ts`, da verificare con prove effettive nella sandbox. Custodire chiave e firma webhook nei secrets Supabase; non nel frontend, Git, ZIP, log o chat. Variabili richieste:

| Variabile server | Uso |
| --- | --- |
| `BILLING_ENABLED` | `true` solo dopo configurazione e test; assente significa disabilitato |
| `STRIPE_MODE` | `test` oppure `live`, mai dedotta dal browser |
| `STRIPE_RESTRICTED_KEY` | Chiave limitata dello stesso ambiente, solo secrets |
| `STRIPE_ACCOUNT_ID` | Account/sandbox atteso, ricontrollato attraverso Stripe |
| `STRIPE_PREMIUM_PRICE_ID` | Prezzo annuale validato dal server |
| `STRIPE_PORTAL_CONFIGURATION_ID` | Configurazione portale validata dal server |
| `STRIPE_INTEGRATION_IDENTIFIER` | `trovat1o-annual-` più otto lettere casuali, stabile per integrazione |
| `STRIPE_WEBHOOK_SIGNING_SECRET` | Firma dell'endpoint, solo secrets |
| `APP_ORIGIN` | Origine HTTPS esatta dell'app |
| Chiavi Supabase server standard | Auth del chiamante e RPC di pagamento riservate |

Distribuire `billing` con verifica JWT e `stripe-webhook` senza JWT gateway: il webhook autentica Stripe mediante firma, non mediante un account utente. Il frontend usa solo `billingReady` e `billingMode`, che non concedono permessi. Restano `false`/`test` nel candidato.

Prima degli addebiti reali: collaudare acquisto, rinnovo, errore, annullamento, duplicati, rimborso e contestazione con chiavi limitate reali della sandbox. Validare dati fiscali, IVA, condizioni di vendita, gestione fatture/rimborsi e tariffe applicabili. `automatic_tax` non è abilitato: non va attivato prima di confermare una registrazione fiscale attiva. Riferimenti: [tasse sugli abbonamenti](https://docs.stripe.com/billing/taxes/collect-taxes), [webhook abbonamenti](https://docs.stripe.com/billing/subscriptions/webhooks).

## Prove eseguite e limiti

- 38 scenari degli effettivi gestori condivisi, con trasporti Auth/Stripe/DB controllati.
- 10 scenari delle effettive funzioni client: doppio tap, cambio account, redirect, piano di prova e query di successo.
- 6 prove crittografiche con il vero SDK Stripe: firma valida, corpo alterato, replay scaduto, altro segreto, rotazione e firma assente/malformata.
- 19 gruppi SQL eseguiti prima dell'applicazione in una transazione con rollback. Utenti/profili e tabelle aggiunte dal dry-run tornati a zero.
- La ripetizione dello stesso script sullo schema installato **non è stata eseguita**: due richieste del connettore sono scadute in attesa della conferma. Non va registrata come superata. Il test è `tests/sql/billing.sql`, rifiuta database popolati e usa rollback.
- Controllo TypeScript superato. Nessun acquisto reale, login Google reale, richiesta end-to-end Stripe/Edge o pagamento sandbox completato.
