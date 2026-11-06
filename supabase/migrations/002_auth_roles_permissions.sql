-- Garage ya Joe: authentication roles and permissions
-- Authorization is stored in database tables, never in user-editable auth metadata.
-- Role assignments are provisioned only by trusted server-side operations (service role).

create table public.role_definitions (
  code text primary key,
  name text not null,
  description text not null,
  is_system_role boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.permission_definitions (
  code text primary key,
  description text not null
);

create table public.role_permissions (
  role_code text not null references public.role_definitions(code) on delete cascade,
  permission_code text not null references public.permission_definitions(code) on delete cascade,
  primary key (role_code, permission_code)
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid references public.locations(id) on delete cascade,
  role_code text not null references public.role_definitions(code),
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  unique (user_id, business_id, location_id, role_code)
);

create index user_roles_user_business_idx
  on public.user_roles (user_id, business_id);
create index user_roles_business_location_idx
  on public.user_roles (business_id, location_id);

insert into public.role_definitions (code, name, description) values
  ('owner', 'Owner', 'Full business authority, including business-wide configuration and access administration.'),
  ('administrator', 'Administrator', 'Manages business operations, staff access and configuration.'),
  ('branch_manager', 'Branch Manager', 'Manages daily operations within assigned branch locations.'),
  ('service_advisor', 'Service Advisor', 'Manages customer reception, inspections, job cards, quotations and service bookings.'),
  ('mechanic', 'Mechanic', 'Works on assigned jobs and records inspection and repair progress.'),
  ('inventory_manager', 'Inventory Manager', 'Manages stock, warehouses, receipts, transfers and stock counts.'),
  ('procurement_officer', 'Procurement Officer', 'Manages suppliers, purchase orders and imported-part sourcing.'),
  ('cashier', 'Cashier', 'Processes approved sales, invoices and customer payments.'),
  ('accountant', 'Accountant', 'Manages financial records, reconciliation and reporting.'),
  ('customer', 'Customer', 'Uses customer-facing account features and views their own records.');

insert into public.permission_definitions (code, description) values
  ('business.manage', 'Manage business settings and business-wide configuration.'),
  ('staff.manage', 'Create, update and deactivate staff access and role assignments.'),
  ('locations.manage', 'Manage branches, garages and locations.'),
  ('customers.view', 'View customer records.'),
  ('customers.manage', 'Create and update customer records.'),
  ('vehicles.view', 'View customer vehicles and service history.'),
  ('vehicles.manage', 'Create and update customer vehicle records.'),
  ('garage.view', 'View garage bookings and job cards.'),
  ('garage.manage', 'Manage bookings, inspections, job cards and service workflow.'),
  ('garage.perform_work', 'Update assigned repair tasks and work progress.'),
  ('quotations.view', 'View quotations.'),
  ('quotations.manage', 'Prepare and update quotations.'),
  ('quotations.approve', 'Approve quotations and work authorizations.'),
  ('catalogue.view', 'View the spare-parts and services catalogue.'),
  ('catalogue.manage', 'Create and update catalogue products.'),
  ('inventory.view', 'View stock quantities and movements.'),
  ('inventory.manage', 'Receive, reserve, transfer and adjust inventory.'),
  ('procurement.manage', 'Manage suppliers, purchasing and importation.'),
  ('sales.view', 'View sales and invoices.'),
  ('sales.manage', 'Create and manage sales and invoices.'),
  ('payments.record', 'Record and reconcile customer payments.'),
  ('finance.view', 'View financial records and reports.'),
  ('finance.manage', 'Manage accounting entries and financial controls.'),
  ('reports.view', 'View operational and financial reports.'),
  ('customer_portal.view_own', 'View the signed-in customer own account, vehicles and service records.');

-- Owner receives every defined permission. Other roles receive only their operational permissions.
insert into public.role_permissions (role_code, permission_code)
select 'owner', code from public.permission_definitions;

insert into public.role_permissions (role_code, permission_code) values
  ('administrator', 'staff.manage'),
  ('administrator', 'locations.manage'),
  ('administrator', 'customers.view'),
  ('administrator', 'customers.manage'),
  ('administrator', 'vehicles.view'),
  ('administrator', 'vehicles.manage'),
  ('administrator', 'garage.view'),
  ('administrator', 'garage.manage'),
  ('administrator', 'quotations.view'),
  ('administrator', 'quotations.manage'),
  ('administrator', 'quotations.approve'),
  ('administrator', 'catalogue.view'),
  ('administrator', 'catalogue.manage'),
  ('administrator', 'inventory.view'),
  ('administrator', 'inventory.manage'),
  ('administrator', 'procurement.manage'),
  ('administrator', 'sales.view'),
  ('administrator', 'sales.manage'),
  ('administrator', 'payments.record'),
  ('administrator', 'finance.view'),
  ('administrator', 'finance.manage'),
  ('administrator', 'reports.view'),
  ('branch_manager', 'customers.view'),
  ('branch_manager', 'customers.manage'),
  ('branch_manager', 'vehicles.view'),
  ('branch_manager', 'vehicles.manage'),
  ('branch_manager', 'garage.view'),
  ('branch_manager', 'garage.manage'),
  ('branch_manager', 'quotations.view'),
  ('branch_manager', 'quotations.manage'),
  ('branch_manager', 'quotations.approve'),
  ('branch_manager', 'catalogue.view'),
  ('branch_manager', 'inventory.view'),
  ('branch_manager', 'sales.view'),
  ('branch_manager', 'sales.manage'),
  ('branch_manager', 'payments.record'),
  ('branch_manager', 'reports.view'),
  ('service_advisor', 'customers.view'),
  ('service_advisor', 'customers.manage'),
  ('service_advisor', 'vehicles.view'),
  ('service_advisor', 'vehicles.manage'),
  ('service_advisor', 'garage.view'),
  ('service_advisor', 'garage.manage'),
  ('service_advisor', 'quotations.view'),
  ('service_advisor', 'quotations.manage'),
  ('service_advisor', 'catalogue.view'),
  ('service_advisor', 'inventory.view'),
  ('mechanic', 'vehicles.view'),
  ('mechanic', 'garage.view'),
  ('mechanic', 'garage.perform_work'),
  ('mechanic', 'catalogue.view'),
  ('mechanic', 'inventory.view'),
  ('inventory_manager', 'catalogue.view'),
  ('inventory_manager', 'catalogue.manage'),
  ('inventory_manager', 'inventory.view'),
  ('inventory_manager', 'inventory.manage'),
  ('inventory_manager', 'procurement.manage'),
  ('inventory_manager', 'reports.view'),
  ('procurement_officer', 'catalogue.view'),
  ('procurement_officer', 'inventory.view'),
  ('procurement_officer', 'procurement.manage'),
  ('cashier', 'customers.view'),
  ('cashier', 'sales.view'),
  ('cashier', 'sales.manage'),
  ('cashier', 'payments.record'),
  ('accountant', 'customers.view'),
  ('accountant', 'sales.view'),
  ('accountant', 'payments.record'),
  ('accountant', 'finance.view'),
  ('accountant', 'finance.manage'),
  ('accountant', 'reports.view'),
  ('customer', 'customer_portal.view_own');

-- Private helper functions avoid recursive RLS checks on role-assignment tables.
create schema if not exists private;

create or replace function private.has_business_permission(
  p_business_id uuid,
  p_permission_code text,
  p_location_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_code = ur.role_code
    where ur.user_id = (select auth.uid())
      and ur.business_id = p_business_id
      and rp.permission_code = p_permission_code
      and (ur.location_id is null or ur.location_id = p_location_id)
  );
$$;

revoke all on function private.has_business_permission(uuid, text, uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.has_business_permission(uuid, text, uuid) to authenticated;

-- Only a signed-in user can read their own profile and role assignments.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_definitions enable row level security;
alter table public.permission_definitions enable row level security;
alter table public.role_permissions enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Users can update their own contact profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "Users can view their own role assignments"
  on public.user_roles for select to authenticated
  using ((select auth.uid()) = user_id);

-- Role catalog and permission matrix are intentionally server-side only.
revoke all on public.role_definitions, public.permission_definitions, public.role_permissions
  from anon, authenticated;
revoke all on public.user_roles from anon, authenticated;
grant select on public.user_roles to authenticated;
revoke all on public.profiles from anon, authenticated;
grant select, update on public.profiles to authenticated;

-- Trusted server-side administration provisions roles; browser clients cannot assign roles.
grant all on public.role_definitions, public.permission_definitions, public.role_permissions, public.user_roles
  to service_role;
