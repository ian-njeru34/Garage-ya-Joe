-- The Garage: mechanic inspection capability and owner staff directory visibility.
insert into public.permission_definitions(code,description)
values('garage.inspect','Inspect assigned vehicles and submit repair findings/recommendations.')
on conflict(code) do nothing;
insert into public.role_permissions(role_code,permission_code)
values('mechanic','garage.inspect')
on conflict do nothing;

drop policy if exists "Garage staff can create inspections" on public.vehicle_inspections;
create policy "Garage staff or assigned mechanics can create inspections"
on public.vehicle_inspections for insert to authenticated
with check (
 private.has_business_permission(business_id,'garage.manage',location_id)
 or (
   inspected_by=(select auth.uid())
   and private.has_business_permission(business_id,'garage.inspect',location_id)
   and exists(
     select 1 from public.service_appointments a
     join public.job_cards j on j.business_id=a.business_id and j.appointment_id=a.id
     join public.job_tasks t on t.business_id=j.business_id and t.job_card_id=j.id
     where a.business_id=vehicle_inspections.business_id
       and a.id=vehicle_inspections.appointment_id
       and t.assigned_to=(select auth.uid())
   )
 )
);

drop policy if exists "Garage staff can view inspections" on public.vehicle_inspections;
create policy "Garage staff or assigned mechanics can view inspections"
on public.vehicle_inspections for select to authenticated
using (
 private.has_business_permission(business_id,'garage.view',location_id)
 or exists(
   select 1 from public.service_appointments a
   join public.job_cards j on j.business_id=a.business_id and j.appointment_id=a.id
   join public.job_tasks t on t.business_id=j.business_id and t.job_card_id=j.id
   where a.business_id=vehicle_inspections.business_id
     and a.id=vehicle_inspections.appointment_id
     and t.assigned_to=(select auth.uid())
 )
);

create policy "Owners can view staff profiles"
on public.profiles for select to authenticated
using(private.has_business_permission((select ur.business_id from public.user_roles ur where ur.user_id=(select auth.uid()) and ur.role_code='owner' limit 1),'staff.manage'));
