-- Capture the workshop's configured labour cost rate on new work-log entries.
-- Historical work logs remain unrated rather than receiving an invented rate.
alter table public.businesses
  add column if not exists default_labour_cost_per_hour_kes numeric(18,2) not null default 0
  check (default_labour_cost_per_hour_kes >= 0);

alter table public.job_work_logs
  add column if not exists labour_rate_kes_per_hour numeric(18,2)
  check (labour_rate_kes_per_hour is null or labour_rate_kes_per_hour >= 0);

create or replace function private.capture_job_work_log_labour_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.labour_rate_kes_per_hour is null then
    select b.default_labour_cost_per_hour_kes
      into new.labour_rate_kes_per_hour
    from public.businesses b
    where b.id = new.business_id;
  end if;
  return new;
end;
$$;

drop trigger if exists job_work_logs_capture_labour_rate on public.job_work_logs;
create trigger job_work_logs_capture_labour_rate
before insert on public.job_work_logs
for each row execute function private.capture_job_work_log_labour_rate();

create or replace function public.owner_update_labour_cost_rate(
  p_business_id uuid,
  p_rate_kes_per_hour numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_rate_kes_per_hour is null or p_rate_kes_per_hour < 0 or p_rate_kes_per_hour > 1000000 then
    raise exception 'Enter a valid hourly labour cost rate between KSh 0 and KSh 1,000,000';
  end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.business_id = p_business_id
      and ur.role_code = 'owner'
  ) then
    raise exception 'Only the business owner can change the default labour cost rate' using errcode = '42501';
  end if;
  update public.businesses
  set default_labour_cost_per_hour_kes = p_rate_kes_per_hour,
      updated_at = now()
  where id = p_business_id;
  if not found then raise exception 'Business not found'; end if;
end;
$$;

revoke all on function public.owner_update_labour_cost_rate(uuid,numeric) from public, anon;
grant execute on function public.owner_update_labour_cost_rate(uuid,numeric) to authenticated;
