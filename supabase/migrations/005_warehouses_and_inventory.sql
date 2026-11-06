-- Garage ya Joe: multi-warehouse inventory controls and transactional stock ledger.
-- Balances are projections; all quantity changes must pass through the private functions below.

alter table public.locations
  add constraint locations_business_id_id_unique unique (business_id, id);

alter table public.warehouses
  add constraint warehouses_business_id_id_unique unique (business_id, id),
  add constraint warehouses_location_business_fk
    foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict;

alter table public.inventory_balances
  add column business_id uuid;

update public.inventory_balances ib
set business_id = w.business_id
from public.warehouses w
where w.id = ib.warehouse_id;

alter table public.inventory_balances
  alter column business_id set not null,
  add column average_unit_cost_kes numeric(18,4) not null default 0
    check (average_unit_cost_kes >= 0),
  add constraint inventory_balances_business_warehouse_product_unique
    unique (business_id, warehouse_id, product_id),
  add constraint inventory_balances_warehouse_business_fk
    foreign key (business_id, warehouse_id)
    references public.warehouses (business_id, id) on delete restrict,
  add constraint inventory_balances_product_business_fk
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict;

alter table public.stock_movements
  add column quantity_reserved_delta numeric(18,3) not null default 0,
  add column unit_cost_kes numeric(18,4)
    check (unit_cost_kes is null or unit_cost_kes >= 0),
  add constraint stock_movements_warehouse_business_fk
    foreign key (business_id, warehouse_id)
    references public.warehouses (business_id, id) on delete restrict,
  add constraint stock_movements_product_business_fk
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict,
  add constraint stock_movements_quantity_semantics_check
    check (
      (movement_type in ('reservation','release') and quantity_delta = 0 and quantity_reserved_delta <> 0)
      or
      (movement_type not in ('reservation','release') and quantity_delta <> 0 and quantity_reserved_delta = 0)
    );

create index inventory_balances_business_product_idx
  on public.inventory_balances (business_id, product_id);
create index stock_movements_business_created_idx
  on public.stock_movements (business_id, created_at desc);

-- Ensure warehouse location references and product references are business-consistent.
alter table public.warehouses enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.stock_movements enable row level security;

create policy "Inventory staff can view business warehouses"
  on public.warehouses for select to authenticated
  using (private.has_business_permission(business_id, 'inventory.view', location_id));

create policy "Inventory staff can view stock balances"
  on public.inventory_balances for select to authenticated
  using (
    private.has_business_permission(
      business_id,
      'inventory.view',
      (select w.location_id from public.warehouses w where w.id = inventory_balances.warehouse_id)
    )
  );

create policy "Inventory staff can view stock movements"
  on public.stock_movements for select to authenticated
  using (
    private.has_business_permission(
      business_id,
      'inventory.view',
      (select w.location_id from public.warehouses w where w.id = stock_movements.warehouse_id)
    )
  );

-- Do not permit direct client writes to balances or the movement ledger.
revoke all on public.inventory_balances, public.stock_movements from anon, authenticated;
grant select on public.inventory_balances, public.stock_movements to authenticated;
revoke all on public.warehouses from anon, authenticated;
grant select on public.warehouses to authenticated;
grant all on public.warehouses to service_role;

