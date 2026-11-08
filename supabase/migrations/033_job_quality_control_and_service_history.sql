-- Immutable quality-control sign-off and atomic workshop job completion.
create table if not exists public.job_quality_checks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_card_id uuid not null,
  checked_by uuid references public.profiles(id) on delete set null,
  checklist jsonb not null,
  notes text,
  passed boolean not null default false,
  checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,job_card_id) references public.job_cards(business_id,id) on delete restrict
);
create index if not exists job_quality_checks_job_idx
  on public.job_quality_checks(business_id,job_card_id,checked_at desc);
alter table public.job_quality_checks enable row level security;
drop policy if exists "Garage staff can view quality checks" on public.job_quality_checks;
create policy "Garage staff can view quality checks"
  on public.job_quality_checks for select to authenticated
  using (private.has_business_permission(business_id,'garage.view',location_id));
drop policy if exists "Garage managers can record quality checks" on public.job_quality_checks;
create policy "Garage managers can record quality checks"
  on public.job_quality_checks for insert to authenticated
  with check (checked_by=(select auth.uid()) and private.has_business_permission(business_id,'garage.manage',location_id));
revoke all on public.job_quality_checks from anon,authenticated;
grant select,insert on public.job_quality_checks to authenticated;

create or replace function public.complete_job_after_quality_check(
  p_job_card_id uuid,
  p_checklist jsonb,
  p_notes text default null,
  p_next_service_due_date date default null,
  p_next_service_due_odometer_km integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_business uuid;
  v_location uuid;
  v_customer uuid;
  v_vehicle uuid;
  v_job_status text;
  v_work_summary text;
  v_odometer integer;
  v_quality_id uuid;
  v_summary text;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_checklist is null or jsonb_typeof(p_checklist)<>'object'
     or p_checklist->>'road_test' is distinct from 'true'
     or p_checklist->>'leak_check' is distinct from 'true'
     or p_checklist->>'safety_check' is distinct from 'true'
     or p_checklist->>'tools_removed' is distinct from 'true'
     or p_checklist->>'customer_items_returned' is distinct from 'true' then
    raise exception 'Complete every quality-control check before closing the job';
  end if;
  if p_next_service_due_odometer_km is not null and p_next_service_due_odometer_km<0 then
    raise exception 'Next service odometer must be zero or greater';
  end if;

  select business_id,location_id,customer_id,vehicle_id,status,work_summary,odometer_out_km
    into v_business,v_location,v_customer,v_vehicle,v_job_status,v_work_summary,v_odometer
  from public.job_cards where id=p_job_card_id for update;
  if not found then raise exception 'Job card not found'; end if;
  if v_job_status<>'quality_check' then raise exception 'Only jobs awaiting quality check can be completed'; end if;
  if not private.has_business_permission(v_business,'garage.manage',v_location) then
    raise exception 'Not authorized to approve workshop completion' using errcode='42501';
  end if;
  if exists(select 1 from public.job_tasks where job_card_id=p_job_card_id and business_id=v_business and status not in ('completed','cancelled')) then
    raise exception 'Complete or cancel all workshop tasks before closing the job';
  end if;
  if exists(select 1 from public.job_parts where job_card_id=p_job_card_id and business_id=v_business and fulfillment_status not in ('fulfilled','cancelled')) then
    raise exception 'Resolve every parts request before closing the job';
  end if;

  v_summary := coalesce(nullif(trim(v_work_summary),''),'Vehicle service completed');
  insert into public.job_quality_checks(business_id,location_id,job_card_id,checked_by,checklist,notes,passed)
  values(v_business,v_location,p_job_card_id,v_uid,p_checklist,nullif(trim(p_notes),''),true)
  returning id into v_quality_id;

  insert into public.service_history(
    business_id,location_id,customer_id,vehicle_id,job_card_id,service_date,
    odometer_km,customer_summary,next_service_due_date,next_service_due_odometer_km,created_by
  ) values(
    v_business,v_location,v_customer,v_vehicle,p_job_card_id,current_date,
    v_odometer,v_summary,p_next_service_due_date,p_next_service_due_odometer_km,v_uid
  )
  on conflict(business_id,job_card_id) do nothing;

  update public.job_cards set status='completed',completed_at=now(),updated_at=now()
  where id=p_job_card_id and business_id=v_business;
  return v_quality_id;
end;
$$;
revoke all on function public.complete_job_after_quality_check(uuid,jsonb,text,date,integer) from public,anon;
grant execute on function public.complete_job_after_quality_check(uuid,jsonb,text,date,integer) to authenticated;
