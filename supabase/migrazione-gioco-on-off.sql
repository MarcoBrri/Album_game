-- Interruttore «gioco attivo» per ogni directory (già applicato al progetto Album's game).
alter table public.clubs add column if not exists game_enabled boolean not null default true;
-- Poi riesegui da schema.sql le funzioni club_info, club_members e submit_score.
