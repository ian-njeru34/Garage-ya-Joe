-- Enforce the customer approval gate before assigned mechanics can perform work.
create or replace function private.sync_job_card_after_customer_approval()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
 if new.status='accepted' and old.status is distinct from new.status and new.job_card_id is not null then
   update public.job_cards
   set status='approved',approved_at=coalesce(approved_at,now()),updated_at=now()
   where id=new.job_card_id and business_id=new.business_id and status in ('draft','awaiting_approval');
 elsif new.status='rejected' and old.status is distinct from new.status and new.job_card_id is not null then
   update public.job_cards
   set status='awaiting_approval',updated_at=now()
   where id=new.job_card_id and business_id=new.business_id and status in ('draft','awaiting_approval');
 end if;
 return new;
end;
$$;
drop trigger if exists quotation_customer_approval_job_card on public.quotations;
create trigger quotation_customer_approval_job_card
after update of status on public.quotations
for each row execute function private.sync_job_card_after_customer_approval();

drop policy if exists "Managers or assigned mechanics can update tasks" on public.job_tasks;
create policy "Managers or approved-job mechanics can update tasks"
on public.job_tasks for update to authenticated
using (
 private.has_business_permission(business_id,'garage.manage',location_id)
 or (
   assigned_to=(select auth.uid())
   and private.has_business_permission(business_id,'garage.perform_work',location_id)
   and exists(select 1 from public.job_cards j where j.id=job_tasks.job_card_id and j.business_id=job_tasks.business_id and j.status in ('approved','in_progress','quality_check'))
 )
)
with check (
 private.has_business_permission(business_id,'garage.manage',location_id)
 or (
   assigned_to=(select auth.uid())
   and private.has_business_permission(business_id,'garage.perform_work',location_id)
   and exists(select 1 from public.job_cards j where j.id=job_tasks.job_card_id and j.business_id=job_tasks.business_id and j.status in ('approved','in_progress','quality_check'))
 )
);
