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

create or replace function public.ab_next_version(slug text)
returns integer
language sql stable
as $$
  select coalesce(max(version), 0) + 1 from public.ab_map_versions where map_slug = slug;
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
