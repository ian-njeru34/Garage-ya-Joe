-- Harden inventory RPCs: public API functions are invokers; privileged implementations are private.

create or replace function private.receive_stock_impl(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_unit_cost_kes numeric,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_old_qty numeric(18,3);
  v_old_cost numeric(18,4);
  v_new_cost numeric(18,4);
  v_movement uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_quantity is null or p_quantity <= 0 or p_unit_cost_kes is null or p_unit_cost_kes < 0 then
    raise exception 'Quantity must be positive and unit cost must be non-negative';
  end if;

  select w.location_id into v_location
  from public.warehouses w
  where w.id = p_warehouse_id and w.business_id = p_business_id and w.is_active
  for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id, 'inventory.manage', v_location) then
    raise exception 'Not authorized for this warehouse' using errcode = '42501';
  end if;
  if not exists (select 1 from public.products p where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory) then
    raise exception 'Inventory-tracked product not found';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, product_id)
  values (p_business_id, p_warehouse_id, p_product_id)
  on conflict (warehouse_id, product_id) do nothing;

  select quantity_on_hand, average_unit_cost_kes into v_old_qty, v_old_cost
  from public.inventory_balances
  where warehouse_id=p_warehouse_id and product_id=p_product_id
  for update;

  v_new_cost := round(((v_old_qty * v_old_cost) + (p_quantity * p_unit_cost_kes)) / (v_old_qty + p_quantity), 4);
  update public.inventory_balances
  set quantity_on_hand=quantity_on_hand+p_quantity,
      average_unit_cost_kes=v_new_cost, updated_at=now()
  where warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    unit_cost, currency_code, unit_cost_kes, reference_type, reference_id, notes, created_by
  ) values (
    p_business_id, p_warehouse_id, p_product_id, 'receipt', p_quantity,
    p_unit_cost_kes, 'KES', p_unit_cost_kes, p_reference_type, p_reference_id, p_notes, v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$$;

create or replace function private.adjust_stock_impl(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_quantity_delta numeric,
  p_reason text,
  p_unit_cost_kes numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_qty numeric(18,3);
  v_reserved numeric(18,3);
  v_avg numeric(18,4);
  v_new_avg numeric(18,4);
  v_movement uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_quantity_delta is null or p_quantity_delta=0 or nullif(trim(p_reason),'') is null then
    raise exception 'A non-zero adjustment and reason are required';
  end if;
  if p_unit_cost_kes is not null and p_unit_cost_kes < 0 then raise exception 'Unit cost cannot be negative'; end if;

  select location_id into v_location from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized for this warehouse' using errcode='42501';
  end if;
  if not exists (select 1 from public.products p where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory) then
    raise exception 'Inventory-tracked product not found';
  end if;

  insert into public.inventory_balances (business_id,warehouse_id,product_id)
  values (p_business_id,p_warehouse_id,p_product_id)
  on conflict (warehouse_id,product_id) do nothing;

  select quantity_on_hand,quantity_reserved,average_unit_cost_kes
  into v_qty,v_reserved,v_avg
  from public.inventory_balances
  where warehouse_id=p_warehouse_id and product_id=p_product_id for update;

  if v_qty+p_quantity_delta < v_reserved then
    raise exception 'Adjustment would reduce stock below reserved quantity';
  end if;

  v_new_avg := case
    when v_qty+p_quantity_delta=0 then 0
    when p_quantity_delta>0 and p_unit_cost_kes is not null
      then round(((v_qty*v_avg)+(p_quantity_delta*p_unit_cost_kes))/(v_qty+p_quantity_delta),4)
    else v_avg
  end;

  update public.inventory_balances
  set quantity_on_hand=quantity_on_hand+p_quantity_delta,
      average_unit_cost_kes=v_new_avg, updated_at=now()
  where warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    unit_cost,currency_code,unit_cost_kes,reference_type,notes,created_by
  ) values (
    p_business_id,p_warehouse_id,p_product_id,'adjustment',p_quantity_delta,
    coalesce(p_unit_cost_kes,v_avg),'KES',p_unit_cost_kes,'manual_adjustment',p_reason,v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$$;

create or replace function private.reserve_stock_impl(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_reference_type text,
  p_reference_id uuid,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_available numeric(18,3);
  v_movement uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_quantity is null or p_quantity<=0 or nullif(trim(p_reference_type),'') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select location_id into v_location from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized for this warehouse' using errcode='42501';
  end if;
  if not exists (select 1 from public.products p where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory) then
    raise exception 'Inventory-tracked product not found';
  end if;

  insert into public.inventory_balances (business_id,warehouse_id,product_id)
  values (p_business_id,p_warehouse_id,p_product_id)
  on conflict (warehouse_id,product_id) do nothing;

  select quantity_on_hand-quantity_reserved into v_available
  from public.inventory_balances
  where warehouse_id=p_warehouse_id and product_id=p_product_id for update;
  if v_available<p_quantity then raise exception 'Insufficient available stock'; end if;

  update public.inventory_balances
  set quantity_reserved=quantity_reserved+p_quantity,updated_at=now()
  where warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    quantity_reserved_delta,reference_type,reference_id,notes,created_by
  ) values (
    p_business_id,p_warehouse_id,p_product_id,'reservation',0,
    p_quantity,p_reference_type,p_reference_id,p_notes,v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$$;

create or replace function private.release_stock_reservation_impl(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_reference_type text,
  p_reference_id uuid,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_reserved numeric(18,3);
  v_movement uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_quantity is null or p_quantity<=0 or nullif(trim(p_reference_type),'') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select location_id into v_location from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized for this warehouse' using errcode='42501';
  end if;

  select quantity_reserved into v_reserved
  from public.inventory_balances
  where business_id=p_business_id and warehouse_id=p_warehouse_id and product_id=p_product_id
  for update;
  if not found or v_reserved<p_quantity then raise exception 'Reservation exceeds reserved stock'; end if;

  update public.inventory_balances
  set quantity_reserved=quantity_reserved-p_quantity,updated_at=now()
  where warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    quantity_reserved_delta,reference_type,reference_id,notes,created_by
  ) values (
    p_business_id,p_warehouse_id,p_product_id,'release',0,
    -p_quantity,p_reference_type,p_reference_id,p_notes,v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$$;

create or replace function private.transfer_stock_impl(
  p_business_id uuid,
  p_source_warehouse_id uuid,
  p_destination_warehouse_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_source_location uuid;
  v_destination_location uuid;
  v_source_qty numeric(18,3);
  v_source_reserved numeric(18,3);
  v_source_cost numeric(18,4);
  v_destination_qty numeric(18,3);
  v_destination_cost numeric(18,4);
  v_transfer_id uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_source_warehouse_id=p_destination_warehouse_id or p_quantity is null or p_quantity<=0 then
    raise exception 'Choose different warehouses and a positive quantity';
  end if;

  select location_id into v_source_location from public.warehouses
  where id=p_source_warehouse_id and business_id=p_business_id and is_active for share;
  if not found then raise exception 'Active source warehouse not found'; end if;
  select location_id into v_destination_location from public.warehouses
  where id=p_destination_warehouse_id and business_id=p_business_id and is_active for share;
  if not found then raise exception 'Active destination warehouse not found'; end if;

  if not private.has_business_permission(p_business_id,'inventory.manage',v_source_location)
     or not private.has_business_permission(p_business_id,'inventory.manage',v_destination_location) then
    raise exception 'Not authorized for both warehouse locations' using errcode='42501';
  end if;
  if not exists (select 1 from public.products p where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory) then
    raise exception 'Inventory-tracked product not found';
  end if;

  insert into public.inventory_balances (business_id,warehouse_id,product_id)
  values (p_business_id,p_source_warehouse_id,p_product_id),
         (p_business_id,p_destination_warehouse_id,p_product_id)
  on conflict (warehouse_id,product_id) do nothing;

  perform 1 from public.inventory_balances
  where product_id=p_product_id and warehouse_id in (p_source_warehouse_id,p_destination_warehouse_id)
  order by warehouse_id for update;

  select quantity_on_hand,quantity_reserved,average_unit_cost_kes
  into v_source_qty,v_source_reserved,v_source_cost
  from public.inventory_balances
  where warehouse_id=p_source_warehouse_id and product_id=p_product_id;

  if v_source_qty-v_source_reserved<p_quantity then
    raise exception 'Insufficient unreserved source stock';
  end if;

  select quantity_on_hand,average_unit_cost_kes into v_destination_qty,v_destination_cost
  from public.inventory_balances
  where warehouse_id=p_destination_warehouse_id and product_id=p_product_id;

  update public.inventory_balances
  set quantity_on_hand=quantity_on_hand-p_quantity,updated_at=now()
  where warehouse_id=p_source_warehouse_id and product_id=p_product_id;

  update public.inventory_balances
  set quantity_on_hand=quantity_on_hand+p_quantity,
      average_unit_cost_kes=round(((v_destination_qty*v_destination_cost)+(p_quantity*v_source_cost))/(v_destination_qty+p_quantity),4),
      updated_at=now()
  where warehouse_id=p_destination_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    unit_cost,currency_code,unit_cost_kes,reference_type,reference_id,notes,created_by
  ) values
    (p_business_id,p_source_warehouse_id,p_product_id,'transfer_out',-p_quantity,v_source_cost,'KES',v_source_cost,'transfer',v_transfer_id,p_notes,v_uid),
    (p_business_id,p_destination_warehouse_id,p_product_id,'transfer_in',p_quantity,v_source_cost,'KES',v_source_cost,'transfer',v_transfer_id,p_notes,v_uid);

  return v_transfer_id;
end;
$$;


-- Exposed RPC entry points run as invokers. Privileged implementation is isolated in
-- the non-exposed private schema and performs explicit auth + location permission checks.

create or replace function public.receive_stock(
  p_business_id uuid, p_warehouse_id uuid, p_product_id uuid, p_quantity numeric,
  p_unit_cost_kes numeric, p_reference_type text default null,
  p_reference_id uuid default null, p_notes text default null
) returns uuid language sql security invoker set search_path = ''
as $$ select private.receive_stock_impl(p_business_id,p_warehouse_id,p_product_id,p_quantity,p_unit_cost_kes,p_reference_type,p_reference_id,p_notes); $$;

create or replace function public.adjust_stock(
  p_business_id uuid, p_warehouse_id uuid, p_product_id uuid, p_quantity_delta numeric,
  p_reason text, p_unit_cost_kes numeric default null
) returns uuid language sql security invoker set search_path = ''
as $$ select private.adjust_stock_impl(p_business_id,p_warehouse_id,p_product_id,p_quantity_delta,p_reason,p_unit_cost_kes); $$;

create or replace function public.reserve_stock(
  p_business_id uuid, p_warehouse_id uuid, p_product_id uuid, p_quantity numeric,
  p_reference_type text, p_reference_id uuid, p_notes text default null
) returns uuid language sql security invoker set search_path = ''
as $$ select private.reserve_stock_impl(p_business_id,p_warehouse_id,p_product_id,p_quantity,p_reference_type,p_reference_id,p_notes); $$;

create or replace function public.release_stock_reservation(
  p_business_id uuid, p_warehouse_id uuid, p_product_id uuid, p_quantity numeric,
  p_reference_type text, p_reference_id uuid, p_notes text default null
) returns uuid language sql security invoker set search_path = ''
as $$ select private.release_stock_reservation_impl(p_business_id,p_warehouse_id,p_product_id,p_quantity,p_reference_type,p_reference_id,p_notes); $$;

create or replace function public.transfer_stock(
  p_business_id uuid, p_source_warehouse_id uuid, p_destination_warehouse_id uuid,
  p_product_id uuid, p_quantity numeric, p_notes text default null
) returns uuid language sql security invoker set search_path = ''
as $$ select private.transfer_stock_impl(p_business_id,p_source_warehouse_id,p_destination_warehouse_id,p_product_id,p_quantity,p_notes); $$;

revoke all on function public.receive_stock(uuid,uuid,uuid,numeric,numeric,text,uuid,text) from public, anon;
revoke all on function public.adjust_stock(uuid,uuid,uuid,numeric,text,numeric) from public, anon;
revoke all on function public.reserve_stock(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function public.release_stock_reservation(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function public.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) from public, anon;

grant execute on function public.receive_stock(uuid,uuid,uuid,numeric,numeric,text,uuid,text) to authenticated;
grant execute on function public.adjust_stock(uuid,uuid,uuid,numeric,text,numeric) to authenticated;
grant execute on function public.reserve_stock(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function public.release_stock_reservation(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function public.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) to authenticated;

revoke all on function private.receive_stock_impl(uuid,uuid,uuid,numeric,numeric,text,uuid,text) from public, anon;
revoke all on function private.adjust_stock_impl(uuid,uuid,uuid,numeric,text,numeric) from public, anon;
revoke all on function private.reserve_stock_impl(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function private.release_stock_reservation_impl(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function private.transfer_stock_impl(uuid,uuid,uuid,uuid,numeric,text) from public, anon;

grant usage on schema private to authenticated;
grant execute on function private.receive_stock_impl(uuid,uuid,uuid,numeric,numeric,text,uuid,text) to authenticated;
grant execute on function private.adjust_stock_impl(uuid,uuid,uuid,numeric,text,numeric) to authenticated;
grant execute on function private.reserve_stock_impl(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function private.release_stock_reservation_impl(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function private.transfer_stock_impl(uuid,uuid,uuid,uuid,numeric,text) to authenticated;
