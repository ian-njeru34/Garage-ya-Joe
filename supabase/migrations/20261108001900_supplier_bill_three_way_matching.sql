-- Supplier bill line-level three-way matching against purchase orders and posted goods receipts.
alter table public.supplier_bill_lines
 add column if not exists purchase_order_item_id uuid,
 add column if not exists quantity numeric(18,4) not null default 1,
 add column if not exists unit_price numeric(18,4) not null default 0;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='supplier_bill_lines_po_item_fk') then
  alter table public.supplier_bill_lines add constraint supplier_bill_lines_po_item_fk
   foreign key(business_id,purchase_order_item_id) references public.purchase_order_items(business_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='supplier_bill_lines_quantity_check') then
  alter table public.supplier_bill_lines add constraint supplier_bill_lines_quantity_check check(quantity>0);
 end if;
 if not exists(select 1 from pg_constraint where conname='supplier_bill_lines_unit_price_check') then
  alter table public.supplier_bill_lines add constraint supplier_bill_lines_unit_price_check check(unit_price>=0);
 end if;
end $$;
create index if not exists supplier_bill_lines_po_item_idx on public.supplier_bill_lines(business_id,purchase_order_item_id) where purchase_order_item_id is not null;

create or replace function public.owner_create_supplier_bill(
 p_business_id uuid,p_location_id uuid,p_supplier_id uuid,p_purchase_order_id uuid,
 p_supplier_invoice_number text,p_bill_date date,p_due_date date,p_currency_code char(3),
 p_exchange_rate_to_kes numeric,p_total_amount numeric,p_total_kes numeric,p_notes text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_line jsonb; v_no integer:=0; v_sum numeric(18,2):=0; v_original_sum numeric(18,2):=0;
 v_supplier public.suppliers%rowtype; v_loc public.locations%rowtype; v_po public.purchase_orders%rowtype; v_po_item public.purchase_order_items%rowtype;
 v_qty numeric(18,4); v_price numeric(18,4); v_po_item_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'procurement.manage',p_location_id) and not private.has_business_permission(p_business_id,'finance.manage',p_location_id) then raise exception 'Supplier bill entry permission required' using errcode='42501'; end if;
 if nullif(btrim(p_supplier_invoice_number),'') is null then raise exception 'Supplier invoice number is required'; end if;
 if p_total_amount is null or p_total_amount<=0 or p_total_kes is null or p_total_kes<=0 or p_exchange_rate_to_kes is null or p_exchange_rate_to_kes<=0 then raise exception 'Enter valid positive bill totals and exchange rate'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one bill line is required'; end if;
 select * into v_supplier from public.suppliers where business_id=p_business_id and id=p_supplier_id and is_active;
 if not found then raise exception 'Active supplier not found'; end if;
 select * into v_loc from public.locations where business_id=p_business_id and id=p_location_id and is_active;
 if not found then raise exception 'Active branch not found'; end if;
 if p_purchase_order_id is not null then
  select * into v_po from public.purchase_orders where business_id=p_business_id and id=p_purchase_order_id and supplier_id=p_supplier_id and location_id=p_location_id for update;
  if not found then raise exception 'Purchase order must belong to the selected supplier and branch'; end if;
  if v_po.status in ('draft','cancelled') then raise exception 'Only submitted purchase orders can be invoiced'; end if;
  if v_po.currency_code<>p_currency_code then raise exception 'Supplier bill currency must match the purchase order currency'; end if;
 end if;
 insert into public.supplier_bills(id,business_id,location_id,supplier_id,purchase_order_id,supplier_invoice_number,bill_date,due_date,currency_code,exchange_rate_to_kes,total_amount,total_kes,subtotal_amount,notes,created_by)
 values(v_id,p_business_id,p_location_id,p_supplier_id,p_purchase_order_id,btrim(p_supplier_invoice_number),coalesce(p_bill_date,current_date),p_due_date,p_currency_code,p_exchange_rate_to_kes,p_total_amount,p_total_kes,p_total_amount,nullif(btrim(coalesce(p_notes,'')),''),v_uid);
 for v_line in select value from jsonb_array_elements(p_lines) loop
  v_no:=v_no+1;
  if coalesce((v_line->>'amount')::numeric,0)<=0 or coalesce((v_line->>'amount_kes')::numeric,0)<=0 then raise exception 'Bill line amounts must be positive'; end if;
  if not exists(select 1 from public.chart_of_accounts a where a.business_id=p_business_id and a.id=(v_line->>'account_id')::uuid and a.is_active and a.account_type in ('asset','expense')) then raise exception 'Each bill line must use an active asset or expense account'; end if;
  v_po_item_id:=nullif(v_line->>'purchase_order_item_id','')::uuid;
  v_qty:=coalesce(nullif(v_line->>'quantity','')::numeric,1);
  v_price:=coalesce(nullif(v_line->>'unit_price','')::numeric,(v_line->>'amount')::numeric);
  if v_qty<=0 or v_price<0 then raise exception 'Enter a valid invoice quantity and unit price'; end if;
  if p_purchase_order_id is not null then
   if v_po_item_id is null then raise exception 'Every invoice line linked to a purchase order must select its matching order item'; end if;
   select * into v_po_item from public.purchase_order_items where business_id=p_business_id and id=v_po_item_id and purchase_order_id=p_purchase_order_id for update;
   if not found then raise exception 'Selected purchase order item does not belong to this purchase order'; end if;
   if v_po_item.currency_code<>p_currency_code then raise exception 'Purchase order item currency does not match supplier bill currency'; end if;
  elsif v_po_item_id is not null then raise exception 'Select a purchase order before mapping order items'; end if;
  insert into public.supplier_bill_lines(business_id,supplier_bill_id,line_number,account_id,description,amount,amount_kes,purchase_order_item_id,quantity,unit_price)
  values(p_business_id,v_id,v_no,(v_line->>'account_id')::uuid,coalesce(nullif(btrim(v_line->>'description'),''),'Supplier bill line'),(v_line->>'amount')::numeric,(v_line->>'amount_kes')::numeric,v_po_item_id,v_qty,v_price);
  v_sum:=v_sum+(v_line->>'amount_kes')::numeric;
  v_original_sum:=v_original_sum+(v_line->>'amount')::numeric;
 end loop;
 if abs(v_sum-p_total_kes)>0.01 then raise exception 'Bill line KES total (%) does not equal bill total (%)',v_sum,p_total_kes; end if;
 if abs(v_original_sum-p_total_amount)>0.01 then raise exception 'Bill line currency total (%) does not equal bill total (%)',v_original_sum,p_total_amount; end if;
 return v_id;