create or replace function private.record_stock_receipt(
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
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_movement_id uuid;
  v_old_qty numeric(18,3);
  v_old_cost numeric(18,4);
  v_new_avg numeric(18,4);
begin
  if v_user_id is null or not private.has_business_permission(p_business_id, 'inventory.manage') then
    raise exception 'Not authorized to receive stock' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or p_unit_cost_kes is null or p_unit_cost_kes < 0 then
    raise exception 'Quantity must be positive and unit cost must be non-negative';
  end if;

  select w.location_id into v_location_id
  from public.warehouses w
  where w.id = p_warehouse_id and w.business_id = p_business_id and w.is_active
  for share;
  if not found then raise exception 'Active warehouse not found for this business'; end if;
  if not exists (
    select 1 from public.products p
    where p.id = p_product_id and p.business_id = p_business_id and p.track_inventory
  ) then raise exception 'Inventory-tracked product not found for this business'; end if;
  if not private.has_business_permission(p_business_id, 'inventory.manage', v_location_id) then
    raise exception 'Not authorized for this warehouse location' using errcode = '42501';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, product_id)
  values (p_business_id, p_warehouse_id, p_product_id)
  on conflict (warehouse_id, product_id) do nothing;

  select ib.quantity_on_hand, ib.average_unit_cost_kes
    into v_old_qty, v_old_cost
  from public.inventory_balances ib
  where ib.warehouse_id = p_warehouse_id and ib.product_id = p_product_id
  for update;

  v_new_avg := case
    when v_old_qty + p_quantity = 0 then 0
    else round(((v_old_qty * v_old_cost) + (p_quantity * p_unit_cost_kes)) / (v_old_qty + p_quantity), 4)
  end;

  update public.inventory_balances
  set quantity_on_hand = quantity_on_hand + p_quantity,
      average_unit_cost_kes = v_new_avg,
      updated_at = now()
  where warehouse_id = p_warehouse_id and product_id = p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    unit_cost, currency_code, unit_cost_kes, reference_type, reference_id, notes, created_by
  ) values (
    p_business_id, p_warehouse_id, p_product_id, 'receipt', p_quantity,
    p_unit_cost_kes, 'KES', p_unit_cost_kes, p_reference_type, p_reference_id, p_notes, v_user_id
  ) returning id into v_movement_id;

  return v_movement_id;
end;
$$;

create or replace function private.adjust_stock(
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
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_movement_id uuid;
  v_qty numeric(18,3);
  v_reserved numeric(18,3);
begin
  if v_user_id is null or not private.has_business_permission(p_business_id, 'inventory.manage') then
    raise exception 'Not authorized to adjust stock' using errcode = '42501';
  end if;
  if p_quantity_delta is null or p_quantity_delta = 0 or nullif(trim(p_reason), '') is null then
    raise exception 'A non-zero adjustment and reason are required';
  end if;
  if p_unit_cost_kes is not null and p_unit_cost_kes < 0 then
    raise exception 'Unit cost cannot be negative';
  end if;

  select w.location_id into v_location_id from public.warehouses w
  where w.id = p_warehouse_id and w.business_id = p_business_id and w.is_active for share;
  if not found then raise exception 'Active warehouse not found for this business'; end if;
  if not private.has_business_permission(p_business_id, 'inventory.manage', v_location_id) then
    raise exception 'Not authorized for this warehouse location' using errcode = '42501';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, product_id)
  values (p_business_id, p_warehouse_id, p_product_id)
  on conflict (warehouse_id, product_id) do nothing;

  select quantity_on_hand, quantity_reserved into v_qty, v_reserved
  from public.inventory_balances
  where warehouse_id = p_warehouse_id and product_id = p_product_id
  for update;

  if v_qty + p_quantity_delta < v_reserved then
    raise exception 'Adjustment would reduce stock below the reserved quantity';
  end if;

  update public.inventory_balances
  set quantity_on_hand = quantity_on_hand + p_quantity_delta,
      average_unit_cost_kes = case
        when p_unit_cost_kes is not null and quantity_on_hand + p_quantity_delta > 0
          then p_unit_cost_kes
        when quantity_on_hand + p_quantity_delta = 0 then 0
        else average_unit_cost_kes
      end,
      updated_at = now()
  where warehouse_id = p_warehouse_id and product_id = p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    unit_cost, currency_code, unit_cost_kes, reference_type, notes, created_by
  ) values (
    p_business_id, p_warehouse_id, p_product_id, 'adjustment', p_quantity_delta,
    coalesce(p_unit_cost_kes, (select average_unit_cost_kes from public.inventory_balances
      where warehouse_id = p_warehouse_id and product_id = p_product_id)),
    'KES', p_unit_cost_kes, 'manual_adjustment', p_reason, v_user_id
  ) returning id into v_movement_id;

  return v_movement_id;
