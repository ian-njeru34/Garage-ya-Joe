-- Workshop job part issue tracking and atomic inventory deduction.
alter table public.job_parts
  add column if not exists issued_quantity numeric(18,3) not null default 0 check (issued_quantity >= 0),
  add column if not exists issued_unit_cost_kes numeric(18,4),
  add column if not exists last_issued_at timestamptz,
  add column if not exists last_issued_by uuid references public.profiles(id) on delete set null;

create or replace function public.issue_job_part_stock(
  p_job_part_id uuid,
  p_warehouse_id uuid,
  p_quantity numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_business uuid;
  v_location uuid;
  v_job uuid;
  v_product uuid;
  v_requested numeric(18,3);
  v_issued numeric(18,3);
  v_old_issue_cost numeric(18,4);
  v_part_status text;
  v_job_status text;
  v_warehouse_location uuid;
  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_unit_cost numeric(18,4);
  v_new_issue_cost numeric(18,4);
  v_movement uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Issue quantity must be greater than zero'; end if;

  select jp.business_id,jp.location_id,jp.job_card_id,jp.product_id,
         jp.requested_quantity,jp.issued_quantity,jp.issued_unit_cost_kes,
         jp.fulfillment_status,j.status
    into v_business,v_location,v_job,v_product,v_requested,v_issued,v_old_issue_cost,
         v_part_status,v_job_status
  from public.job_parts jp
  join public.job_cards j on j.id=jp.job_card_id and j.business_id=jp.business_id
  where jp.id=p_job_part_id
  for update of jp;
  if not found then raise exception 'Job part request not found'; end if;
  if v_job_status not in ('approved','in_progress') then raise exception 'The job must be approved or in progress before issuing parts'; end if;
  if not private.has_business_permission(v_business,'inventory.manage',v_location) then raise exception 'Not authorized to issue stock for this branch' using errcode='42501'; end if;
  if v_part_status in ('fulfilled','cancelled') or v_issued + p_quantity > v_requested then raise exception 'Issue quantity exceeds the remaining requested quantity'; end if;

  select w.location_id into v_warehouse_location from public.warehouses w
  where w.id=p_warehouse_id and w.business_id=v_business and w.is_active for share;
  if not found or v_warehouse_location is distinct from v_location then raise exception 'Choose an active warehouse belonging to the job branch'; end if;

  select b.quantity_on_hand,b.quantity_reserved,b.average_unit_cost_kes
    into v_on_hand,v_reserved,v_unit_cost
  from public.inventory_balances b
  where b.business_id=v_business and b.warehouse_id=p_warehouse_id and b.product_id=v_product
  for update;
  if not found or v_on_hand-v_reserved < p_quantity then raise exception 'Insufficient unreserved stock in the selected warehouse'; end if;

  update public.inventory_balances set quantity_on_hand=quantity_on_hand-p_quantity,updated_at=now()
  where business_id=v_business and warehouse_id=p_warehouse_id and product_id=v_product;

  v_new_issue_cost := case when v_issued=0 then coalesce(v_unit_cost,0)
    else round(((v_issued*coalesce(v_old_issue_cost,0))+(p_quantity*coalesce(v_unit_cost,0)))/(v_issued+p_quantity),4) end;

  update public.job_parts set issued_quantity=issued_quantity+p_quantity,
    issued_unit_cost_kes=v_new_issue_cost,
    fulfillment_status=case when issued_quantity+p_quantity >= requested_quantity then 'fulfilled' else 'available' end,
    last_issued_at=now(),last_issued_by=v_uid,updated_at=now()
  where id=p_job_part_id;

  insert into public.stock_movements(
    business_id,warehouse_id,product_id,movement_type,quantity_delta,quantity_reserved_delta,
    unit_cost,currency_code,unit_cost_kes,reference_type,reference_id,notes,created_by
  ) values(v_business,p_warehouse_id,v_product,'job_issue',-p_quantity,0,v_unit_cost,'KES',v_unit_cost,
    'job_part',p_job_part_id,'Issued to workshop job '||v_job::text,v_uid)
  returning id into v_movement;
  return v_movement;
end;
$$;

revoke all on function public.issue_job_part_stock(uuid,uuid,numeric) from public,anon;
grant execute on function public.issue_job_part_stock(uuid,uuid,numeric) to authenticated;
