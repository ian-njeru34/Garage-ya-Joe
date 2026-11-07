-- Bind inventory reservations to real, same-business orders and protect per-order releases.
-- Public RPC signatures and grants remain unchanged; only the private implementations are hardened.

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
as $function$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_reference_location uuid;
  v_available numeric(18,3);
  v_movement uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if p_quantity is null or p_quantity <= 0
     or nullif(trim(p_reference_type),'') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select location_id into v_location
  from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active
  for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized for this warehouse' using errcode='42501';
  end if;

  -- Only approved workshop jobs and confirmed sales orders may receive new reservations.
  if p_reference_type='job_card' then
    select location_id into v_reference_location
    from public.job_cards
    where id=p_reference_id and business_id=p_business_id
      and status in ('approved','in_progress','quality_check')
    for share;
  elsif p_reference_type='sales_order' then
    select location_id into v_reference_location
    from public.sales_orders
    where id=p_reference_id and business_id=p_business_id
      and status in ('confirmed','processing','partially_fulfilled')
    for share;
  else
    raise exception 'Unsupported reservation reference type';
  end if;
  if not found then raise exception 'Eligible order not found'; end if;
  if v_reference_location is distinct from v_location then
    raise exception 'Order and warehouse must belong to the same location';
  end if;

  if not exists (
    select 1 from public.products p
    where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory
  ) then
    raise exception 'Inventory-tracked product not found';
  end if;

  insert into public.inventory_balances (business_id,warehouse_id,product_id)
  values (p_business_id,p_warehouse_id,p_product_id)
  on conflict (warehouse_id,product_id) do nothing;

  select quantity_on_hand-quantity_reserved into v_available
  from public.inventory_balances
  where business_id=p_business_id and warehouse_id=p_warehouse_id and product_id=p_product_id
  for update;
  if v_available < p_quantity then raise exception 'Insufficient available stock'; end if;

  update public.inventory_balances
  set quantity_reserved=quantity_reserved+p_quantity,updated_at=now()
  where business_id=p_business_id and warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    quantity_reserved_delta,reference_type,reference_id,notes,created_by
  ) values (
    p_business_id,p_warehouse_id,p_product_id,'reservation',0,
    p_quantity,p_reference_type,p_reference_id,p_notes,v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$function$;

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
as $function$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_reference_location uuid;
  v_reserved numeric(18,3);
  v_reference_reserved numeric(18,3);
  v_movement uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if p_quantity is null or p_quantity <= 0
     or nullif(trim(p_reference_type),'') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select location_id into v_location
  from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active
  for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized for this warehouse' using errcode='42501';
  end if;

  -- A reservation may still be released after an order is cancelled or completed,
  -- but its reference must continue to belong to this business and warehouse location.
  if p_reference_type='job_card' then
    select location_id into v_reference_location
    from public.job_cards
    where id=p_reference_id and business_id=p_business_id
    for share;
  elsif p_reference_type='sales_order' then
    select location_id into v_reference_location
    from public.sales_orders
    where id=p_reference_id and business_id=p_business_id
    for share;
  else
    raise exception 'Unsupported reservation reference type';
  end if;
  if not found then raise exception 'Order reference not found'; end if;
  if v_reference_location is distinct from v_location then
    raise exception 'Order and warehouse must belong to the same location';
  end if;

  select quantity_reserved into v_reserved
  from public.inventory_balances
  where business_id=p_business_id and warehouse_id=p_warehouse_id and product_id=p_product_id
  for update;
  if not found or v_reserved < p_quantity then
    raise exception 'Reservation exceeds reserved stock';
  end if;

  select coalesce(sum(quantity_reserved_delta),0) into v_reference_reserved
  from public.stock_movements
  where business_id=p_business_id
    and warehouse_id=p_warehouse_id
    and product_id=p_product_id
    and reference_type=p_reference_type
    and reference_id=p_reference_id
    and movement_type in ('reservation','release');
  if v_reference_reserved < p_quantity then
    raise exception 'Release exceeds this order’s reserved quantity';
  end if;

  update public.inventory_balances
  set quantity_reserved=quantity_reserved-p_quantity,updated_at=now()
  where business_id=p_business_id and warehouse_id=p_warehouse_id and product_id=p_product_id;

  insert into public.stock_movements (
    business_id,warehouse_id,product_id,movement_type,quantity_delta,
    quantity_reserved_delta,reference_type,reference_id,notes,created_by
  ) values (
    p_business_id,p_warehouse_id,p_product_id,'release',0,
    -p_quantity,p_reference_type,p_reference_id,p_notes,v_uid
  ) returning id into v_movement;
  return v_movement;
end;
$function$;
