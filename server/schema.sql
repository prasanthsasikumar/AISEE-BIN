-- AISEE-BIN map versions on the shared Supabase (db.flowsxr.com).
-- Tables use the ab_ prefix (option A in SUPABASE.md). Idempotent.

create table if not exists public.ab_map_versions (
  id              uuid primary key default gen_random_uuid(),
  map_slug        text not null default 'default',
  version         integer not null,
  source          text not null check (source in ('ios', 'web')),
  note            text,
  graph           jsonb not null,           -- NavigationMap JSON (nodes, edges, names, categories, details, aliases)
  worldmap_path   text,                     -- storage path of the ARWorldMap archive
  pointcloud_path text,                     -- storage path of the Float32 xyz point cloud
  point_count     integer,
  created_at      timestamptz not null default now(),
  unique (map_slug, version)
);

create index if not exists ab_map_versions_slug_version on public.ab_map_versions (map_slug, version desc);

alter table public.ab_map_versions enable row level security;

drop policy if exists ab_versions_read on public.ab_map_versions;
create policy ab_versions_read on public.ab_map_versions
  for select to anon, authenticated using (true);

-- MVP: anyone holding the publishable key may publish a version. Versions are
-- append-only (no update/delete policy), so a bad upload never destroys data.
drop policy if exists ab_versions_insert on public.ab_map_versions;
create policy ab_versions_insert on public.ab_map_versions
  for insert to anon, authenticated with check (true);

-- Skips version numbers that already have files in the bucket, not only rows:
-- a publish that uploaded its world map and then failed leaves `<slug>/v<n>/…`
-- behind with no row, and the app uploads with x-upsert, so a retry on the same
-- number was an UPDATE that no storage policy allows (RLS 403). Live since
-- 2026-10-26.
create or replace function public.ab_next_version(slug text)
returns integer
language sql stable
as $$
  select greatest(
    coalesce((select max(version) from public.ab_map_versions where map_slug = slug), 0),
    coalesce((select max(substr(split_part(name, '/', 2), 2)::int)
              from storage.objects
              where bucket_id = 'aiseebin-maps'
                and split_part(name, '/', 1) = slug
                and split_part(name, '/', 2) ~ '^v[0-9]+$'), 0)
  ) + 1;
$$;

grant execute on function public.ab_next_version(text) to anon, authenticated;

-- Public-read bucket for world maps and point clouds.
insert into storage.buckets (id, name, public)
values ('aiseebin-maps', 'aiseebin-maps', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists ab_maps_read on storage.objects;
create policy ab_maps_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'aiseebin-maps');

drop policy if exists ab_maps_insert on storage.objects;
create policy ab_maps_insert on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'aiseebin-maps');

-- Node count as a PostgREST computed column, so the web editor's version list can
-- show "N nodes" without selecting the whole `graph` payload for every version.
create or replace function public.node_count(public.ab_map_versions)
returns integer
language sql stable
as $$
  select jsonb_array_length(coalesce($1.graph -> 'pois', '[]'::jsonb));
$$;

grant execute on function public.node_count(public.ab_map_versions) to anon, authenticated;

-- Field-test results from the apps (Flower Dome POC, 2026-09-30): accuracy
-- checks, marked points, scan-link walks, uploaded logs. Append-only like the
-- map versions; readable with the publishable key so results can be pulled
-- the same day without anyone sending files.
create table if not exists public.ab_field_results (
  id           bigserial primary key,
  created_at   timestamptz not null default now(),
  kind         text not null,          -- check | mark | link | log
  platform     text,                   -- ios | android
  device       text,
  app_version  text,
  map_slug     text,
  map_version  int,
  mode         text,                   -- glasses | phone
  localizer    text,
  point_id     text,
  point_name   text,
  payload      jsonb not null default '{}'::jsonb
);
alter table public.ab_field_results enable row level security;
drop policy if exists ab_field_read on public.ab_field_results;
create policy ab_field_read on public.ab_field_results for select to anon, authenticated using (true);
drop policy if exists ab_field_insert on public.ab_field_results;
create policy ab_field_insert on public.ab_field_results for insert to anon, authenticated with check (true);
grant select, insert on public.ab_field_results to anon, authenticated;
grant usage, select on sequence public.ab_field_results_id_seq to anon, authenticated;

