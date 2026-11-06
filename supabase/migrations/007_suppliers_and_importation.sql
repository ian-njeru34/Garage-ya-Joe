-- Garage ya Joe: suppliers, procurement, importation, shipments, landed costs and goods receiving.
-- Sensitive supplier, purchasing and shipment records are staff-only and business/location scoped.

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  supplier_code text not null,
  supplier_name text not null,
  supplier_type text not null default 'local'
    check (supplier_type in ('local','international','manufacturer','distributor','clearing_agent','freight_forwarder')),
  contact_person text,
  email text,
  phone text,
  website text,
  tax_identifier text,
  country_code char(2),
  default_currency char(3) not null default 'KES' references public.currencies(code),
  payment_terms text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  unique (business_id, supplier_code),
  check (length(trim(supplier_code)) > 0),
  check (length(trim(supplier_name)) > 0)
);

create table public.supplier_product_references (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  supplier_id uuid not null,
  product_id uuid not null,
  supplier_part_number text not null,
  supplier_description text,
  last_quoted_price numeric(18,4) check (last_quoted_price is null or last_quoted_price >= 0),
  price_currency char(3) references public.currencies(code),
  minimum_order_quantity numeric(18,3) check (minimum_order_quantity is null or minimum_order_quantity > 0),
  lead_time_days integer check (lead_time_days is null or lead_time_days >= 0),
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, supplier_id) references public.suppliers(business_id,id) on delete restrict,
  foreign key (business_id, product_id) references public.products(business_id,id) on delete restrict,
  unique (business_id, id),
  unique (business_id, supplier_id, supplier_part_number),
  unique (business_id, supplier_id, product_id),
  check (length(trim(supplier_part_number)) > 0)
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  supplier_id uuid not null,
  po_number text not null,
  status text not null default 'draft'
    check (status in ('draft','submitted','partially_received','received','cancelled','closed')),
  order_type text not null default 'local'
    check (order_type in ('local','import')),
  order_date date not null default current_date,
  expected_delivery_date date,
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null default 1 check (exchange_rate_to_kes > 0),
  supplier_reference text,
  payment_terms_snapshot text,
  subtotal numeric(18,2) not null default 0 check (subtotal >= 0),
  discount_total numeric(18,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  order_total numeric(18,2) not null default 0 check (order_total >= 0),
  order_total_kes numeric(18,2) not null default 0 check (order_total_kes >= 0),
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id, supplier_id) references public.suppliers(business_id,id) on delete restrict,
  unique (business_id, id),
  unique (business_id, po_number),
  check (expected_delivery_date is null or expected_delivery_date >= order_date)
);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  purchase_order_id uuid not null,
  product_id uuid not null,
  supplier_product_reference_id uuid,
  line_description text not null,
  ordered_quantity numeric(18,3) not null check (ordered_quantity > 0),
  received_quantity numeric(18,3) not null default 0 check (received_quantity >= 0 and received_quantity <= ordered_quantity),
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  estimated_landed_unit_cost_kes numeric(18,4) check (estimated_landed_unit_cost_kes is null or estimated_landed_unit_cost_kes >= 0),
  actual_landed_unit_cost_kes numeric(18,4) check (actual_landed_unit_cost_kes is null or actual_landed_unit_cost_kes >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, purchase_order_id) references public.purchase_orders(business_id,id) on delete restrict,
  foreign key (business_id, product_id) references public.products(business_id,id) on delete restrict,
  foreign key (business_id, supplier_product_reference_id) references public.supplier_product_references(business_id,id) on delete restrict,
  unique (business_id, id)
);

