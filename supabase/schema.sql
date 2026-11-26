-- Club Quiz: schema completo del database (Supabase / PostgreSQL)
-- Per una NUOVA installazione: incolla tutto nel "SQL Editor" di Supabase ed esegui una volta sola.
-- (Se hai già una versione precedente, usa invece supabase/migrazione-campi.sql.)

-- ───────────── Validazione della scheda (definita dall'admin) ─────────────
create or replace function public.valid_fields(f jsonb) returns boolean
language plpgsql immutable set search_path = public as $$
declare fld jsonb; opt jsonb; sub jsonb; ids text[] := '{}'; v text;
begin
  if jsonb_typeof(f) is distinct from 'array' or jsonb_array_length(f) > 8 then return false; end if;
  for fld in select value from jsonb_array_elements(f) loop
    if jsonb_typeof(fld) is distinct from 'object' then return false; end if;
    v := fld->>'id';
    if v is null or v !~ '^[a-z0-9_]{1,24}$' or v = any(ids) then return false; end if;
    ids := ids || v;
    if char_length(coalesce(fld->>'label','')) not between 1 and 40 then return false; end if;
    if coalesce(fld->>'type','') not in ('text','single','multi') then return false; end if;
    if fld->>'type' <> 'text' then
      if jsonb_typeof(fld->'options') is distinct from 'array' or jsonb_array_length(fld->'options') not between 1 and 30 then return false; end if;
      for opt in select value from jsonb_array_elements(fld->'options') loop
        if jsonb_typeof(opt) is distinct from 'object' then return false; end if;
        v := opt->>'id';
        if v is null or v !~ '^[a-z0-9_]{1,24}$' or v = any(ids) then return false; end if;
        ids := ids || v;
        if char_length(coalesce(opt->>'label','')) not between 1 and 60 then return false; end if;
        if opt->'sub' is not null then
          if jsonb_typeof(opt->'sub') is distinct from 'array' or jsonb_array_length(opt->'sub') > 30 then return false; end if;
          for sub in select value from jsonb_array_elements(opt->'sub') loop
            if jsonb_typeof(sub) is distinct from 'object' then return false; end if;
            v := sub->>'id';
            if v is null or v !~ '^[a-z0-9_]{1,24}$' or v = any(ids) then return false; end if;
            ids := ids || v;
            if char_length(coalesce(sub->>'label','')) not between 1 and 60 then return false; end if;
          end loop;
        end if;
      end loop;
    end if;
  end loop;
  return true;
end $$;

create or replace function public.valid_person_data(f jsonb, d jsonb) returns boolean
language plpgsql immutable set search_path = public as $$
declare k text; v jsonb; fld jsonb; opt jsonb; sub jsonb; el jsonb; s text;
        ok_top text[]; ok_sub text[]; parent_of jsonb; vals text[]; tops int;
begin
  if jsonb_typeof(d) is distinct from 'object' or char_length(d::text) > 4000 then return false; end if;
  for k, v in select key, value from jsonb_each(d) loop
    fld := null;
    select x.value into fld from jsonb_array_elements(f) x where x.value->>'id' = k limit 1;
    if fld is null then return false; end if;
    if fld->>'type' = 'text' then
      if jsonb_typeof(v) is distinct from 'string' or char_length(v #>> '{}') > 100 then return false; end if;
    else
      if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v) > 40 then return false; end if;
      ok_top := '{}'; ok_sub := '{}'; parent_of := '{}'::jsonb;
      for opt in select value from jsonb_array_elements(fld->'options') loop
        ok_top := ok_top || (opt->>'id');
        if opt->'sub' is not null then
          for sub in select value from jsonb_array_elements(opt->'sub') loop
            ok_sub := ok_sub || (sub->>'id');
            parent_of := parent_of || jsonb_build_object(sub->>'id', opt->>'id');
          end loop;
        end if;
      end loop;
      vals := '{}';
      for el in select value from jsonb_array_elements(v) loop
        if jsonb_typeof(el) is distinct from 'string' then return false; end if;
        vals := vals || (el #>> '{}');
      end loop;
      tops := 0;
      foreach s in array vals loop
        if s = any(ok_top) then tops := tops + 1;
        elsif s = any(ok_sub) then
          if not ((parent_of->>s) = any(vals)) then return false; end if;
        else return false; end if;
      end loop;
      if fld->>'type' = 'single' and tops > 1 then return false; end if;
    end if;
  end loop;
  return true;
end $$;


-- ───────────── Tabelle ─────────────
create table if not exists public.clubs (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,60}$'),
  name       text not null check (char_length(name) between 2 and 60),
  fields     jsonb not null default '[]'::jsonb constraint clubs_fields_valid check (public.valid_fields(fields)),
  use_nick   boolean not null default true,
  game_enabled boolean not null default true,
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.people (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 80),
  nick       text not null default '' check (char_length(nick) <= 40),
  data       jsonb not null default '{}'::jsonb constraint people_data_size check (char_length(data::text) <= 4000),
  photo      text not null default '' check (char_length(photo) <= 150000),
  status     text not null default 'pending' check (status in ('pending','approved')),
  legend     boolean not null default false,
  legend_note text not null default '' check (char_length(legend_note) <= 80),
  consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists clubs_owner_idx on public.clubs (owner_id);
create index if not exists people_club_status_idx on public.people (club_id, status);

-- ───────────── Sicurezza (Row Level Security) ─────────────
alter table public.clubs  enable row level security;
alter table public.people enable row level security;
revoke all on public.clubs, public.people from anon;

drop policy if exists clubs_owner on public.clubs;
create policy clubs_owner on public.clubs
  for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists people_owner on public.people;
create policy people_owner on public.people
  for all to authenticated
  using (exists (select 1 from public.clubs c where c.id = people.club_id and c.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.clubs c where c.id = people.club_id and c.owner_id = (select auth.uid())));

grant select, insert, update, delete on public.clubs, public.people to authenticated;

-- ───────────── Funzioni pubbliche (usate dal link condiviso, senza account) ─────────────
drop function if exists public.club_info(text);
create function public.club_info(p_slug text)
returns table (id uuid, name text, fields jsonb, use_nick boolean, game_enabled boolean, members int)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.fields, c.use_nick, c.game_enabled,
         (select count(*)::int from public.people p where p.club_id = c.id and p.status = 'approved')
  from public.clubs c where c.slug = p_slug;
$$;

-- Solo persone approvate, e solo se il gioco è attivo
drop function if exists public.club_members(text);
create function public.club_members(p_slug text)
returns table (id uuid, name text, nick text, data jsonb, photo text, legend boolean, legend_note text)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nick, p.data, p.photo, p.legend, p.legend_note
  from public.people p join public.clubs c on c.id = p.club_id
  where c.slug = p_slug and p.status = 'approved' and c.game_enabled
  order by p.name;
$$;

create or replace function public.submit_member(p_slug text, p_name text, p_nick text, p_data jsonb, p_photo text, p_consent boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_fields jsonb; v_nick boolean;
begin
  select id, fields, use_nick into v_club, v_fields, v_nick from public.clubs where slug = p_slug;
  if v_club is null then raise exception 'club_not_found'; end if;
  if p_consent is not true then raise exception 'consent_required'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then raise exception 'invalid_name'; end if;
  if char_length(coalesce(p_nick,'')) > 40 then raise exception 'invalid_nick'; end if;
  if not public.valid_person_data(v_fields, coalesce(p_data, '{}'::jsonb)) then raise exception 'invalid_data'; end if;
  if coalesce(p_photo,'') = '' then raise exception 'photo_required'; end if;
  if left(p_photo, 23) <> 'data:image/jpeg;base64,' or char_length(p_photo) > 150000
    then raise exception 'invalid_photo'; end if;
  if (select count(*) from public.people where club_id = v_club and status = 'pending') >= 200
    then raise exception 'too_many_pending'; end if;
  insert into public.people (club_id, name, nick, data, photo, status, consent_at)
  values (v_club, btrim(p_name), case when v_nick then btrim(coalesce(p_nick,'')) else '' end,
          coalesce(p_data, '{}'::jsonb), p_photo, 'pending', now());
end;
$$;

revoke all on function public.club_info(text), public.club_members(text),
  public.submit_member(text,text,text,jsonb,text,boolean) from public;
grant execute on function public.club_info(text), public.club_members(text),
  public.submit_member(text,text,text,jsonb,text,boolean) to anon, authenticated;


-- ───────────── Classifica ─────────────
create table if not exists public.scores (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs(id) on delete cascade,
  player     text not null check (char_length(player) between 1 and 30),
  mode       text not null check (mode in ('photo','name','hard')),
  kind       text not null check (kind in ('10','20','all')),
  n          int  not null check (n between 1 and 500),
  score      numeric(6,1) not null check (score >= 0),
  max        numeric(6,1) not null check (max > 0),
  seconds    int  not null default 0 check (seconds between 0 and 86400),
  created_at timestamptz not null default now(),
  check (score <= max),
  check (max <= n * 30),
  check (kind = 'all' or n = kind::int)
);
create index if not exists scores_club_idx on public.scores (club_id, mode, kind);

alter table public.scores enable row level security;
revoke all on public.scores from anon;
grant select, insert, update, delete on public.scores to authenticated;

drop policy if exists scores_owner on public.scores;
create policy scores_owner on public.scores
  for all to authenticated
  using (exists (select 1 from public.clubs c where c.id = scores.club_id and c.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.clubs c where c.id = scores.club_id and c.owner_id = (select auth.uid())));

-- Classifica pubblica: il miglior risultato di ogni nome, ordinato per percentuale e poi per tempo.
create or replace function public.club_scores(p_slug text, p_mode text, p_kind text)
returns table (id uuid, player text, n int, score numeric, max numeric, seconds int, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select t.id, t.player, t.n, t.score, t.max, t.seconds, t.created_at
  from (
    select distinct on (lower(s.player)) s.id, s.player, s.n, s.score, s.max, s.seconds, s.created_at
    from public.scores s join public.clubs c on c.id = s.club_id
    where c.slug = p_slug and s.mode = p_mode and s.kind = p_kind
    order by lower(s.player), (s.score / s.max) desc, s.seconds asc
  ) t
  order by (t.score / t.max) desc, t.seconds asc
  limit 100;
$$;

-- Salvataggio di un punteggio (senza account).
create or replace function public.submit_score(
  p_slug text, p_player text, p_mode text, p_kind text, p_n int, p_score numeric, p_max numeric, p_seconds int
) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_on boolean;
begin
  select id, game_enabled into v_club, v_on from public.clubs where slug = p_slug;
  if v_club is null then raise exception 'club_not_found'; end if;
  if not v_on then raise exception 'game_disabled'; end if;
  if p_player is null or char_length(btrim(p_player)) not between 1 and 30 then raise exception 'invalid_player'; end if;
  if (select count(*) from public.scores where club_id = v_club) >= 3000 then raise exception 'too_many_scores'; end if;
  insert into public.scores (club_id, player, mode, kind, n, score, max, seconds)
  values (v_club, btrim(p_player), p_mode, p_kind, p_n, p_score, p_max, least(greatest(coalesce(p_seconds,0),0),86400));
end;
$$;

revoke all on function public.club_scores(text,text,text), public.submit_score(text,text,text,text,int,numeric,numeric,int) from public;
grant execute on function public.club_scores(text,text,text), public.submit_score(text,text,text,text,int,numeric,numeric,int) to anon, authenticated;
