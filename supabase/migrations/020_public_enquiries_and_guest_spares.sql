-- Guest enquiries and spare requests. Public submissions are written by a single
-- validated server route; no anonymous database write privileges are granted.
alter table public.spare_requests
 alter column customer_id drop not null,
 alter column created_by drop not null;
alter table public.spare_requests
 add column if not exists customer_name text,
 add column if not exists customer_email text;

create table if not exists public.customer_enquiries (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete restrict,
 customer_id uuid references public.customers(id) on delete set null,
 full_name text not null,
 email text,
 whatsapp text not null,
 vehicle_details text,
 enquiry_type text not null,
 details text,
 status text not null default 'new' check(status in ('new','contacted','quoted','converted','closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(length(trim(full_name))>0),
 check(length(trim(whatsapp))>0),
 check(length(trim(enquiry_type))>0),
 unique(business_id,id)
);
create index if not exists customer_enquiries_business_status_idx
 on public.customer_enquiries(business_id,status,created_at desc);
alter table public.customer_enquiries enable row level security;
create policy "Owners can view and manage customer enquiries"
 on public.customer_enquiries for all to authenticated
 using(private.has_business_permission(business_id,'staff.manage'))
 with check(private.has_business_permission(business_id,'staff.manage'));
revoke all on public.customer_enquiries from anon,authenticated;
grant select,update on public.customer_enquiries to authenticated;
grant all on public.customer_enquiries to service_role;
