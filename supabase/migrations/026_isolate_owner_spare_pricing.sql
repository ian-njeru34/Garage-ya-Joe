-- Move owner-only markup and published price data out of the customer-readable
-- spare_requests table. RLS is row-based, so confidential price columns need their
-- own owner-restricted table.
create table if not exists public.owner_spare_pricing (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  spare_request_id uuid not null,
  markup_percent numeric(8,2) not null default 0 check(markup_percent>=0),
  markup_fixed_kes numeric(18,2) not null default 0 check(markup_fixed_kes>=0),
  customer_unit_price_kes numeric(18,2) not null check(customer_unit_price_kes>=0),
  customer_shipping_kes numeric(18,2) not null default 0 check(customer_shipping_kes>=0),
  customer_total_kes numeric(18,2) not null check(customer_total_kes>=0),
  published_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id,spare_request_id)
    references public.spare_requests(business_id,id) on delete cascade,
  unique(business_id,spare_request_id)
);
alter table public.owner_spare_pricing enable row level security;
drop policy if exists "Owners manage published spare pricing" on public.owner_spare_pricing;
create policy "Owners manage published spare pricing"
  on public.owner_spare_pricing for all to authenticated
  using(private.has_business_permission(business_id,'staff.manage'))
  with check(private.has_business_permission(business_id,'staff.manage'));
revoke all on public.owner_spare_pricing from public,anon,authenticated;
grant select,insert,update on public.owner_spare_pricing to authenticated;
grant all on public.owner_spare_pricing to service_role;
create index if not exists owner_spare_pricing_request_idx
  on public.owner_spare_pricing(business_id,spare_request_id);

-- No customer-readable base table should contain dealer-derived or owner markup values.
alter table public.spare_requests
  drop column if exists owner_markup_percent,
  drop column if exists owner_markup_fixed_kes,
  drop column if exists customer_unit_price_kes,
  drop column if exists customer_shipping_kes,
  drop column if exists customer_total_kes,
  drop column if exists customer_quote_published_at,
  drop column if exists owner_price_updated_by;

create or replace function public.customer_published_spare_quotes()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_customer public.customers%rowtype; v_result jsonb;
begin
  select * into v_customer
  from public.customers
  where profile_id=(select auth.uid())
  order by created_at asc
  limit 1;
  if not found then
    raise exception 'Customer profile not found' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'part_name',r.part_name,
    'part_number',r.part_number,
    'quantity',r.quantity,
    'status',r.status,
    'unit_price_kes',p.customer_unit_price_kes,
    'shipping_kes',p.customer_shipping_kes,
    'total_kes',p.customer_total_kes,
    'published_at',p.published_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_result
  from public.spare_requests r
  join public.owner_spare_pricing p
    on p.business_id=r.business_id and p.spare_request_id=r.id
  where r.business_id=v_customer.business_id
    and r.customer_id=v_customer.id;
  return v_result;
end;
$$;
revoke all on function public.customer_published_spare_quotes() from public,anon;
grant execute on function public.customer_published_spare_quotes() to authenticated;
