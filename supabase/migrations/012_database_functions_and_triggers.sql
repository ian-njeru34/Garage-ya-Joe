-- Garage ya Joe: transactional operational functions and database triggers.
-- All stock changes append to the immutable stock ledger; balances are projections.
-- Financial document totals are recalculated from their line items inside the same transaction.

-- ---------------------------------------------------------------------------
-- The existing inventory API in the warehouse migration already updates the
-- balance and appends a stock movement in one transaction. Keep that API as the
-- sole writer; this trigger prevents later edits to the ledger.
create or replace function private.guard_stock_movement_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'Stock movements are immutable. Record a correcting movement instead';
end;
$$;

create trigger stock_movements_immutable
before update or delete on public.stock_movements
for each row execute function private.guard_stock_movement_immutable();

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
  if not private.has_business_permission(p_business_id,'inventory.manage',v_receipt.location_id) then
    raise exception 'Inventory management permission required to post a goods receipt' using errcode='42501';
  end if;
  if v_receipt.purchase_order_id is not null
     and not private.has_business_permission(p_business_id,'procurement.manage',v_receipt.location_id) then
    raise exception 'Procurement management permission required to update the purchase order' using errcode='42501';
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
      perform private.receive_stock_impl(
        p_business_id,v_receipt.warehouse_id,v_item.product_id,
        v_item.received_quantity,v_item.unit_landed_cost_kes,
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
    'draft',v_quote.currency_code,v_quote.exchange_rate_to_kes,
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

  update public.sales_orders set status='confirmed',confirmed_at=now(),updated_by=v_uid,updated_at=now()
  where business_id=p_business_id and id=v_order_id;

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

-- Permit the controlled accepted -> converted quotation transition only.
create policy "Sales staff convert accepted quotations"
on public.quotations for update to authenticated
using (
  status='accepted'
  and private.has_business_permission(business_id,'quotations.manage',location_id)
  and private.has_business_permission(business_id,'sales.manage',location_id)
)
with check (
  status='converted'
  and private.has_business_permission(business_id,'quotations.manage',location_id)
  and private.has_business_permission(business_id,'sales.manage',location_id)
);

-- Prevent moving a line item between documents; otherwise old totals could remain stale.
create or replace function private.prevent_commercial_line_reparent()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_table_name='quotation_items' and new.quotation_id is distinct from old.quotation_id then
    raise exception 'Quotation line items cannot be moved between quotations';
  elsif tg_table_name='sales_order_items' and new.sales_order_id is distinct from old.sales_order_id then
    raise exception 'Sales order line items cannot be moved between orders';
  elsif tg_table_name='invoice_items' and new.invoice_id is distinct from old.invoice_id then
    raise exception 'Invoice line items cannot be moved between invoices';
  end if;
  return new;
end;
$$;

create trigger quotation_items_parent_immutable
before update on public.quotation_items
for each row execute function private.prevent_commercial_line_reparent();
create trigger sales_order_items_parent_immutable
before update on public.sales_order_items
for each row execute function private.prevent_commercial_line_reparent();
create trigger invoice_items_parent_immutable
before update on public.invoice_items
for each row execute function private.prevent_commercial_line_reparent();

-- Internal function permissions. Existing stock operations remain the only
-- public entry points for manual receipts, adjustments, reservations and transfers.
revoke all on function private.guard_stock_movement_immutable() from public,anon,authenticated;
revoke all on function private.recalculate_commercial_document_totals() from public,anon,authenticated;
revoke all on function private.prevent_commercial_line_reparent() from public,anon,authenticated;
revoke all on function private.post_goods_receipt_impl(uuid,uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.post_goods_receipt_impl(uuid,uuid) to authenticated;

revoke all on function public.post_goods_receipt(uuid,uuid) from public,anon;
revoke all on function public.convert_accepted_quotation_to_order(uuid,uuid,text) from public,anon;
revoke all on function public.create_invoice_from_sales_order(uuid,uuid,text,date) from public,anon;
grant execute on function public.post_goods_receipt(uuid,uuid) to authenticated;
grant execute on function public.convert_accepted_quotation_to_order(uuid,uuid,text) to authenticated;
grant execute on function public.create_invoice_from_sales_order(uuid,uuid,text,date) to authenticated;
