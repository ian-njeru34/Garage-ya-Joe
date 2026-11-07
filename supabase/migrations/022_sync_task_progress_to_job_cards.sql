-- Reflect mechanic task progress on the customer-visible job card.
create or replace function private.sync_job_card_task_progress()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_job_status text;
begin
 if new.status='in_progress' and old.status is distinct from new.status then
   update public.job_cards
   set status='in_progress',
       work_started_at=coalesce(work_started_at,now()),
       updated_at=now()
   where id=new.job_card_id and business_id=new.business_id
     and status in ('approved','in_progress');
 elsif new.status='completed' and old.status is distinct from new.status then
   if not exists(
     select 1 from public.job_tasks t
     where t.job_card_id=new.job_card_id
       and t.business_id=new.business_id
       and t.status in ('pending','in_progress','blocked')
   ) then
     update public.job_cards
     set status='quality_check',updated_at=now()
     where id=new.job_card_id and business_id=new.business_id
       and status in ('approved','in_progress');
   end if;
 end if;
 return new;
end;
$$;
drop trigger if exists job_task_sync_job_card_progress on public.job_tasks;
create trigger job_task_sync_job_card_progress
after update of status on public.job_tasks
for each row execute function private.sync_job_card_task_progress();
