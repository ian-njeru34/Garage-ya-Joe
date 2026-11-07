-- Owner-only directory access for staff administration screens.
create policy "Owners can view business staff assignments"
on public.user_roles for select to authenticated
using(private.has_business_permission(business_id,'staff.manage'));
