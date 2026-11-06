-- Garage ya Joe: transactional operational functions and database triggers.
-- All stock changes append to the immutable stock ledger; balances are projections.
-- Financial document totals are recalculated from their line items inside the same transaction.

-- ---------------------------------------------------------------------------
-- Inventory ledger and balance projection
-- ---------------------------------------------------------------------------

create or replace function private.guard_stock_movement_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Stock movements are immutable. Record a correcting movement instead';
end;
$$;

create trigger stock_movements_immutable
before update or delete on public.stock_movements
for each row execute function private.guard_stock_movement_immutable();

create or replace function private.project_stock_movement_to_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_on_hand numeric(18,3);
  v_reserved numeric(18,3);
  v_average numeric(18,4);
  v_new_on_hand numeric(18,3);
  v_new_reserved numeric(18,3);
  v_new_average numeric(18,4);
begin
  insert into public.inventory_balances(
    business_id,warehouse_id,product_id,quantity_on_hand,quantity_reserved,average_unit_cost_kes
  ) values (
    new.business_id,new.warehouse_id,new.product_id,0,0,0
  )
  on conflict (business_id,warehouse_id,product_id) do nothing;

  select quantity_on_hand,quantity_reserved,average_unit_cost_kes
    into v_on_hand,v_reserved,v_average
  from public.inventory_balances
  where business_id=new.business_id
    and warehouse_id=new.warehouse_id
    and product_id=new.product_id
  for update;

  v_new_on_hand := v_on_hand + new.quantity_delta;
  v_new_reserved := v_reserved + new.quantity_reserved_delta;

  if v_new_on_hand < 0 then
    raise exception 'Insufficient stock on hand for product %',new.product_id;
  end if;
  if v_new_reserved < 0 then
    raise exception 'Reserved stock cannot become negative for product %',new.product_id;
  end if;
  if v_new_reserved > v_new_on_hand then
    raise exception 'Reserved stock cannot exceed stock on hand for product %',new.product_id;
  end if;

  v_new_average := v_average;
  if new.quantity_delta > 0 and new.unit_cost_kes is not null then
    if v_new_on_hand = 0 then
      v_new_average := new.unit_cost_kes;
    else
      v_new_average := round(
        ((v_on_hand * v_average) + (new.quantity_delta * new.unit_cost_kes))
        / v_new_on_hand,4
      );
    end if;
  end if;

  update public.inventory_balances
  set quantity_on_hand=v_new_on_hand,
      quantity_reserved=v_new_reserved,
      average_unit_cost_kes=v_new_average,
      updated_at=now()
  where business_id=new.business_id
    and warehouse_id=new.warehouse_id
    and product_id=new.product_id;

  return new;
end;
$$;

create trigger stock_movement_updates_balance
after insert on public.stock_movements
for each row execute function private.project_stock_movement_to_balance();