end;
$$;

create or replace function private.reserve_stock(
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
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_available numeric(18,3);
  v_movement_id uuid;
begin
  if v_user_id is null or not private.has_business_permission(p_business_id, 'inventory.manage') then
    raise exception 'Not authorized to reserve stock' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or nullif(trim(p_reference_type), '') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select w.location_id into v_location_id from public.warehouses w
  where w.id = p_warehouse_id and w.business_id = p_business_id and w.is_active for share;
  if not found then raise exception 'Active warehouse not found for this business'; end if;
  if not private.has_business_permission(p_business_id, 'inventory.manage', v_location_id) then
    raise exception 'Not authorized for this warehouse location' using errcode = '42501';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, product_id)
  values (p_business_id, p_warehouse_id, p_product_id)
  on conflict (warehouse_id, product_id) do nothing;

  select quantity_on_hand - quantity_reserved into v_available
  from public.inventory_balances
  where warehouse_id = p_warehouse_id and product_id = p_product_id
  for update;

  if v_available < p_quantity then raise exception 'Insufficient available stock'; end if;

  update public.inventory_balances
  set quantity_reserved = quantity_reserved + p_quantity, updated_at = now()
  where warehouse_id = p_warehouse_id and product_id = p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    quantity_reserved_delta, reference_type, reference_id, notes, created_by
  ) values (
    p_business_id, p_warehouse_id, p_product_id, 'reservation', 0,
    p_quantity, p_reference_type, p_reference_id, p_notes, v_user_id
  ) returning id into v_movement_id;

  return v_movement_id;
end;
$$;

create or replace function private.release_stock_reservation(
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
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_reserved numeric(18,3);
  v_movement_id uuid;
begin
  if v_user_id is null or not private.has_business_permission(p_business_id, 'inventory.manage') then
    raise exception 'Not authorized to release stock reservations' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or nullif(trim(p_reference_type), '') is null or p_reference_id is null then
    raise exception 'Positive quantity and a reference are required';
  end if;

  select w.location_id into v_location_id from public.warehouses w
  where w.id = p_warehouse_id and w.business_id = p_business_id and w.is_active for share;
  if not found then raise exception 'Active warehouse not found for this business'; end if;
  if not private.has_business_permission(p_business_id, 'inventory.manage', v_location_id) then
    raise exception 'Not authorized for this warehouse location' using errcode = '42501';
  end if;

  select quantity_reserved into v_reserved
  from public.inventory_balances
  where warehouse_id = p_warehouse_id and product_id = p_product_id
  for update;
  if not found or v_reserved < p_quantity then raise exception 'Reservation quantity exceeds reserved stock'; end if;

  update public.inventory_balances
  set quantity_reserved = quantity_reserved - p_quantity, updated_at = now()
  where warehouse_id = p_warehouse_id and product_id = p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    quantity_reserved_delta, reference_type, reference_id, notes, created_by
  ) values (
    p_business_id, p_warehouse_id, p_product_id, 'release', 0,
    -p_quantity, p_reference_type, p_reference_id, p_notes, v_user_id
  ) returning id into v_movement_id;

  return v_movement_id;
end;
$$;

