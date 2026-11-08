-- Ensure matched receipts belong to the same PO and aggregate duplicate bill lines before comparing quantities.
create or replace function public.owner_approve_supplier_bill(p_business_id uuid,p_supplier_bill_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_bill public.supplier_bills%rowtype; v_period uuid; v_period_status text; v_ap uuid; v_journal uuid; v_line record; v_no integer:=0;
 v_po public.purchase_orders%rowtype; v_po_item public.purchase_order_items%rowtype; v_received numeric(18,4); v_previously_billed numeric(18,4); v_bill_qty numeric(18,4);
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
    where gri.business_id=p_business_id and gri.purchase_order_item_id=v_line.purchase_order_item_id and gr.purchase_order_id=v_po.id and gr.status='posted' and gri.condition_status='good';
   select coalesce(sum(sbl.quantity),0) into v_previously_billed
    from public.supplier_bill_lines sbl join public.supplier_bills sb on sb.business_id=sbl.business_id and sb.id=sbl.supplier_bill_id
    where sbl.business_id=p_business_id and sbl.purchase_order_item_id=v_line.purchase_order_item_id and sb.id<>v_bill.id and sb.status in ('approved','partially_paid','paid');
   select coalesce(sum(quantity),0) into v_bill_qty from public.supplier_bill_lines where business_id=p_business_id and supplier_bill_id=v_bill.id and purchase_order_item_id=v_line.purchase_order_item_id;
   if v_bill_qty>v_received-v_previously_billed+0.0001 then
    raise exception 'Three-way match failed: invoice quantity % exceeds received good quantity available (%) for order item %',v_bill_qty,greatest(0,v_received-v_previously_billed),v_po_item.line_description;
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
