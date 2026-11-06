-- Garage ya Joe: customer vehicles and ownership history.
-- Customer master records remain business-scoped. Vehicles are shared across garage and spares workflows.

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  registration_number text not null,
  registration_normalized text generated always as (
    upper(regexp_replace(registration_number, '[^A-Za-z0-9]', '', 'g'))
  ) stored,
  make text not null,
  model text not null,
  model_variant text,
  manufacture_year smallint,
  body_type text,
  fuel_type text,
  transmission text,
  engine_capacity_cc integer,
  engine_number text,
  vin_chassis_number text,
  colour text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicles_year_check check (
    manufacture_year is null or manufacture_year between 1900 and 2100
  ),
  constraint vehicles_engine_capacity_check check (
    engine_capacity_cc is null or engine_capacity_cc > 0
  ),
  constraint vehicles_registration_not_blank check (length(trim(registration_number)) > 0),
  constraint vehicles_make_not_blank check (length(trim(make)) > 0),
  constraint vehicles_model_not_blank check (length(trim(model)) > 0),
  unique (business_id, id),
  unique (business_id, registration_normalized)
);

create unique index vehicles_business_vin_unique_idx
  on public.vehicles (business_id, upper(regexp_replace(vin_chassis_number, '[^A-Za-z0-9]', '', 'g')))
  where vin_chassis_number is not null and length(trim(vin_chassis_number)) > 0;

create index vehicles_business_make_model_idx
  on public.vehicles (business_id, make, model);
create index vehicles_business_engine_number_idx
  on public.vehicles (business_id, engine_number)
  where engine_number is not null;

-- One vehicle may have a current owner and additional authorized drivers/fleet contacts.
-- Ownership history is retained by closing a relationship with ended_at rather than deleting it.
alter table public.customers
  add constraint customers_business_id_id_unique unique (business_id, id);

create table public.vehicle_customer_relationships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  vehicle_id uuid not null,
  customer_id uuid not null,
  relationship_type text not null default 'owner'
    check (relationship_type in ('owner', 'driver', 'fleet_manager', 'authorized_contact')),
  started_at date not null default current_date,
  ended_at date,
  notes text,
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint vehicle_relationship_dates_check check (ended_at is null or ended_at >= started_at),
  constraint vehicle_relationship_vehicle_fk
    foreign key (business_id, vehicle_id)
    references public.vehicles (business_id, id) on delete restrict,
  constraint vehicle_relationship_customer_fk
    foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete restrict
);

create unique index vehicle_one_current_owner_idx
  on public.vehicle_customer_relationships (vehicle_id)
  where relationship_type = 'owner' and ended_at is null;

create unique index vehicle_customer_relationship_no_duplicate_active_idx
  on public.vehicle_customer_relationships (vehicle_id, customer_id, relationship_type)
  where ended_at is null;

create index vehicle_relationship_customer_idx
  on public.vehicle_customer_relationships (business_id, customer_id, started_at desc);
create index vehicle_relationship_vehicle_idx
  on public.vehicle_customer_relationships (business_id, vehicle_id, started_at desc);

-- All exposed tables retain RLS. Access is based on database-assigned permissions
-- or a verified customer profile link; user-editable metadata is not trusted.
alter table public.customers enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_customer_relationships enable row level security;

-- Customers: staff with permission can view/manage; customers can view and update only their own contact details.
create policy "Staff can view business customers"
  on public.customers for select to authenticated
  using (
    private.has_business_permission(business_id, 'customers.view')
    or profile_id = (select auth.uid())
  );

create policy "Authorized staff can create customers"
  on public.customers for insert to authenticated
  with check (private.has_business_permission(business_id, 'customers.manage'));

create policy "Authorized staff or customer can update customer contact"
  on public.customers for update to authenticated
  using (
    private.has_business_permission(business_id, 'customers.manage')
    or profile_id = (select auth.uid())
  )
  with check (
    private.has_business_permission(business_id, 'customers.manage')
    or profile_id = (select auth.uid())
  );

create policy "Authorized staff can delete customers"
  on public.customers for delete to authenticated
  using (private.has_business_permission(business_id, 'customers.manage'));

-- Vehicles: customers may see vehicles linked to their own customer profile.
create policy "Staff or linked customers can view vehicles"
  on public.vehicles for select to authenticated
  using (
    private.has_business_permission(business_id, 'vehicles.view')
    or exists (
      select 1
      from public.vehicle_customer_relationships vcr
      join public.customers c
        on c.id = vcr.customer_id and c.business_id = vcr.business_id
      where vcr.vehicle_id = vehicles.id
        and c.profile_id = (select auth.uid())
    )
  );

create policy "Authorized staff can create vehicles"
  on public.vehicles for insert to authenticated
  with check (private.has_business_permission(business_id, 'vehicles.manage'));

create policy "Authorized staff can update vehicles"
  on public.vehicles for update to authenticated
  using (private.has_business_permission(business_id, 'vehicles.manage'))
  with check (private.has_business_permission(business_id, 'vehicles.manage'));

create policy "Authorized staff can delete unlinked vehicles"
  on public.vehicles for delete to authenticated
  using (
    private.has_business_permission(business_id, 'vehicles.manage')
    and not exists (
      select 1 from public.vehicle_customer_relationships vcr
      where vcr.vehicle_id = vehicles.id
    )
  );

-- Ownership/driver links: visible to permitted staff and the linked customer.
create policy "Staff or linked customers can view vehicle relationships"
  on public.vehicle_customer_relationships for select to authenticated
  using (
    private.has_business_permission(business_id, 'vehicles.view')
    or exists (
      select 1 from public.customers c
      where c.id = vehicle_customer_relationships.customer_id
        and c.business_id = vehicle_customer_relationships.business_id
        and c.profile_id = (select auth.uid())
    )
  );

create policy "Authorized staff can create vehicle relationships"
  on public.vehicle_customer_relationships for insert to authenticated
  with check (private.has_business_permission(business_id, 'vehicles.manage'));

create policy "Authorized staff can update vehicle relationships"
  on public.vehicle_customer_relationships for update to authenticated
  using (private.has_business_permission(business_id, 'vehicles.manage'))
  with check (private.has_business_permission(business_id, 'vehicles.manage'));

-- Preserve relationship history: do not allow browser-side deletion.
revoke all on public.vehicle_customer_relationships from anon, authenticated;
grant select, insert, update on public.vehicle_customer_relationships to authenticated;

revoke all on public.vehicles from anon, authenticated;
grant select, insert, update, delete on public.vehicles to authenticated;

-- Customer-facing users may update only contact fields. Staff insert/update/delete via
-- explicit policies and column grants; privileged server workflows handle sensitive fields.
revoke all on public.customers from anon, authenticated;
grant select, insert, delete on public.customers to authenticated;
grant update (display_name, email, phone) on public.customers to authenticated;
