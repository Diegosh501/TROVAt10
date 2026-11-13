-- Copy-only correction: existing event_updated type, authorization and delivery gates remain unchanged.
create or replace function private.notify_event_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_rec record; v_type text; v_title text; v_body text;
begin
  if old.status is not distinct from new.status
     and old.starts_at is not distinct from new.starts_at
     and old.venue is not distinct from new.venue
     and old.city is not distinct from new.city then return new; end if;
  if new.status='cancelled' and old.status is distinct from 'cancelled' then
    v_type:='event_cancelled'; v_title:='Partita annullata'; v_body:='L’organizzatore ha annullato la partita.';
  elsif new.status='in_progress' and old.status is distinct from 'in_progress' then
    v_type:='event_updated'; v_title:='Partita iniziata'; v_body:='L’organizzatore ha avviato la partita. Le iscrizioni sono chiuse.';
  elsif new.status='completed' and old.status is distinct from 'completed' then
    v_type:='event_updated'; v_title:='Partita conclusa'; v_body:='La partita è conclusa. Puoi ritrovarla nello storico dei tuoi match.';
  else
    v_type:='event_updated'; v_title:='Partita aggiornata'; v_body:='L’organizzatore ha aggiornato data, orario o luogo.';
  end if;
  for v_rec in
    select distinct m.user_id from public.event_members m where m.event_id=new.id and m.state='approved'
    union select new.creator_id
  loop
    if v_rec.user_id is distinct from new.creator_id then
      perform private.enqueue_user_notification(v_rec.user_id,new.id,v_type,v_title,v_body,new.id::text||':'||v_type||':'||new.updated_at::text);
    end if;
  end loop;
  return new;
end $$;
revoke all on function private.notify_event_update() from public, anon, authenticated;
