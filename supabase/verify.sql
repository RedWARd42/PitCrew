-- Read-only setup audit. Run after applying the migration to the existing project.
-- Every row should have present, rls_enabled, server_crud, and private_to_server = true.
with expected(name, needs_realtime) as (
  values
    ('site',false), ('zone',false), ('asset',false), ('topology_edge',false),
    ('sensor',false), ('reading',false), ('plant_snapshot',false),
    ('baseline',false), ('alarm',false), ('incident',true), ('warning',true),
    ('note',true), ('procedure',false), ('procedure_run',false),
    ('procedure_step_check',false), ('work_order',false),
    ('maintenance_window',false), ('person',false), ('shift',false),
    ('round',false), ('round_stop',false), ('handover',false),
    ('message_log',true), ('agent_trace',false), ('audit_log',false),
    ('readings_latest',true)
)
select e.name,
  c.oid is not null as present,
  coalesce(c.relrowsecurity,false) as rls_enabled,
  coalesce(
    has_table_privilege('service_role',c.oid,'SELECT') and
    has_table_privilege('service_role',c.oid,'INSERT') and
    has_table_privilege('service_role',c.oid,'UPDATE') and
    has_table_privilege('service_role',c.oid,'DELETE'),false
  ) as server_crud,
  coalesce(
    not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') and
    not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'),false
  ) as private_to_server,
  not e.needs_realtime or exists (
    select 1 from pg_publication_tables p
    where p.pubname='supabase_realtime' and p.schemaname='public' and p.tablename=e.name
  ) as realtime_correct
from expected e
left join pg_namespace n on n.nspname='public'
left join pg_class c on c.relnamespace=n.oid and c.relname=e.name and c.relkind='r'
order by e.name;

select has_schema_privilege('service_role','public','USAGE') as server_schema_usage;
