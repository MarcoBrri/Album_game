-- Migrazione: scheda configurabile per ogni directory (campi definiti dall'admin).
-- Sicura da rieseguire. Non elimina nulla: le vecchie colonne (roles, comitato, gear) restano inutilizzate.

-- ───────────── Validazione della struttura e dei dati ─────────────
create or replace function public.valid_fields(f jsonb) returns boolean
language plpgsql immutable as $$
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
language plpgsql immutable as $$
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

-- ───────────── Colonne nuove ─────────────
alter table public.clubs  add column if not exists fields   jsonb   not null default '[]'::jsonb;
alter table public.clubs  add column if not exists use_nick boolean not null default true;
alter table public.people add column if not exists data     jsonb   not null default '{}'::jsonb;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clubs_fields_valid') then
    alter table public.clubs add constraint clubs_fields_valid check (public.valid_fields(fields));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'people_data_size') then
    alter table public.people add constraint people_data_size check (char_length(data::text) <= 4000);
  end if;
end $$;

-- ───────────── Le directory esistenti ricevono la struttura «Sci club» ─────────────
update public.clubs set fields = '[
 {"id":"ruolo","label":"Ruolo","type":"multi","options":[
   {"id":"aiuto","label":"Aiutomonitore"},
   {"id":"monitore","label":"Monitore"},
   {"id":"comitato","label":"Comitato","sub":[
     {"id":"c_pres","label":"Presidente"},{"id":"c_vice","label":"Vice Presidente"},{"id":"c_coach","label":"Team Coach"},
     {"id":"c_segr","label":"Segretaria"},{"id":"c_cass","label":"Cassiere"},{"id":"c_eventi","label":"Responsabile Eventi"},
     {"id":"c_sito","label":"Responsabile Sito/Area soci"},{"id":"c_pr","label":"Responsabile PR"},
     {"id":"c_inv","label":"Responsabile attività invernali"},{"id":"c_membro","label":"Membro di comitato"}]}]},
 {"id":"attrezzo","label":"Attrezzo","type":"multi","options":[{"id":"sci","label":"Sci"},{"id":"snow","label":"Snowboard"}]}
]'::jsonb where fields = '[]'::jsonb;

-- Conversione dei profili già inseriti
update public.people p set data = jsonb_build_object(
  'ruolo', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select case r when 'Aiutomonitore' then 'aiuto' when 'Monitore' then 'monitore' when 'Comitato' then 'comitato' end as x from unnest(p.roles) r
      union all
      select case c when 'Presidente' then 'c_pres' when 'Vice Presidente' then 'c_vice'
                    when 'Vice Presidente e Responsabile Formazione' then 'c_vice' when 'Team Coach' then 'c_coach'
                    when 'Segretaria' then 'c_segr' when 'Cassiere' then 'c_cass' when 'Responsabile Eventi' then 'c_eventi'
                    when 'Responsabile Sito/Area soci' then 'c_sito' when 'Responsabile PR' then 'c_pr'
                    when 'Responsabile attività invernali' then 'c_inv' when 'Membro di comitato' then 'c_membro' end from unnest(p.comitato) c
    ) q where x is not null),
  'attrezzo', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select case g when 'Sci' then 'sci' when 'Snowboard' then 'snow' end as x from unnest(p.gear) g) q where x is not null)
) where p.data = '{}'::jsonb;

-- ───────────── Funzioni pubbliche (nuove) ─────────────
create or replace function public.club_info(p_slug text)
returns table (id uuid, name text, fields jsonb, use_nick boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.fields, c.use_nick from public.clubs c where c.slug = p_slug;
$$;

create or replace function public.club_members(p_slug text)
returns table (id uuid, name text, nick text, data jsonb, photo text)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nick, p.data, p.photo
  from public.people p join public.clubs c on c.id = p.club_id
  where c.slug = p_slug and p.status = 'approved'
  order by p.name;
$$;

create or replace function public.submit_member(p_slug text, p_name text, p_nick text, p_data jsonb, p_photo text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_fields jsonb; v_nick boolean;
begin
  select id, fields, use_nick into v_club, v_fields, v_nick from public.clubs where slug = p_slug;
  if v_club is null then raise exception 'club_not_found'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then raise exception 'invalid_name'; end if;
  if char_length(coalesce(p_nick,'')) > 40 then raise exception 'invalid_nick'; end if;
  if not public.valid_person_data(v_fields, coalesce(p_data, '{}'::jsonb)) then raise exception 'invalid_data'; end if;
  if coalesce(p_photo,'') <> '' and (left(p_photo, 23) <> 'data:image/jpeg;base64,' or char_length(p_photo) > 150000)
    then raise exception 'invalid_photo'; end if;
  if (select count(*) from public.people where club_id = v_club and status = 'pending') >= 200
    then raise exception 'too_many_pending'; end if;
  insert into public.people (club_id, name, nick, data, photo, status)
  values (v_club, btrim(p_name), case when v_nick then btrim(coalesce(p_nick,'')) else '' end,
          coalesce(p_data, '{}'::jsonb), coalesce(p_photo,''), 'pending');
end;
$$;

revoke all on function public.club_info(text), public.club_members(text),
  public.submit_member(text,text,text,jsonb,text) from public;
grant execute on function public.club_info(text), public.club_members(text),
  public.submit_member(text,text,text,jsonb,text) to anon, authenticated;

-- Le vecchie funzioni non servono più: nessun accesso pubblico
revoke execute on function public.club_by_slug(text), public.club_people(text),
  public.submit_person(text,text,text,text[],text[],text[],text) from anon, authenticated;

-- ───────────── Classifica: ora una scheda può valere più di 7 punti ─────────────
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'public.scores'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%* 7%' loop
    execute format('alter table public.scores drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'scores_max_per_question') then
    alter table public.scores add constraint scores_max_per_question check (max <= n * 30);
  end if;
end $$;