create or replace function private.apply_stock_movement_impl(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_quantity_reserved_delta numeric default 0,
  p_unit_cost_kes numeric default null,
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
  v_uid uuid := (select auth.uid());
  v_location_id uuid;
  v_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'Authenticated staff session required' using errcode='42501';
  end if;

  select location_id into v_location_id
  from public.warehouses
  where business_id=p_business_id and id=p_warehouse_id and is_active
  for share;
  if not found then raise exception 'Active warehouse not found for this business'; end if;

  if not (
    private.has_business_permission(p_business_id,'inventory.manage',v_location_id)
    or private.has_business_permission(p_business_id,'procurement.manage',v_location_id)
  ) then
    raise exception 'Not authorized to change inventory at this location' using errcode='42501';
  end if;

  if p_movement_type not in ('receipt','sale','reservation','release','transfer_in','transfer_out','adjustment','return') then
    raise exception 'Unsupported stock movement type';
  end if;
  if p_movement_type='reservation' then
    if p_quantity_delta <> 0 or p_quantity_reserved_delta <= 0 then
      raise exception 'Reservation requires zero on-hand delta and a positive reserved delta';
    end if;
  elsif p_movement_type='release' then
    if p_quantity_delta <> 0 or p_quantity_reserved_delta >= 0 then
      raise exception 'Release requires zero on-hand delta and a negative reserved delta';
    end if;
  else
    if p_quantity_delta = 0 or p_quantity_reserved_delta <> 0 then
      raise exception 'Physical stock movements require a non-zero on-hand delta and zero reserved delta';
    end if;
    if p_movement_type in ('receipt','return','transfer_in') and p_quantity_delta <= 0 then
      raise exception 'This movement type requires a positive quantity';
    end if;
    if p_movement_type in ('sale','transfer_out') and p_quantity_delta >= 0 then
      raise exception 'This movement type requires a negative quantity';
    end if;
  end if;

  if p_unit_cost_kes is not null and p_unit_cost_kes < 0 then
    raise exception 'Unit cost cannot be negative';
  end if;
  if p_movement_type in ('receipt','return','transfer_in') and p_unit_cost_kes is null then
    raise exception 'A KES unit cost is required for incoming stock';
  end if;

  insert into public.stock_movements(
    id,business_id,warehouse_id,product_id,movement_type,quantity_delta,
    quantity_reserved_delta,unit_cost_kes,currency_code,reference_type,
    reference_id,notes,created_by
  ) values (
    v_id,p_business_id,p_warehouse_id,p_product_id,p_movement_type,p_quantity_delta,
    p_quantity_reserved_delta,p_unit_cost_kes,'KES',p_reference_type,
    p_reference_id,p_notes,v_uid
  );

  return v_id;
end;
$$;

create or replace function public.record_stock_movement(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_unit_cost_kes numeric default null,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.has_business_permission(
    p_business_id,'inventory.manage',
    (select w.location_id from public.warehouses w where w.business_id=p_business_id and w.id=p_warehouse_id)
  ) then
    raise exception 'Inventory management permission required' using errcode='42501';
  end if;
  return private.apply_stock_movement_impl(
    p_business_id,p_warehouse_id,p_product_id,p_movement_type,
    p_quantity_delta,0,p_unit_cost_kes,'manual',null,p_notes
  );
end;
$$;

create or replace function public.reserve_stock(
  p_business_id uuid,p_warehouse_id uuid,p_product_id uuid,p_quantity numeric,p_reference_type text,p_reference_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_quantity <= 0 then raise exception 'Reservation quantity must be positive'; end if;
  if not private.has_business_permission(
    p_business_id,'inventory.manage',
    (select w.location_id from public.warehouses w where w.business_id=p_business_id and w.id=p_warehouse_id)
  ) then
    raise exception 'Inventory management permission required' using errcode='42501';
  end if;
  return private.apply_stock_movement_impl(
    p_business_id,p_warehouse_id,p_product_id,'reservation',0,p_quantity,
    null,p_reference_type,p_reference_id,'Stock reserved'
  );
end;
$$;

create or replace function public.release_stock(
  p_business_id uuid,p_warehouse_id uuid,p_product_id uuid,p_quantity numeric,p_reference_type text,p_reference_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_quantity <= 0 then raise exception 'Release quantity must be positive'; end if;
  if not private.has_business_permission(
    p_business_id,'inventory.manage',
    (select w.location_id from public.warehouses w where w.business_id=p_business_id and w.id=p_warehouse_id)
  ) then
    raise exception 'Inventory management permission required' using errcode='42501';
  end if;
  return private.apply_stock_movement_impl(
    p_business_id,p_warehouse_id,p_product_id,'release',0,-p_quantity,
    null,p_reference_type,p_reference_id,'Stock reservation released'
  );
end;
$$;

create or replace function public.transfer_stock(
  p_business_id uuid,p_from_warehouse_id uuid,p_to_warehouse_id uuid,
  p_product_id uuid,p_quantity numeric,p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_from_location uuid;
  v_to_location uuid;
  v_cost numeric(18,4);
  v_reference uuid := gen_random_uuid();
begin
  if p_quantity <= 0 then raise exception 'Transfer quantity must be positive'; end if;
  select location_id into v_from_location from public.warehouses
    where business_id=p_business_id and id=p_from_warehouse_id and is_active;
  select location_id into v_to_location from public.warehouses
    where business_id=p_business_id and id=p_to_warehouse_id and is_active;
  if v_from_location is null or v_to_location is null then
    raise exception 'Both warehouses must be active and belong to this business';
  end if;
  if p_from_warehouse_id=p_to_warehouse_id then raise exception 'Source and destination warehouses must differ'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_from_location)
     or not private.has_business_permission(p_business_id,'inventory.manage',v_to_location) then
    raise exception 'Inventory management permission is required at both warehouse locations' using errcode='42501';
  end if;

  select average_unit_cost_kes into v_cost
  from public.inventory_balances
  where business_id=p_business_id and warehouse_id=p_from_warehouse_id and product_id=p_product_id
  for update;
  if not found then raise exception 'No stock balance exists at the source warehouse'; end if;

  perform private.apply_stock_movement_impl(
    p_business_id,p_from_warehouse_id,p_product_id,'transfer_out',-p_quantity,0,null,
    'stock_transfer',v_reference,p_notes
  );
  perform private.apply_stock_movement_impl(
    p_business_id,p_to_warehouse_id,p_product_id,'transfer_in',p_quantity,0,coalesce(v_cost,0),
    'stock_transfer',v_reference,p_notes
  );
  return v_reference;
end;
$$;

-- ---------------------------------------------------------------------------
-- Goods receipt posting: receipt, ledger movement, balance and PO quantities
-- commit or roll back together.
-- ---------------------------------------------------------------------------

create or replace function private.post_goods_receipt_impl(p_business_id uuid,p_goods_receipt_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_receipt public.goods_receipts%rowtype;
  v_item record;
  v_po_status text;
  v_all_received boolean;
  v_any_received boolean;
begin
  if v_uid is null then raise exception 'Authenticated staff session required' using errcode='42501'; end if;

  select * into v_receipt
  from public.goods_receipts
  where business_id=p_business_id and id=p_goods_receipt_id
  for update;
  if not found then raise exception 'Goods receipt not found'; end if;
  if v_receipt.status <> 'draft' then raise exception 'Only draft goods receipts can be posted'; end if;
  if not (
    private.has_business_permission(p_business_id,'inventory.manage',v_receipt.location_id)
    or private.has_business_permission(p_business_id,'procurement.manage',v_receipt.location_id)
  ) then
    raise exception 'Procurement or inventory management permission required' using errcode='42501';
  end if;

  if not exists(select 1 from public.goods_receipt_items where business_id=p_business_id and goods_receipt_id=p_goods_receipt_id) then
    raise exception 'A goods receipt must contain at least one item';
  end if;

  for v_item in
    select * from public.goods_receipt_items
    where business_id=p_business_id and goods_receipt_id=p_goods_receipt_id
    order by id
    for update
  loop
    if v_item.condition_status='good' then
      perform private.apply_stock_movement_impl(
        p_business_id,v_receipt.warehouse_id,v_item.product_id,'receipt',
        v_item.received_quantity,0,v_item.unit_landed_cost_kes,
        'goods_receipt',p_goods_receipt_id,
        'Goods receipt '||v_receipt.receipt_number
      );
    end if;

    if v_receipt.purchase_order_id is not null and v_item.purchase_order_item_id is not null then
      update public.purchase_order_items
      set received_quantity=received_quantity+v_item.received_quantity,
          updated_at=now()
      where business_id=p_business_id
        and id=v_item.purchase_order_item_id
        and purchase_order_id=v_receipt.purchase_order_id
        and received_quantity+v_item.received_quantity <= ordered_quantity;
      if not found then
        raise exception 'Received quantity exceeds the purchase order quantity or item does not belong to this order';
      end if;
    end if;
  end loop;

  if v_receipt.purchase_order_id is not null then
    select
      bool_and(received_quantity >= ordered_quantity),
      bool_or(received_quantity > 0)
    into v_all_received,v_any_received
    from public.purchase_order_items
    where business_id=p_business_id and purchase_order_id=v_receipt.purchase_order_id;

    update public.purchase_orders
    set status=case when coalesce(v_all_received,false) then 'received'
                    when coalesce(v_any_received,false) then 'partially_received'
                    else status end,
        updated_at=now()
    where business_id=p_business_id and id=v_receipt.purchase_order_id
      and status in ('submitted','partially_received');
  end if;

  update public.goods_receipts
  set status='posted',posted_at=now(),posted_by=v_uid
  where business_id=p_business_id and id=p_goods_receipt_id;

  return p_goods_receipt_id;
end;
$$;

create or replace function public.post_goods_receipt(p_business_id uuid,p_goods_receipt_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $func$
  select private.post_goods_receipt_impl(p_business_id,p_goods_receipt_id);
$func$;

-- ---------------------------------------------------------------------------
-- Recalculate document totals whenever draft line items change.
-- ---------------------------------------------------------------------------

create or replace function private.recalculate_commercial_document_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_parent_id uuid;
  v_location_id uuid;
  v_status text;
  v_permission text;
begin
  if tg_table_name='quotation_items' then
    v_parent_id := coalesce(new.quotation_id,old.quotation_id);
    select business_id,location_id,status into v_business_id,v_location_id,v_status
      from public.quotations where id=v_parent_id for update;
    v_permission := 'quotations.manage';
  elsif tg_table_name='sales_order_items' then
    v_parent_id := coalesce(new.sales_order_id,old.sales_order_id);
    select business_id,location_id,status into v_business_id,v_location_id,v_status
      from public.sales_orders where id=v_parent_id for update;
    v_permission := 'sales.manage';
  elsif tg_table_name='invoice_items' then
    v_parent_id := coalesce(new.invoice_id,old.invoice_id);
    select business_id,location_id,status into v_business_id,v_location_id,v_status
      from public.invoices where id=v_parent_id for update;
    v_permission := 'sales.manage';
  else
    raise exception 'Unsupported commercial line-item table';
  end if;

  if v_business_id is null then raise exception 'Parent commercial document not found'; end if;
  if v_status <> 'draft' then raise exception 'Line items can only be changed while the document is a draft'; end if;
  if not private.has_business_permission(v_business_id,v_permission,v_location_id) then
    raise exception 'Not authorized to change this document' using errcode='42501';
  end if;

  if tg_table_name='quotation_items' then
    update public.quotations d set
      subtotal_amount=x.subtotal_amount,discount_amount=x.discount_amount,tax_amount=x.tax_amount,total_amount=x.total_amount,
      subtotal_kes=x.subtotal_kes,discount_kes=x.discount_kes,tax_kes=x.tax_kes,total_kes=x.total_kes,updated_at=now()
    from (
      select coalesce(sum(quantity*unit_price),0) subtotal_amount,
             coalesce(sum(discount_amount),0) discount_amount,
             coalesce(sum(tax_amount),0) tax_amount,
             coalesce(sum(line_total),0) total_amount,
             coalesce(sum(quantity*unit_price_kes),0) subtotal_kes,
             coalesce(sum(discount_kes),0) discount_kes,
             coalesce(sum(tax_kes),0) tax_kes,
             coalesce(sum(line_total_kes),0) total_kes
      from public.quotation_items where business_id=v_business_id and quotation_id=v_parent_id
    ) x where d.business_id=v_business_id and d.id=v_parent_id;
  elsif tg_table_name='sales_order_items' then
    update public.sales_orders d set
      subtotal_amount=x.subtotal_amount,discount_amount=x.discount_amount,tax_amount=x.tax_amount,total_amount=x.total_amount,
      subtotal_kes=x.subtotal_kes,discount_kes=x.discount_kes,tax_kes=x.tax_kes,total_kes=x.total_kes,updated_at=now()
    from (
      select coalesce(sum(quantity*unit_price),0) subtotal_amount,
             coalesce(sum(discount_amount),0) discount_amount,
             coalesce(sum(tax_amount),0) tax_amount,
             coalesce(sum(line_total),0) total_amount,
             coalesce(sum(quantity*unit_price_kes),0) subtotal_kes,
             coalesce(sum(discount_kes),0) discount_kes,
             coalesce(sum(tax_kes),0) tax_kes,
             coalesce(sum(line_total_kes),0) total_kes
      from public.sales_order_items where business_id=v_business_id and sales_order_id=v_parent_id
    ) x where d.business_id=v_business_id and d.id=v_parent_id;
  else
    update public.invoices d set
      subtotal_amount=x.subtotal_amount,discount_amount=x.discount_amount,tax_amount=x.tax_amount,total_amount=x.total_amount,
      subtotal_kes=x.subtotal_kes,discount_kes=x.discount_kes,tax_kes=x.tax_kes,total_kes=x.total_kes,updated_at=now()
    from (
      select coalesce(sum(quantity*unit_price),0) subtotal_amount,
             coalesce(sum(discount_amount),0) discount_amount,
             coalesce(sum(tax_amount),0) tax_amount,
             coalesce(sum(line_total),0) total_amount,
             coalesce(sum(quantity*unit_price_kes),0) subtotal_kes,
             coalesce(sum(discount_kes),0) discount_kes,
             coalesce(sum(tax_kes),0) tax_kes,
             coalesce(sum(line_total_kes),0) total_kes
      from public.invoice_items where business_id=v_business_id and invoice_id=v_parent_id
    ) x where d.business_id=v_business_id and d.id=v_parent_id;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create trigger quotation_items_recalculate_totals
after insert or update or delete on public.quotation_items
for each row execute function private.recalculate_commercial_document_totals();

create trigger sales_order_items_recalculate_totals
after insert or update or delete on public.sales_order_items
for each row execute function private.recalculate_commercial_document_totals();

create trigger invoice_items_recalculate_totals
after insert or update or delete on public.invoice_items
for each row execute function private.recalculate_commercial_document_totals();

-- ---------------------------------------------------------------------------
-- Accepted quotation -> sales order, preserving all line-item snapshots.
-- ---------------------------------------------------------------------------

create or replace function public.convert_accepted_quotation_to_order(
  p_business_id uuid,p_quotation_id uuid,p_order_number text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_quote public.quotations%rowtype;
  v_order_id uuid := gen_random_uuid();
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'Authenticated staff session required' using errcode='42501'; end if;
  if nullif(trim(p_order_number),'') is null then raise exception 'Order number is required'; end if;

  select * into v_quote from public.quotations
  where business_id=p_business_id and id=p_quotation_id for update;
  if not found then raise exception 'Quotation not found'; end if;
  if not private.has_business_permission(p_business_id,'sales.manage',v_quote.location_id)
     or not private.has_business_permission(p_business_id,'quotations.manage',v_quote.location_id) then
    raise exception 'Sales and quotation management permissions are required' using errcode='42501';
  end if;
  if v_quote.status <> 'accepted' then raise exception 'Only accepted quotations can be converted'; end if;
  if v_quote.valid_until is not null and v_quote.valid_until < current_date then
    raise exception 'Quotation has expired';
  end if;
  if not exists(select 1 from public.quotation_items where business_id=p_business_id and quotation_id=p_quotation_id) then
    raise exception 'Quotation has no line items';
  end if;

  insert into public.sales_orders(
    id,business_id,location_id,order_number,customer_id,quotation_id,job_card_id,order_source,status,
    currency_code,exchange_rate_to_kes,subtotal_amount,discount_amount,tax_amount,total_amount,
    subtotal_kes,discount_kes,tax_kes,total_kes,customer_notes,internal_notes,created_by,updated_by
  ) values (
    v_order_id,p_business_id,v_quote.location_id,p_order_number,v_quote.customer_id,v_quote.id,
    v_quote.job_card_id,
    case when v_quote.quote_type='garage' then 'garage'
         when v_quote.quote_type='import' then 'import'
         when v_quote.quote_type='spare_parts' then 'online' else 'other' end,
    'confirmed',v_quote.currency_code,v_quote.exchange_rate_to_kes,
    v_quote.subtotal_amount,v_quote.discount_amount,v_quote.tax_amount,v_quote.total_amount,
    v_quote.subtotal_kes,v_quote.discount_kes,v_quote.tax_kes,v_quote.total_kes,
    v_quote.customer_notes,v_quote.internal_notes,v_uid,v_uid
  );

  insert into public.sales_order_items(
    business_id,sales_order_id,line_number,item_type,product_id,description,sku_snapshot,product_name_snapshot,
    quantity,unit_of_measure,unit_price,discount_amount,tax_rate,tax_amount,line_total,
    unit_price_kes,discount_kes,tax_kes,line_total_kes,notes
  )
  select business_id,v_order_id,line_number,item_type,product_id,description,sku_snapshot,product_name_snapshot,
    quantity,unit_of_measure,unit_price,discount_amount,tax_rate,tax_amount,line_total,
    unit_price_kes,discount_kes,tax_kes,line_total_kes,notes
  from public.quotation_items
  where business_id=p_business_id and quotation_id=p_quotation_id
  order by line_number;

  update public.quotations
  set status='converted',converted_at=now(),updated_by=v_uid,updated_at=now()
  where business_id=p_business_id and id=p_quotation_id;

  return v_order_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sales order -> draft invoice, preserving transaction currency and snapshots.
-- ---------------------------------------------------------------------------

create or replace function public.create_invoice_from_sales_order(
  p_business_id uuid,p_sales_order_id uuid,p_invoice_number text,p_due_date date default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order public.sales_orders%rowtype;
  v_invoice_id uuid := gen_random_uuid();
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'Authenticated staff session required' using errcode='42501'; end if;
  if nullif(trim(p_invoice_number),'') is null then raise exception 'Invoice number is required'; end if;

  select * into v_order from public.sales_orders
  where business_id=p_business_id and id=p_sales_order_id for update;
  if not found then raise exception 'Sales order not found'; end if;
  if not private.has_business_permission(p_business_id,'sales.manage',v_order.location_id) then
    raise exception 'Sales management permission required' using errcode='42501';
  end if;
  if v_order.status not in ('confirmed','processing','partially_fulfilled','fulfilled') then
    raise exception 'Sales order must be confirmed before invoicing';
  end if;
  if exists(select 1 from public.invoices where business_id=p_business_id and sales_order_id=p_sales_order_id and status <> 'void') then
    raise exception 'A non-void invoice already exists for this sales order';
  end if;

  insert into public.invoices(
    id,business_id,location_id,invoice_number,customer_id,sales_order_id,quotation_id,job_card_id,
    status,currency_code,exchange_rate_to_kes,subtotal_amount,discount_amount,tax_amount,total_amount,
    subtotal_kes,discount_kes,tax_kes,total_kes,due_date,customer_notes,internal_notes,created_by,updated_by
  ) values (
    v_invoice_id,p_business_id,v_order.location_id,p_invoice_number,v_order.customer_id,v_order.id,
    v_order.quotation_id,v_order.job_card_id,'draft',v_order.currency_code,v_order.exchange_rate_to_kes,
    v_order.subtotal_amount,v_order.discount_amount,v_order.tax_amount,v_order.total_amount,
    v_order.subtotal_kes,v_order.discount_kes,v_order.tax_kes,v_order.total_kes,
    p_due_date,v_order.customer_notes,v_order.internal_notes,v_uid,v_uid
  );

  insert into public.invoice_items(
    business_id,invoice_id,line_number,item_type,product_id,description,sku_snapshot,product_name_snapshot,
    quantity,unit_of_measure,unit_price,discount_amount,tax_rate,tax_amount,line_total,
    unit_price_kes,discount_kes,tax_kes,line_total_kes,notes
  )
  select business_id,v_invoice_id,line_number,item_type,product_id,description,sku_snapshot,product_name_snapshot,
    quantity,unit_of_measure,unit_price,discount_amount,tax_rate,tax_amount,line_total,
    unit_price_kes,discount_kes,tax_kes,line_total_kes,notes
  from public.sales_order_items
  where business_id=p_business_id and sales_order_id=p_sales_order_id
  order by line_number;

  return v_invoice_id;
end;
$$;

-- Internal trigger/function permissions.
revoke all on function private.guard_stock_movement_immutable() from public,anon,authenticated;
revoke all on function private.project_stock_movement_to_balance() from public,anon,authenticated;
revoke all on function private.apply_stock_movement_impl(uuid,uuid,uuid,text,numeric,numeric,numeric,text,uuid,text) from public,anon;
revoke all on function private.recalculate_commercial_document_totals() from public,anon,authenticated;
revoke all on function private.post_goods_receipt_impl(uuid,uuid) from public,anon;
grant execute on function private.post_goods_receipt_impl(uuid,uuid) to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.apply_stock_movement_impl(uuid,uuid,uuid,text,numeric,numeric,numeric,text,uuid,text) to authenticated;

revoke all on function public.record_stock_movement(uuid,uuid,uuid,text,numeric,numeric,text) from public,anon;
revoke all on function public.reserve_stock(uuid,uuid,uuid,numeric,text,uuid) from public,anon;
revoke all on function public.release_stock(uuid,uuid,uuid,numeric,text,uuid) from public,anon;
revoke all on function public.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) from public,anon;
revoke all on function public.post_goods_receipt(uuid,uuid) from public,anon;
revoke all on function public.convert_accepted_quotation_to_order(uuid,uuid,text) from public,anon;
revoke all on function public.create_invoice_from_sales_order(uuid,uuid,text,date) from public,anon;

grant execute on function public.record_stock_movement(uuid,uuid,uuid,text,numeric,numeric,text) to authenticated;
grant execute on function public.reserve_stock(uuid,uuid,uuid,numeric,text,uuid) to authenticated;
grant execute on function public.release_stock(uuid,uuid,uuid,numeric,text,uuid) to authenticated;
grant execute on function public.transfer_stock(uuid,uuid,uuid,uuid,numeric,text) to authenticated;
grant execute on function public.post_goods_receipt(uuid,uuid) to authenticated;
grant execute on function public.convert_accepted_quotation_to_order(uuid,uuid,text) to authenticated;
grant execute on function public.create_invoice_from_sales_order(uuid,uuid,text,date) to authenticated;