create or replace function private.transfer_stock(
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
  v_user_id uuid := auth.uid();
  v_source_location uuid;
  v_destination_location uuid;
  v_source_qty numeric(18,3);
  v_source_reserved numeric(18,3);
  v_source_cost numeric(18,4);
  v_destination_qty numeric(18,3);
  v_destination_cost numeric(18,4);
  v_transfer_id uuid := gen_random_uuid();
begin
  if v_user_id is null or not private.has_business_permission(p_business_id, 'inventory.manage') then
    raise exception 'Not authorized to transfer stock' using errcode = '42501';
  end if;
  if p_source_warehouse_id = p_destination_warehouse_id or p_quantity is null or p_quantity <= 0 then
    raise exception 'Choose two different warehouses and a positive quantity';
  end if;

  select location_id into v_source_location from public.warehouses
  where id = p_source_warehouse_id and business_id = p_business_id and is_active for share;
  if not found then raise exception 'Active source warehouse not found'; end if;
  select location_id into v_destination_location from public.warehouses
  where id = p_destination_warehouse_id and business_id = p_business_id and is_active for share;
  if not found then raise exception 'Active destination warehouse not found'; end if;

  if not private.has_business_permission(p_business_id, 'inventory.manage', v_source_location)
     or not private.has_business_permission(p_business_id, 'inventory.manage', v_destination_location) then
    raise exception 'Not authorized for both warehouse locations' using errcode = '42501';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, product_id)
  values
    (p_business_id, p_source_warehouse_id, p_product_id),
    (p_business_id, p_destination_warehouse_id, p_product_id)
  on conflict (warehouse_id, product_id) do nothing;

  -- Lock both balances in a stable order to reduce deadlock risk.
  perform 1 from public.inventory_balances
  where product_id = p_product_id
    and warehouse_id in (p_source_warehouse_id, p_destination_warehouse_id)
  order by warehouse_id
  for update;

  select quantity_on_hand, quantity_reserved, average_unit_cost_kes
    into v_source_qty, v_source_reserved, v_source_cost
  from public.inventory_balances
  where warehouse_id = p_source_warehouse_id and product_id = p_product_id;

  if v_source_qty - v_source_reserved < p_quantity then
    raise exception 'Insufficient unreserved stock in source warehouse';
  end if;

  select quantity_on_hand, average_unit_cost_kes
    into v_destination_qty, v_destination_cost
  from public.inventory_balances
  where warehouse_id = p_destination_warehouse_id and product_id = p_product_id;

  update public.inventory_balances
  set quantity_on_hand = quantity_on_hand - p_quantity, updated_at = now()
  where warehouse_id = p_source_warehouse_id and product_id = p_product_id;

  update public.inventory_balances
  set quantity_on_hand = quantity_on_hand + p_quantity,
      average_unit_cost_kes = case
        when v_destination_qty + p_quantity = 0 then 0
        else round(((v_destination_qty * v_destination_cost) + (p_quantity * v_source_cost)) /
          (v_destination_qty + p_quantity), 4)
      end,
      updated_at = now()
  where warehouse_id = p_destination_warehouse_id and product_id = p_product_id;

  insert into public.stock_movements (
    business_id, warehouse_id, product_id, movement_type, quantity_delta,
    unit_cost, currency_code, unit_cost_kes, reference_type, reference_id, notes, created_by
  ) values
    (p_business_id, p_source_warehouse_id, p_product_id, 'transfer_out', -p_quantity,
      v_source_cost, 'KES', v_source_cost, 'transfer', v_transfer_id, p_notes, v_user_id),
    (p_business_id, p_destination_warehouse_id, p_product_id, 'transfer_in', p_quantity,
      v_source_cost, 'KES', v_source_cost, 'transfer', v_transfer_id, p_notes, v_user_id);

  return v_transfer_id;
end;
$$;

-- No public execution: these functions are callable only by authenticated users with database permissions.
revoke all on function private.record_stock_receipt(uuid,uuid,uuid,numeric,numeric,text,uuid,text) from public, anon;
revoke all on function private.adjust_stock(uuid,uuid,uuid,numeric,text,numeric) from public, anon;
revoke all on function private.reserve_stock(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function private.release_stock_reservation(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
revoke all on function private.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) from public, anon;

grant usage on schema private to authenticated;
grant execute on function private.record_stock_receipt(uuid,uuid,uuid,numeric,numeric,text,uuid,text) to authenticated;
grant execute on function private.adjust_stock(uuid,uuid,uuid,numeric,text,numeric) to authenticated;
grant execute on function private.reserve_stock(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function private.release_stock_reservation(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;
grant execute on function private.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) to authenticated;
