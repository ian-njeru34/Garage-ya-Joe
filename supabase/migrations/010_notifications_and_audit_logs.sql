-- Garage ya Joe: append-only audit trail and notification delivery foundation.
-- Audit records store changed column names, not old/new values, to reduce unnecessary PII retention.
-- Notification delivery is performed by trusted server-side workers/Edge Functions.

create table public.audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  location_id uuid,
  actor_id uuid references public.profiles(id) on delete set null,
  table_name text not null,
  record_id text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE')),
  changed_columns text[] not null default '{}',
  occurred_at timestamptz not null default now(),
  constraint audit_logs_location_fk
    foreign key (business_id,location_id)
    references public.locations(business_id,id) on delete restrict
);

create index audit_logs_business_time_idx
  on public.audit_logs(business_id,occurred_at desc);
create index audit_logs_location_time_idx
  on public.audit_logs(business_id,location_id,occurred_at desc);
create index audit_logs_record_idx
  on public.audit_logs(business_id,table_name,record_id,occurred_at desc);
create index audit_logs_actor_time_idx
  on public.audit_logs(business_id,actor_id,occurred_at desc);

alter table public.audit_logs enable row level security;

insert into public.permission_definitions(code,description)
values ('audit.view','View business and location-scoped audit history.')
on conflict (code) do nothing;

insert into public.role_permissions(role_code,permission_code)
values
 ('owner','audit.view'),
 ('administrator','audit.view'),
 ('accountant','audit.view')
on conflict do nothing;

create policy "Authorized staff view audit history"
on public.audit_logs for select to authenticated
using (private.has_business_permission(business_id,'audit.view',location_id));

-- The trigger owner writes audit rows. Client roles cannot write, alter, or delete them.
revoke all on public.audit_logs from anon,authenticated;
grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;

create or replace function private.capture_audit_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
  v_business_id uuid;
  v_location_id uuid;
  v_record_id text;
  v_changed_columns text[];
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old);
    v_row := v_old;
  else
    v_new := to_jsonb(new);
    v_row := v_new;
  end if;

  if tg_table_name = 'businesses' then
    v_business_id := nullif(v_row->>'id','')::uuid;
  else
    v_business_id := nullif(coalesce(v_new->>'business_id',v_old->>'business_id'),'')::uuid;
  end if;
  v_location_id := nullif(coalesce(v_new->>'location_id',v_old->>'location_id'),'')::uuid;
  v_record_id := coalesce(v_row->>'id',v_row->>'code',v_row->>'sku','unknown');

  select coalesce(array_agg(k order by k),array[]::text[])
    into v_changed_columns
  from (
    select key as k
    from jsonb_object_keys(coalesce(v_new,'{}'::jsonb) || coalesce(v_old,'{}'::jsonb)) as keys(key)
    where v_new->key is distinct from v_old->key
  ) changed;

  if v_business_id is not null then
    insert into public.audit_logs(
      business_id,location_id,actor_id,table_name,record_id,operation,changed_columns
    ) values (
      v_business_id,v_location_id,(select auth.uid()),tg_table_name,v_record_id,tg_op,v_changed_columns
    );
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.capture_audit_change() from public,anon,authenticated;
grant usage on schema private to authenticated;

-- Business-scoped operational records are audited centrally.
do $$
declare
  v_table text;
  v_tables text[] := array[
    'businesses','locations','user_roles','customers','vehicles','vehicle_customer_relationships',
    'products','product_categories','product_part_numbers','product_vehicle_compatibility',
    'product_images','warehouses','inventory_balances','stock_movements',
    'service_appointments','vehicle_inspections','job_cards','job_tasks','job_parts',
    'job_work_logs','service_history',
    'suppliers','supplier_product_references','purchase_orders','purchase_order_items',
    'import_requests','import_request_supplier_quotes','shipments','shipment_purchase_orders',
    'shipment_items','shipment_landed_costs','shipment_landed_cost_allocations',
    'goods_receipts','goods_receipt_items',
    'quotations','quotation_items','quotation_status_history','sales_orders',
    'sales_order_items','invoices','invoice_items',
    'accounting_periods','chart_of_accounts','cash_accounts','journal_entries','journal_lines',
    'customer_payments','supplier_payments','credit_notes'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is not null then
      execute format(
        'create trigger %I after insert or update or delete on public.%I for each row execute function private.capture_audit_change()',
        'audit_' || v_table, v_table
      );
    end if;
  end loop;
end;
$$;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  location_id uuid,
  recipient_user_id uuid not null references public.profiles(id) on delete restrict,
  category text not null check (category in (
    'booking','job_update','quotation','invoice','payment','importation','shipment','system'
  )),
  channel text not null check (channel in ('in_app','email','whatsapp')),
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','processing','sent','failed','read','cancelled')),
  scheduled_at timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notifications_business_id_id_unique unique (business_id,id),
  constraint notifications_location_fk
    foreign key (business_id,location_id)
    references public.locations(business_id,id) on delete restrict,
  check (length(trim(title)) > 0),
  check (length(trim(body)) > 0)
);

create index notifications_recipient_unread_idx
  on public.notifications(recipient_user_id,status,created_at desc);
create index notifications_business_schedule_idx
  on public.notifications(business_id,status,scheduled_at)
  where status in ('queued','failed');

alter table public.notifications enable row level security;

create policy "Users view their own notifications"
on public.notifications for select to authenticated
using (recipient_user_id = (select auth.uid()));

create policy "Users mark their own notifications as read"
on public.notifications for update to authenticated
using (recipient_user_id = (select auth.uid()))
with check (
  recipient_user_id = (select auth.uid())
  and status = 'read'
  and read_at is not null
);

revoke all on public.notifications from anon,authenticated;
grant select on public.notifications to authenticated;
grant update(status,read_at,updated_at) on public.notifications to authenticated;
grant all on public.notifications to service_role;

create table public.notification_delivery_attempts (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  notification_id uuid not null,
  attempt_number integer not null check (attempt_number > 0),
  provider text,
  provider_message_id text,
  status text not null check (status in ('started','sent','failed')),
  response_code text,
  error_summary text,
  attempted_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (business_id,notification_id,attempt_number),
  foreign key (business_id,notification_id)
    references public.notifications(business_id,id) on delete restrict
);

create index notification_attempts_notification_idx
  on public.notification_delivery_attempts(business_id,notification_id,attempt_number desc);

alter table public.notification_delivery_attempts enable row level security;
revoke all on public.notification_delivery_attempts from anon,authenticated;
grant all on public.notification_delivery_attempts to service_role;

-- Notification records and delivery attempts are created/updated only by trusted server-side code.
-- Do not expose provider credentials or call WhatsApp/email providers from browser clients.