create table public.import_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  request_number text not null,
  requested_by_customer_id uuid,
  requested_by_profile_id uuid references public.profiles(id) on delete restrict,
  related_job_part_id uuid,
  product_id uuid,
  requested_part_name text not null,
  requested_part_number text,
  oem_number text,
  vehicle_make text,
  vehicle_model text,
  vehicle_year smallint,
  engine_code text,
  quantity numeric(18,3) not null default 1 check (quantity > 0),
  customer_budget numeric(18,2) check (customer_budget is null or customer_budget >= 0),
  budget_currency char(3) references public.currencies(code),
  status text not null default 'requested'
    check (status in ('requested','researching','quoted','awaiting_customer_approval','approved','ordered','in_transit','arrived','fulfilled','cancelled','unavailable')),
  urgency text not null default 'standard' check (urgency in ('standard','urgent')),
  customer_notes text,
  internal_notes text,
  quoted_price numeric(18,2) check (quoted_price is null or quoted_price >= 0),
  quoted_currency char(3) references public.currencies(code),
  quote_valid_until date,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id, requested_by_customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id, product_id) references public.products(business_id,id) on delete restrict,
  unique (business_id, id),
  unique (business_id, request_number),
  check (vehicle_year is null or vehicle_year between 1900 and 2100),
  check (length(trim(requested_part_name)) > 0)
);

create table public.import_request_supplier_quotes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  import_request_id uuid not null,
  supplier_id uuid not null,
  supplier_part_number text,
  quoted_unit_price numeric(18,4) not null check (quoted_unit_price >= 0),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  estimated_shipping_kes numeric(18,2) not null default 0 check (estimated_shipping_kes >= 0),
  estimated_duty_kes numeric(18,2) not null default 0 check (estimated_duty_kes >= 0),
  estimated_other_costs_kes numeric(18,2) not null default 0 check (estimated_other_costs_kes >= 0),
  estimated_landed_total_kes numeric(18,2) not null check (estimated_landed_total_kes >= 0),
  lead_time_days integer check (lead_time_days is null or lead_time_days >= 0),
  quote_expires_at date,
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (business_id, import_request_id) references public.import_requests(business_id,id) on delete restrict,
  foreign key (business_id, supplier_id) references public.suppliers(business_id,id) on delete restrict,
  unique (business_id, id)
);

create table public.shipments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  destination_location_id uuid not null,
  shipment_reference text not null,
  carrier_name text,
  tracking_number text,
  origin_country char(2),
  origin_port text,
  destination_port text,
  shipping_method text not null default 'air'
    check (shipping_method in ('air','sea','road','courier','other')),
  status text not null default 'planned'
    check (status in ('planned','booked','dispatched','in_transit','customs','cleared','arrived','partially_received','received','exception','cancelled')),
  departure_date date,
  estimated_arrival_date date,
  actual_arrival_date date,
  clearing_agent_supplier_id uuid,
  freight_forwarder_supplier_id uuid,
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, destination_location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id, clearing_agent_supplier_id) references public.suppliers(business_id,id) on delete restrict,
  foreign key (business_id, freight_forwarder_supplier_id) references public.suppliers(business_id,id) on delete restrict,
  unique (business_id, id),
  unique (business_id, shipment_reference),
  check (estimated_arrival_date is null or departure_date is null or estimated_arrival_date >= departure_date)
);

create table public.shipment_purchase_orders (
  business_id uuid not null,
  shipment_id uuid not null,
  purchase_order_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (shipment_id, purchase_order_id),
  foreign key (business_id, shipment_id) references public.shipments(business_id,id) on delete restrict,
  foreign key (business_id, purchase_order_id) references public.purchase_orders(business_id,id) on delete restrict
);

create table public.shipment_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  shipment_id uuid not null,
  purchase_order_item_id uuid not null,
  shipped_quantity numeric(18,3) not null check (shipped_quantity > 0),
  package_reference text,
  weight_kg numeric(18,3) check (weight_kg is null or weight_kg >= 0),
  volume_m3 numeric(18,4) check (volume_m3 is null or volume_m3 >= 0),
  notes text,
  created_at timestamptz not null default now(),
  foreign key (business_id, shipment_id) references public.shipments(business_id,id) on delete restrict,
  foreign key (business_id, purchase_order_item_id) references public.purchase_order_items(business_id,id) on delete restrict,
  unique (business_id, id)
);

