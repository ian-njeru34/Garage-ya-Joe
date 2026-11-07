-- Protect dealer/customer pricing boundaries and record task-level accountability.
alter table public.spare_requests
  add column if not exists owner_markup_percent numeric(8,2) not null default 0 check (owner_markup_percent >= 0),
  add column if not exists owner_markup_fixed_kes numeric(18,2) not null default 0 check (owner_markup_fixed_kes >= 0),
  add column if not exists customer_unit_price_kes numeric(18,2),
  add column if not exists customer_shipping_kes numeric(18,2),
  add column if not exists customer_total_kes numeric(18,2),
  add column if not exists customer_quote_published_at timestamptz,
  add column if not exists owner_price_updated_by uuid references public.profiles(id) on delete set null;

alter table public.spare_request_responses
  add column if not exists estimated_shipping_kes numeric(18,2) not null default 0 check (estimated_shipping_kes >= 0),
  add column if not exists updated_at timestamptz not null default now();

-- Dealer responses contain wholesale/supplier prices. Customers must never read this table.
drop policy if exists "Customers view responses to their own requests" on public.spare_request_responses;
drop policy if exists "Assigned dealers view their requests" on public.spare_requests;

-- Dealers receive only a filtered payload through the authenticated Edge Function.
-- Their direct table SELECT policy is intentionally removed to protect customer identity/contact details.

create table if not exists public.job_task_activity (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  job_card_id uuid not null,
  job_task_id uuid not null,
  actor_id uuid references public.profiles(id) on delete set null,
  assigned_to uuid references public.profiles(id) on delete set null,
  event_type text not null check (event_type in ('created','assigned','started','completed','status_changed')),
  previous_status text,
  new_status text,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  foreign key (business_id,job_card_id) references public.job_cards(business_id,id) on delete cascade,
  foreign key (business_id,job_task_id) references public.job_tasks(business_id,id) on delete cascade
);
create index if not exists job_task_activity_task_time_idx
  on public.job_task_activity(business_id,job_task_id,occurred_at desc);
create index if not exists job_task_activity_job_time_idx
  on public.job_task_activity(business_id,job_card_id,occurred_at desc);

alter table public.job_task_activity enable row level security;
drop policy if exists "Garage managers view task activity" on public.job_task_activity;
create policy "Garage managers view task activity"
  on public.job_task_activity for select to authenticated
  using (private.has_business_permission(business_id,'garage.view',location_id));
drop policy if exists "Assigned mechanics view own task activity" on public.job_task_activity;
create policy "Assigned mechanics view own task activity"
  on public.job_task_activity for select to authenticated
  using (assigned_to=(select auth.uid()) or actor_id=(select auth.uid()));
revoke all on public.job_task_activity from anon,authenticated;
grant select on public.job_task_activity to authenticated;
grant all on public.job_task_activity to service_role;

create or replace function private.capture_job_task_activity()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_actor uuid;
begin
  if tg_op='INSERT' then
    v_actor := coalesce((select auth.uid()),new.created_by);
    insert into public.job_task_activity(
      business_id,location_id,job_card_id,job_task_id,actor_id,assigned_to,event_type,new_status,details
    ) values (
      new.business_id,new.location_id,new.job_card_id,new.id,v_actor,new.assigned_to,'created',new.status,
      jsonb_build_object('task_title',new.task_title)
    );
    if new.assigned_to is not null then
      insert into public.job_task_activity(
        business_id,location_id,job_card_id,job_task_id,actor_id,assigned_to,event_type,new_status
      ) values (
        new.business_id,new.location_id,new.job_card_id,new.id,v_actor,new.assigned_to,'assigned',new.status
      );
    end if;
    return new;
  end if;

  v_actor := coalesce((select auth.uid()),new.assigned_to,new.created_by);
  if old.assigned_to is distinct from new.assigned_to then
    insert into public.job_task_activity(
      business_id,location_id,job_card_id,job_task_id,actor_id,assigned_to,event_type,previous_status,new_status,details
    ) values (
      new.business_id,new.location_id,new.job_card_id,new.id,v_actor,new.assigned_to,'assigned',old.status,new.status,
      jsonb_build_object('previous_assignee',old.assigned_to,'new_assignee',new.assigned_to)
    );
  end if;
  if old.status is distinct from new.status then
    insert into public.job_task_activity(
      business_id,location_id,job_card_id,job_task_id,actor_id,assigned_to,event_type,previous_status,new_status
    ) values (
      new.business_id,new.location_id,new.job_card_id,new.id,v_actor,new.assigned_to,
      case when new.status='started' then 'started'
           when new.status='in_progress' then 'started'
           when new.status='completed' then 'completed'
           else 'status_changed' end,
      old.status,new.status
    );
  end if;
  return new;
end;
$$;

drop trigger if exists capture_job_task_activity on public.job_tasks;
create trigger capture_job_task_activity
after insert or update of assigned_to,status on public.job_tasks
for each row execute function private.capture_job_task_activity();

-- Publish only the owner-approved customer price through the existing customer snapshot.
