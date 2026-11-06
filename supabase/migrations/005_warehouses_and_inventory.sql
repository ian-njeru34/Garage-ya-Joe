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
