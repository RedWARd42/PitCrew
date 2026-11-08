-- Tables are server-only; no anonymous writes or public operational data.
create table if not exists public.site (id text primary key, name text not null);
create table if not exists public.zone (id text primary key, site_id text references public.site(id), name text not null);
create table if not exists public.asset (id text primary key, zone_id text references public.zone(id), data jsonb not null);
create table if not exists public.topology_edge (id text primary key, from_asset text references public.asset(id), to_asset text references public.asset(id), kind text not null, redundancy_group text);
create table if not exists public.sensor (id text primary key, asset_id text references public.asset(id), data jsonb not null);
create table if not exists public.reading (id bigint generated always as identity primary key, sensor_id text references public.sensor(id), ts timestamptz not null, value double precision not null, source text not null);
create index if not exists reading_sensor_ts on public.reading(sensor_id,ts desc);
create table if not exists public.plant_snapshot (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
do $$
declare t text;
begin
 foreach t in array array['baseline','alarm','incident','warning','note','procedure','procedure_run','procedure_step_check','work_order','maintenance_window','person','shift','round','round_stop','handover','message_log','agent_trace','audit_log','readings_latest'] loop
 execute format('create table if not exists public.%I (id text primary key, data jsonb not null, updated_at timestamptz not null default now())', t);
 end loop;
 foreach t in array array['site','zone','asset','topology_edge','sensor','reading','plant_snapshot','baseline','alarm','incident','warning','note','procedure','procedure_run','procedure_step_check','work_order','maintenance_window','person','shift','round','round_stop','handover','message_log','agent_trace','audit_log','readings_latest'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select, insert, update, delete on public.%I to service_role',t);
 end loop;
 foreach t in array array['warning','incident','note','readings_latest','message_log'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t);
 end if;
 end loop;
end $$;
grant usage, select on all sequences in schema public to service_role;