create table public.shipment_landed_costs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  shipment_id uuid not null,
  charge_type text not null
    check (charge_type in ('freight','insurance','customs_duty','import_declaration_fee','clearing','port_handling','inspection','storage','transport','bank_fee','other')),
  description text,
  supplier_id uuid,
  amount numeric(18,2) not null check (amount >= 0),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  amount_kes numeric(18,2) not null check (amount_kes >= 0),
  invoice_reference text,
  incurred_at date,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (business_id, shipment_id) references public.shipments(business_id,id) on delete restrict,
  foreign key (business_id, supplier_id) references public.suppliers(business_id,id) on delete restrict,
  unique (business_id, id)
);

create table public.shipment_landed_cost_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  shipment_landed_cost_id uuid not null,
  shipment_item_id uuid not null,
  allocation_method text not null
    check (allocation_method in ('item_value','quantity','weight','volume','manual')),
  allocated_amount_kes numeric(18,2) not null check (allocated_amount_kes >= 0),
  allocation_basis numeric(18,6) check (allocation_basis is null or allocation_basis >= 0),
  created_at timestamptz not null default now(),
  foreign key (business_id, shipment_landed_cost_id) references public.shipment_landed_costs(business_id,id) on delete restrict,
  foreign key (business_id, shipment_item_id) references public.shipment_items(business_id,id) on delete restrict,
  unique (shipment_landed_cost_id, shipment_item_id)
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  warehouse_id uuid not null,
  receipt_number text not null,
  purchase_order_id uuid,
  shipment_id uuid,
  status text not null default 'draft' check (status in ('draft','posted','cancelled')),
  received_at timestamptz not null default now(),
  received_by uuid references public.profiles(id) on delete restrict,
  posted_at timestamptz,
  posted_by uuid references public.profiles(id) on delete restrict,
  notes text,
  created_at timestamptz not null default now(),
  foreign key (business_id, location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id, warehouse_id) references public.warehouses(business_id,id) on delete restrict,
  foreign key (business_id, purchase_order_id) references public.purchase_orders(business_id,id) on delete restrict,
  foreign key (business_id, shipment_id) references public.shipments(business_id,id) on delete restrict,
  unique (business_id, id),
  unique (business_id, receipt_number)
);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  goods_receipt_id uuid not null,
  purchase_order_item_id uuid,
  product_id uuid not null,
  received_quantity numeric(18,3) not null check (received_quantity > 0),
  unit_landed_cost_kes numeric(18,4) not null check (unit_landed_cost_kes >= 0),
  condition_status text not null default 'good'
    check (condition_status in ('good','damaged','quarantined','short_shipped')),
  notes text,
  created_at timestamptz not null default now(),
  foreign key (business_id, goods_receipt_id) references public.goods_receipts(business_id,id) on delete restrict,
  foreign key (business_id, purchase_order_item_id) references public.purchase_order_items(business_id,id) on delete restrict,
  foreign key (business_id, product_id) references public.products(business_id,id) on delete restrict,
  unique (business_id, id)
);

create index suppliers_business_name_idx on public.suppliers (business_id, lower(supplier_name));
create index supplier_product_refs_product_idx on public.supplier_product_references (business_id, product_id);
create index purchase_orders_business_status_date_idx on public.purchase_orders (business_id, status, order_date desc);
create index purchase_order_items_po_idx on public.purchase_order_items (business_id, purchase_order_id);
create index import_requests_business_status_idx on public.import_requests (business_id, status, created_at desc);
create index import_requests_part_number_idx on public.import_requests (business_id, requested_part_number);
create index shipments_business_status_eta_idx on public.shipments (business_id, status, estimated_arrival_date);
create index shipment_items_shipment_idx on public.shipment_items (business_id, shipment_id);
create index landed_costs_shipment_idx on public.shipment_landed_costs (business_id, shipment_id);
create index goods_receipts_business_date_idx on public.goods_receipts (business_id, received_at desc);
create index goods_receipt_items_receipt_idx on public.goods_receipt_items (business_id, goods_receipt_id);