end; $$;
revoke all on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) to authenticated;

create or replace function public.owner_approve_supplier_bill(p_business_id uuid,p_supplier_bill_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_bill public.supplier_bills%rowtype; v_period uuid; v_period_status text; v_ap uuid; v_journal uuid; v_line record; v_no integer:=0;
 v_po public.purchase_orders%rowtype; v_po_item public.purchase_order_items%rowtype; v_received numeric(18,4); v_previously_billed numeric(18,4);
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_bill from public.supplier_bills where business_id=p_business_id and id=p_supplier_bill_id for update;
 if not found then raise exception 'Supplier bill not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_bill.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_bill.status<>'draft' then raise exception 'Only draft supplier bills can be approved'; end if;
 if v_bill.purchase_order_id is not null then
  select * into v_po from public.purchase_orders where business_id=p_business_id and id=v_bill.purchase_order_id for update;
  if not found or v_po.supplier_id<>v_bill.supplier_id or v_po.location_id<>v_bill.location_id then raise exception 'Linked purchase order is invalid for this supplier bill'; end if;
  if v_po.status in ('draft','cancelled') then raise exception 'Linked purchase order is not eligible for invoicing'; end if;
  for v_line in select * from public.supplier_bill_lines where business_id=p_business_id and supplier_bill_id=v_bill.id order by line_number loop
   if v_line.purchase_order_item_id is null then raise exception 'Three-way match failed: invoice line % is not mapped to a purchase order item',v_line.line_number; end if;
   select * into v_po_item from public.purchase_order_items where business_id=p_business_id and id=v_line.purchase_order_item_id and purchase_order_id=v_po.id for update;
   if not found then raise exception 'Three-way match failed: invoice line % references an invalid order item',v_line.line_number; end if;
   if abs(v_line.unit_price-v_po_item.unit_price)>0.01 then raise exception 'Three-way match failed: invoice line % unit price differs from the purchase order',v_line.line_number; end if;
   select coalesce(sum(gri.received_quantity),0) into v_received
    from public.goods_receipt_items gri join public.goods_receipts gr on gr.business_id=gri.business_id and gr.id=gri.goods_receipt_id
    where gri.business_id=p_business_id and gri.purchase_order_item_id=v_line.purchase_order_item_id and gr.status='posted' and gri.condition_status='good';
   select coalesce(sum(sbl.quantity),0) into v_previously_billed
    from public.supplier_bill_lines sbl join public.supplier_bills sb on sb.business_id=sbl.business_id and sb.id=sbl.supplier_bill_id
    where sbl.business_id=p_business_id and sbl.purchase_order_item_id=v_line.purchase_order_item_id and sb.id<>v_bill.id and sb.status in ('approved','partially_paid','paid');
   if v_line.quantity>v_received-v_previously_billed+0.0001 then
    raise exception 'Three-way match failed: invoice quantity % exceeds received good quantity available (%) for order item %',v_line.quantity,greatest(0,v_received-v_previously_billed),v_po_item.line_description;
   end if;
  end loop;
 end if;
 select id,status into v_period,v_period_status from public.accounting_periods where business_id=p_business_id and v_bill.bill_date between starts_on and ends_on order by starts_on desc limit 1;
 if v_period is null or v_period_status<>'open' then raise exception 'No open accounting period covers the supplier bill date'; end if;
 select id into v_ap from public.chart_of_accounts where business_id=p_business_id and account_code='2000' and account_type='liability' and is_control_account and is_active;
 if v_ap is null then raise exception 'Accounts payable control account is not configured'; end if;
 v_journal:=gen_random_uuid();
 insert into public.journal_entries(id,business_id,location_id,accounting_period_id,entry_number,entry_date,description,source_type,source_id,currency_code,exchange_rate_to_kes,status,created_by)
 values(v_journal,p_business_id,v_bill.location_id,v_period,'BILL-'||left(replace(v_bill.supplier_invoice_number,' ',''),24)||'-'||left(replace(v_bill.id::text,'-',''),8),v_bill.bill_date,'Supplier bill '||v_bill.supplier_invoice_number,'supplier_bill',v_bill.id,v_bill.currency_code,v_bill.exchange_rate_to_kes,'draft',v_uid);
 for v_line in select * from public.supplier_bill_lines where business_id=p_business_id and supplier_bill_id=v_bill.id order by line_number loop
  v_no:=v_no+1;
  insert into public.journal_lines(business_id,journal_entry_id,line_number,account_id,description,currency_code,exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes)
  values(p_business_id,v_journal,v_no,v_line.account_id,v_line.description,v_bill.currency_code,v_bill.exchange_rate_to_kes,v_line.amount,0,v_line.amount_kes,0);
 end loop;
 insert into public.journal_lines(business_id,journal_entry_id,line_number,account_id,description,currency_code,exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes)
 values(p_business_id,v_journal,v_no+1,v_ap,'Accounts payable · supplier bill '||v_bill.supplier_invoice_number,v_bill.currency_code,v_bill.exchange_rate_to_kes,0,v_bill.total_amount,0,v_bill.total_kes);
 perform private.post_journal_entry_impl(p_business_id,v_journal);
 update public.supplier_bills set status='approved',journal_entry_id=v_journal,approved_by=v_uid,approved_at=now(),updated_at=now() where business_id=p_business_id and id=v_bill.id;
 return v_journal;
end; $$;
revoke all on function public.owner_approve_supplier_bill(uuid,uuid) from public,anon;
grant execute on function public.owner_approve_supplier_bill(uuid,uuid) to authenticated;