-- Usage logging: the apps upload one header row per session (ab_sessions) and
-- append-only event rows (ab_events). Idempotent uploads: unique (session_id, seq)
-- plus on_conflict ignore-duplicates. Readable with the publishable key so the
-- review page can pull sessions without anyone sending files.
create table if not exists public.ab_sessions (
  session_id   uuid primary key,
  install_id   text,
  platform     text,                   -- ios | android
  device       text,
  os_version   text,
  app_version  text,
  build_config text,                   -- debug | release
  simulator    boolean,
  staff        boolean,
  started_at   timestamptz,
  received_at  timestamptz not null default now()
);
alter table public.ab_sessions enable row level security;
drop policy if exists ab_sessions_read on public.ab_sessions;
create policy ab_sessions_read on public.ab_sessions for select to anon, authenticated using (true);
drop policy if exists ab_sessions_insert on public.ab_sessions;
create policy ab_sessions_insert on public.ab_sessions for insert to anon, authenticated with check (true);
grant select, insert on public.ab_sessions to anon, authenticated;
-- Which app logged the session: aiseebin | nus-open-house (older rows and clients: aiseebin).
alter table public.ab_sessions add column if not exists app text not null default 'aiseebin';

create table if not exists public.ab_events (
  id           bigserial primary key,
  session_id   uuid not null,
  seq          int not null,
  t            timestamptz not null,
  type         text not null,          -- map.loaded | mode.enter | loc.attempt | ...
  data         jsonb not null default '{}'::jsonb,
  received_at  timestamptz not null default now(),
  unique (session_id, seq)
);
create index if not exists ab_events_session_seq_idx on public.ab_events (session_id, seq);
create index if not exists ab_events_t_idx on public.ab_events (t);
alter table public.ab_events enable row level security;
drop policy if exists ab_events_read on public.ab_events;
create policy ab_events_read on public.ab_events for select to anon, authenticated using (true);
drop policy if exists ab_events_insert on public.ab_events;
create policy ab_events_insert on public.ab_events for insert to anon, authenticated with check (true);
grant select, insert on public.ab_events to anon, authenticated;
grant usage, select on sequence public.ab_events_id_seq to anon, authenticated;

-- One row per session, built from the events so a session whose header never
-- arrived still shows up (header columns are then null).
-- Dropped first: adding `app` moves the columns, which create or replace cannot do.
drop view if exists public.ab_session_summary;
create view public.ab_session_summary with (security_invoker = on) as
select
  e.session_id,
  s.install_id, s.app, s.platform, s.device, s.os_version, s.app_version,
  s.build_config, s.simulator, s.staff, s.started_at, s.received_at,
  min(e.t) as first_t,
  max(e.t) as last_t,
  extract(epoch from (max(e.t) - min(e.t)))::int as duration_s,
  count(*)::int as event_count,
  coalesce(array_remove(array_agg(distinct e.data->>'slug') filter (where e.type = 'map.loaded'), null), '{}') as maps,
  coalesce(array_remove(array_agg(distinct e.data->>'mode') filter (where e.type = 'mode.enter'), null), '{}') as modes,
  (count(*) filter (where e.type = 'speech.heard'))::int as utterances,
  (count(*) filter (where e.type = 'nav.arrived'))::int as arrivals,
  (count(*) filter (where e.type = 'nav.cancel'))::int as cancels,
  -- A fix is an accepted one: ok, and not rejected by the jump gate (accepted false).
  (count(*) filter (where e.type = 'loc.attempt' and (e.data->>'ok') = 'true'
                    and coalesce(e.data->>'accepted', 'true') <> 'false'))::int as fixes,
  (count(*) filter (where e.type = 'loc.attempt'))::int as attempts,
  (count(*) filter (where e.type = 'error'))::int as errors
from public.ab_events e
left join public.ab_sessions s on s.session_id = e.session_id
group by e.session_id, s.session_id, s.install_id, s.app, s.platform, s.device, s.os_version,
         s.app_version, s.build_config, s.simulator, s.staff, s.started_at, s.received_at;
grant select on public.ab_session_summary to anon, authenticated;
