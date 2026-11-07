-- Dealer wholesale prices and owner markups are restricted to the owner role,
-- not general administrators or other staff with staff.manage permission.
drop policy if exists "Owners manage published spare pricing" on public.owner_spare_pricing;
create policy "Owners manage published spare pricing"
  on public.owner_spare_pricing for all to authenticated
  using (exists(
    select 1 from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.business_id=owner_spare_pricing.business_id
      and ur.role_code='owner'
  ))
  with check (exists(
    select 1 from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.business_id=owner_spare_pricing.business_id
      and ur.role_code='owner'
  ));
