-- Keep the job card diagnosis/recommendations in sync with mechanic inspection entries.
create or replace function private.sync_inspection_to_job_card()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
 update public.job_cards
 set inspection_id=new.id,
     diagnosis_summary=coalesce(new.findings,diagnosis_summary),
     work_summary=coalesce(new.recommendations,work_summary),
     updated_at=now()
 where business_id=new.business_id
   and appointment_id=new.appointment_id;
 return new;
end;
$$;
drop trigger if exists vehicle_inspection_sync_job_card on public.vehicle_inspections;
create trigger vehicle_inspection_sync_job_card
after insert or update of findings,recommendations on public.vehicle_inspections
for each row execute function private.sync_inspection_to_job_card();
