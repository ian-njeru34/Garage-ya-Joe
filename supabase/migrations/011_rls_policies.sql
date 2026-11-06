-- Garage ya Joe: least-privilege policies for business context and currency reference data.
-- Role/permission catalogs and notification delivery attempts remain server-only by design.

-- Business records are visible only to authenticated users with an assignment in that business.
drop policy if exists "Assigned staff can view their business" on public.businesses;
create policy "Assigned staff can view their business"
on public.businesses for select to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.business_id = businesses.id
  )
);

-- Location visibility follows the permissions of the user's assignment at that location.
drop policy if exists "Authorized staff can view assigned locations" on public.locations;
create policy "Authorized staff can view assigned locations"
on public.locations for select to authenticated
using (
  private.has_business_permission(business_id,'garage.view',id)
  or private.has_business_permission(business_id,'customers.view',id)
  or private.has_business_permission(business_id,'inventory.view',id)
  or private.has_business_permission(business_id,'procurement.manage',id)
  or private.has_business_permission(business_id,'sales.view',id)
  or private.has_business_permission(business_id,'finance.view',id)
  or private.has_business_permission(business_id,'reports.view',id)
);

-- Currency codes are reference data and may be read publicly; clients cannot modify them.
drop policy if exists "Anyone can read currency reference data" on public.currencies;
create policy "Anyone can read currency reference data"
on public.currencies for select to anon, authenticated
using (true);

-- Explicit least-privilege table grants. Server-side service_role retains administration.
revoke all on public.businesses, public.locations from anon, authenticated;
grant select on public.businesses, public.locations to authenticated;
grant all on public.businesses, public.locations to service_role;

revoke all on public.currencies from anon, authenticated;
grant select on public.currencies to anon, authenticated;
grant all on public.currencies to service_role;

-- These are authorization internals. Keep them unavailable through the browser Data API.
alter table public.role_definitions enable row level security;
alter table public.permission_definitions enable row level security;
alter table public.role_permissions enable row level security;
revoke all on public.role_definitions, public.permission_definitions, public.role_permissions
  from anon, authenticated;
grant all on public.role_definitions, public.permission_definitions, public.role_permissions
  to service_role;

-- Delivery attempts can contain provider references and failure details; worker-only.
alter table public.notification_delivery_attempts enable row level security;
revoke all on public.notification_delivery_attempts from anon, authenticated;
grant all on public.notification_delivery_attempts to service_role;

-- Keep role assignment provisioning server-side. Users can read only their own assignments
-- through the pre-existing policy, but cannot grant themselves roles.
revoke all on public.user_roles from anon, authenticated;
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
