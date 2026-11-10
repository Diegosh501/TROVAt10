# TROVAT1O · Supabase

## Stato attuale

Il progetto `TROVAT1O` è attivo in EU Central. `schema.sql` è stato applicato al database cloud con le relative migration. Tabelle e policy RLS esistono, ma non sono presenti profili o eventi; `onlineReady` rimane `false`. Il progetto non ha Edge Functions pubblicate, SMTP o Turnstile configurati. Nessuna sessione reale è stata usata per testare Auth o RLS.

Le modifiche a eventi, accesso, capienza, inviti e pin sono previste attraverso RPC con controlli server. Il browser non ha permessi di lettura o aggiornamento diretti sulla tabella `events`; legge l’RPC `event_feed`, che oscura luogo e coordinate di un evento privato fino all’ammissione. I link privati usano un token casuale di cui il database conserva soltanto SHA-256.

## Schema

- `profiles`: username, ruolo Host/Sportivo, attestazioni 18+, accettazione informativa e stato telefono.
- `events`: calcio a 5/8/11, data, luogo e pin, capienza, visibilità, ammissione e stato. La lettura passa dal feed filtrato.
- `event_members` e `event_invites`: richieste/partecipazioni e token invito privato.
- `event_host_contacts`: numero WhatsApp separato dall’evento, letto solo dal creatore o da utenti ammessi quando il creatore ha dato consenso.
- `pin_suggestions` e `player_reports`: suggerimenti e segnalazioni soggetti a controlli e limiti.
- `support_requests`, audit e quote: tabelle solo server-side per supporto e anti-abuso.
- `subscriptions`: stato Premium che deve essere scritto da un webhook affidabile, mai dal client.
- Tabelle telefono OTP: quote e numero temporaneo con scadenza; richiedono cleanup.

`notifications.sql` è uno scaffold separato. Preferenze e coda push non consegnano notifiche senza dispatcher, chiavi VAPID e pianificazione Cron.

## Prima di attivare account cloud

1. Configurare SMTP personalizzato, conferma email e recupero account in Supabase Auth.
2. Configurare Turnstile e gli URL redirect/CORS HTTPS effettivi.
3. Distribuire le Edge Functions da `functions/` e impostare i segreti sul lato server.
4. Se si attiva la verifica telefono, configurare Twilio Verify. Il servizio SMS può costare; le partite private tramite link non richiedono SMS.
5. Provare con utenti e sessioni separate: anonimo, Host, Sportivo, email non confermata, telefono non verificato, ammesso e non ammesso. Verificare soprattutto sede privata, capienza concorrente e ruoli.
6. Attivare reminder/push, cleanup, esportazione/cancellazione account, retention e pagamenti solo dopo test separati.
7. Aggiornare informative e `config.js`; non impostare `onlineReady: true` prima della verifica end-to-end.

## Mappatura della UI

| UI | Schema/backend |
| --- | --- |
| `date` + `time` | `events.starts_at`, conversione del fuso locale |
| `format`, `kind`, `title` | `format`, `kind`, `title` |
| `venue`, `city`, `lat`, `lon` | `venue`, `city`, `latitude`, `longitude` |
| `maxPlayers`, `cost`, `skill` | `max_players`, `cost_label`, `skill` |
| `isPublic`, `access`, `status` | `visibility`, `admission`, `status` |
| `participants[].status` | `event_members.state` |
| `inviteToken` | token casuale nel link; mai salvato in chiaro nel database |

Non considerare `localStorage` attendibile per identità, ruoli, capienza, autorizzazioni o pagamenti.

## Segreti e migrazioni

`config.js` non contiene dati cloud e mantiene il servizio spento. La chiave Supabase publishable/anon è pubblica per definizione, ma va usata solo insieme a RLS; service-role, chiave privata VAPID, Turnstile secret, credenziali Twilio, HMAC telefono e token Stripe vanno impostati solo nei secrets del provider. Non copiarli in HTML, repository, log o chat.

Il database è stato modificato tramite le migration registrate dal connettore Supabase. `schema.sql` documenta lo stato desiderato; prima di usare Supabase CLI (`db push`) allineare i file locali con l’intera cronologia remota e verificarne il diff. Non rieseguire manualmente questo baseline su un database con policy o dati già presenti.


## Audit applicato il 10 novembre 2026

Cronologia remota verificata: 20261110013616 trovat1o_v2_membership_privacy e 20261110015103 trovat1o_v2_notification_preferences. Le modifiche sono presenti nei blueprint schema.sql e notifications.sql. Le policy ora nascondono ai peer le richieste non ammesse e impediscono la riammissione automatica di utenti rimossi/rifiutati. Tabelle notifiche, preferenze, sottoscrizioni e coda privata sono state applicate, con opt-out ricontrollato al claim. Non esiste ancora un dispatcher di consegna.

Il test SQL autorizzato in tests/sql/membership-decisions.sql è passato con trigger attivi e rollback; i conteggi successivi users/events/members/app_notifications/notification_delivery_queue risultano zero. Per rieseguirlo occorre un ambiente di prova o l’autorizzazione esplicita del proprietario per il progetto remoto; il controllo nel file rifiuta database popolati.