-- Every procurement table is protected by RLS. Staff access is permission + branch scoped.
do $$
declare
  t text;
begin
  foreach t in array array[
    'suppliers','supplier_product_references','purchase_orders','purchase_order_items',
    'import_requests','import_request_supplier_quotes','shipments','shipment_purchase_orders',
    'shipment_items','shipment_landed_costs','shipment_landed_cost_allocations',
    'goods_receipts','goods_receipt_items'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create policy "Procurement staff can view suppliers"
  on public.suppliers for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage suppliers"
  on public.suppliers for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view supplier product references"
  on public.supplier_product_references for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage supplier product references"
  on public.supplier_product_references for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view purchase orders"
  on public.purchase_orders for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage',location_id));

create policy "Procurement staff can manage purchase orders"
  on public.purchase_orders for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage',location_id))
  with check (private.has_business_permission(business_id,'procurement.manage',location_id));

create policy "Procurement staff can view purchase order items"
  on public.purchase_order_items for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage purchase order items"
  on public.purchase_order_items for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view import requests"
  on public.import_requests for select to authenticated
  using (
    private.has_business_permission(business_id,'procurement.manage',location_id)
    or (
      requested_by_profile_id = (select auth.uid())
      and private.has_business_permission(business_id,'customer_portal.view_own')
    )
  );

create policy "Procurement staff can manage import requests"
  on public.import_requests for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage',location_id))
  with check (private.has_business_permission(business_id,'procurement.manage',location_id));

create policy "Procurement staff can view import supplier quotes"
  on public.import_request_supplier_quotes for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage import supplier quotes"
  on public.import_request_supplier_quotes for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view shipments"
  on public.shipments for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage',destination_location_id));

create policy "Procurement staff can manage shipments"
  on public.shipments for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage',destination_location_id))
  with check (private.has_business_permission(business_id,'procurement.manage',destination_location_id));

create policy "Procurement staff can view shipment purchase orders"
  on public.shipment_purchase_orders for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage shipment purchase orders"
  on public.shipment_purchase_orders for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view shipment items"
  on public.shipment_items for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage shipment items"
  on public.shipment_items for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view landed costs"
  on public.shipment_landed_costs for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage landed costs"
  on public.shipment_landed_costs for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can view landed cost allocations"
  on public.shipment_landed_cost_allocations for select to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'));

create policy "Procurement staff can manage landed cost allocations"
  on public.shipment_landed_cost_allocations for all to authenticated
  using (private.has_business_permission(business_id,'procurement.manage'))
  with check (private.has_business_permission(business_id,'procurement.manage'));

create policy "Inventory staff can view goods receipts"
  on public.goods_receipts for select to authenticated
  using (private.has_business_permission(business_id,'inventory.view',location_id));

create policy "Inventory staff can create goods receipts"
  on public.goods_receipts for insert to authenticated
  with check (private.has_business_permission(business_id,'inventory.manage',location_id));

create policy "Inventory staff can view goods receipt items"
  on public.goods_receipt_items for select to authenticated
  using (private.has_business_permission(business_id,'inventory.view'));

create policy "Inventory staff can create goods receipt items"
  on public.goods_receipt_items for insert to authenticated
  with check (private.has_business_permission(business_id,'inventory.manage'));

-- No browser-side deletion of procurement/receiving audit records.
do $$
declare
  t text;
begin
  foreach t in array array[
    'suppliers','supplier_product_references','purchase_orders','purchase_order_items',
    'import_requests','import_request_supplier_quotes','shipments','shipment_purchase_orders',
    'shipment_items','shipment_landed_costs','shipment_landed_cost_allocations',
    'goods_receipts','goods_receipt_items'
  ] loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
