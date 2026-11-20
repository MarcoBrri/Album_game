-- Chi è chi: schema del database (Supabase / PostgreSQL)
-- Da incollare nel "SQL Editor" di Supabase ed eseguire una volta sola.

-- ───────────── Tabelle ─────────────
create table if not exists public.clubs (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,60}$'),
  name       text not null check (char_length(name) between 2 and 60),
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.people (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 80),
  nick       text not null default '' check (char_length(nick) <= 40),
  roles      text[] not null default '{}',
  comitato   text[] not null default '{}',
  gear       text[] not null default '{}',
  photo      text not null default '' check (char_length(photo) <= 150000),
  status     text not null default 'pending' check (status in ('pending','approved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists people_club_status_idx on public.people (club_id, status);

-- ───────────── Sicurezza (Row Level Security) ─────────────
alter table public.clubs  enable row level security;
alter table public.people enable row level security;

-- I visitatori anonimi non possono leggere né scrivere direttamente nelle tabelle:
revoke all on public.clubs, public.people from anon;

-- L'amministratore (proprietario della directory) gestisce tutto ciò che è suo.
drop policy if exists clubs_owner on public.clubs;
create policy clubs_owner on public.clubs
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists people_owner on public.people;
create policy people_owner on public.people
  for all to authenticated
  using (exists (select 1 from public.clubs c where c.id = people.club_id and c.owner_id = auth.uid()))
  with check (exists (select 1 from public.clubs c where c.id = people.club_id and c.owner_id = auth.uid()));

-- ───────────── Funzioni pubbliche (usate dal link condiviso, senza account) ─────────────

-- Nome della directory a partire dal link.
create or replace function public.club_by_slug(p_slug text)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name from public.clubs c where c.slug = p_slug;
$$;

-- Solo le persone APPROVATE.
create or replace function public.club_people(p_slug text)
returns table (id uuid, name text, nick text, roles text[], comitato text[], gear text[], photo text)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nick, p.roles, p.comitato, p.gear, p.photo
  from public.people p join public.clubs c on c.id = p.club_id
  where c.slug = p_slug and p.status = 'approved'
  order by p.name;
$$;

-- Proposta di una nuova persona: finisce sempre "in attesa" fino all'approvazione.
create or replace function public.submit_person(
  p_slug text, p_name text, p_nick text, p_roles text[], p_comitato text[], p_gear text[], p_photo text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
  v_roles    constant text[] := array['Aiutomonitore','Monitore','Comitato'];
  v_comitato constant text[] := array['Presidente','Vice Presidente','Team Coach','Segretaria','Cassiere',
                                      'Responsabile Eventi','Responsabile Sito/Area soci','Responsabile PR',
                                      'Responsabile attività invernali','Membro di comitato'];
  v_gear     constant text[] := array['Sci','Snowboard'];
begin
  select id into v_club from public.clubs where slug = p_slug;
  if v_club is null then raise exception 'club_not_found'; end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then raise exception 'invalid_name'; end if;
  if char_length(coalesce(p_nick,'')) > 40 then raise exception 'invalid_nick'; end if;
  if not (coalesce(p_roles,'{}')    <@ v_roles)    then raise exception 'invalid_roles'; end if;
  if not (coalesce(p_comitato,'{}') <@ v_comitato) then raise exception 'invalid_comitato'; end if;
  if not (coalesce(p_gear,'{}')     <@ v_gear)     then raise exception 'invalid_gear'; end if;
  if coalesce(p_photo,'') <> '' and (left(p_photo, 23) <> 'data:image/jpeg;base64,' or char_length(p_photo) > 150000)
    then raise exception 'invalid_photo'; end if;

  -- Freno anti-spam: massimo 200 proposte in attesa per directory.
  if (select count(*) from public.people where club_id = v_club and status = 'pending') >= 200
    then raise exception 'too_many_pending'; end if;

  insert into public.people (club_id, name, nick, roles, comitato, gear, photo, status)
  values (v_club, btrim(p_name), btrim(coalesce(p_nick,'')), coalesce(p_roles,'{}'), coalesce(p_comitato,'{}'),
          coalesce(p_gear,'{}'), coalesce(p_photo,''), 'pending');
end;
$$;

revoke all on function public.club_by_slug(text), public.club_people(text),
  public.submit_person(text,text,text,text[],text[],text[],text) from public;
grant execute on function public.club_by_slug(text), public.club_people(text),
  public.submit_person(text,text,text,text[],text[],text[],text) to anon, authenticated;
