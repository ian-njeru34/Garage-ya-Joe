-- Customer-facing service updates published by workshop staff.
create table if not exists public.customer_job_updates (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_card_id uuid not null,
  customer_id uuid not null,
  message text not null check (length(trim(message)) between 1 and 3000),
  published_by uuid not null references public.profiles(id) on delete restrict,
  whatsapp_status text not null default 'pending'
    check (whatsapp_status in ('pending','sent','failed','not_configured')),
  whatsapp_message_id text,
  whatsapp_error text,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,job_card_id) references public.job_cards(business_id,id) on delete cascade,
  foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict
);
create index if not exists customer_job_updates_customer_time_idx
  on public.customer_job_updates(business_id,customer_id,created_at desc);
create index if not exists customer_job_updates_job_time_idx
  on public.customer_job_updates(business_id,job_card_id,created_at desc);

alter table public.customer_job_updates enable row level security;
drop policy if exists "Customers read their published job updates" on public.customer_job_updates;
create policy "Customers read their published job updates"
  on public.customer_job_updates for select to authenticated
  using (exists (
    select 1 from public.customers c
    where c.id=customer_job_updates.customer_id
      and c.business_id=customer_job_updates.business_id
      and c.profile_id=(select auth.uid())
  ));
drop policy if exists "Workshop staff read job updates" on public.customer_job_updates;
create policy "Workshop staff read job updates"
  on public.customer_job_updates for select to authenticated
  using (exists (
    select 1 from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.business_id=customer_job_updates.business_id
      and (ur.location_id is null or ur.location_id=customer_job_updates.location_id)
      and ur.role_code in ('owner','administrator','branch_manager','service_advisor','mechanic')
  ));
drop policy if exists "Workshop staff publish customer job updates" on public.customer_job_updates;
create policy "Workshop staff publish customer job updates"
  on public.customer_job_updates for insert to authenticated
  with check (
    published_by=(select auth.uid())
    and exists (
      select 1 from public.job_cards j
      where j.id=customer_job_updates.job_card_id
        and j.business_id=customer_job_updates.business_id
        and j.location_id=customer_job_updates.location_id
        and j.customer_id=customer_job_updates.customer_id
    )
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id=(select auth.uid())
        and ur.business_id=customer_job_updates.business_id
        and (ur.location_id is null or ur.location_id=customer_job_updates.location_id)
        and ur.role_code in ('owner','administrator','branch_manager','service_advisor','mechanic')
    )
  );

revoke all on public.customer_job_updates from anon, authenticated;
grant select, insert on public.customer_job_updates to authenticated;
grant all on public.customer_job_updates to service_role;
