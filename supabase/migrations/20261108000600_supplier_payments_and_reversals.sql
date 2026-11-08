create or replace function public.owner_record_supplier_payment(
  p_business_id uuid,p_location_id uuid,p_supplier_id uuid,p_cash_account_id uuid,
  p_payment_number text,p_payment_date date,p_amount numeric,p_exchange_rate_to_kes numeric,
  p_external_reference text default null,p_notes text default null,p_purchase_order_id uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
 v_uid uuid:=auth.uid(); v_supplier public.suppliers%rowtype; v_cash public.cash_accounts%rowtype;
 v_payment_id uuid:=gen_random_uuid(); v_period_id uuid; v_period_status text;
 v_ap_account uuid; v_cash_ledger uuid; v_journal_id uuid; v_method text; v_kes numeric(18,2);
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if nullif(btrim(p_payment_number),'') is null then raise exception 'Payment number is required'; end if;
 if p_amount is null or p_amount<=0 or p_amount>1000000000 then raise exception 'Enter a valid positive payment amount'; end if;
 if p_exchange_rate_to_kes is null or p_exchange_rate_to_kes<=0 then raise exception 'Enter a valid exchange rate to KES'; end if;
 if not private.has_business_permission(p_business_id,'payments.record',p_location_id)
  and not private.has_business_permission(p_business_id,'procurement.manage',p_location_id)
  and not private.has_business_permission(p_business_id,'finance.manage',p_location_id) then
  raise exception 'Supplier payment permission required' using errcode='42501';
 end if;
 select * into v_supplier from public.suppliers where business_id=p_business_id and id=p_supplier_id and is_active;
 if not found then raise exception 'Active supplier not found'; end if;
 select * into v_cash from public.cash_accounts where business_id=p_business_id and id=p_cash_account_id and is_active for share;
 if not found then raise exception 'Select an active receiving account'; end if;
 if v_cash.location_id<>p_location_id then raise exception 'Receiving account must belong to the selected branch'; end if;
 if p_purchase_order_id is not null and not exists(select 1 from public.purchase_orders po where po.business_id=p_business_id and po.id=p_purchase_order_id and po.supplier_id=p_supplier_id) then
  raise exception 'Purchase order does not belong to this supplier'; end if;
 v_method:=case v_cash.account_type when 'cash' then 'cash' when 'bank' then 'bank_transfer' when 'mobile_money' then 'mobile_money' when 'card_clearing' then 'card' else 'other' end;
 v_kes:=round(p_amount*p_exchange_rate_to_kes,2);
 insert into public.supplier_payments(id,business_id,location_id,supplier_id,purchase_order_id,cash_account_id,payment_number,payment_date,payment_method,currency_code,exchange_rate_to_kes,amount,amount_kes,external_reference,status,notes,paid_by)
 values(v_payment_id,p_business_id,p_location_id,p_supplier_id,p_purchase_order_id,p_cash_account_id,btrim(p_payment_number),coalesce(p_payment_date,current_date),v_method,v_cash.currency_code,p_exchange_rate_to_kes,p_amount,v_kes,nullif(btrim(coalesce(p_external_reference,'')),''),'recorded',nullif(btrim(coalesce(p_notes,'')),''),v_uid);
 if private.has_business_permission(p_business_id,'finance.manage',p_location_id) then
  select id into v_cash_ledger from public.chart_of_accounts where business_id=p_business_id and id=v_cash.ledger_account_id and account_type='asset' and is_active;
  select id into v_ap_account from public.chart_of_accounts where business_id=p_business_id and account_code='2000' and account_type='liability' and is_control_account and is_active;
  select id,status into v_period_id,v_period_status from public.accounting_periods where business_id=p_business_id and coalesce(p_payment_date,current_date) between starts_on and ends_on order by starts_on desc limit 1;
  if v_cash_ledger is not null and v_ap_account is not null and v_period_id is not null and v_period_status='open' then
   insert into public.journal_entries(business_id,location_id,accounting_period_id,entry_number,entry_date,description,source_type,source_id,currency_code,exchange_rate_to_kes,status,created_by)
   values(p_business_id,p_location_id,v_period_id,'SUP-'||btrim(p_payment_number),coalesce(p_payment_date,current_date),'Supplier payment '||btrim(p_payment_number)||' to '||v_supplier.supplier_name,'supplier_payment',v_payment_id,v_cash.currency_code,p_exchange_rate_to_kes,'draft',v_uid) returning id into v_journal_id;
   insert into public.journal_lines(business_id,journal_entry_id,line_number,account_id,description,currency_code,exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes)
   values(p_business_id,v_journal_id,1,v_ap_account,'Reduce accounts payable to '||v_supplier.supplier_name,v_cash.currency_code,p_exchange_rate_to_kes,p_amount,0,v_kes,0),
         (p_business_id,v_journal_id,2,v_cash_ledger,'Supplier payment from '||v_cash.account_name,v_cash.currency_code,p_exchange_rate_to_kes,0,p_amount,0,v_kes);
   perform private.post_journal_entry_impl(p_business_id,v_journal_id);
   update public.supplier_payments set journal_entry_id=v_journal_id where business_id=p_business_id and id=v_payment_id;
  end if;
 end if;
 return v_payment_id;
end; $$;
revoke all on function public.owner_record_supplier_payment(uuid,uuid,uuid,uuid,text,date,numeric,numeric,text,text,uuid) from public,anon;
grant execute on function public.owner_record_supplier_payment(uuid,uuid,uuid,uuid,text,date,numeric,numeric,text,text,uuid) to authenticated;

create or replace function public.owner_reverse_supplier_payment(p_business_id uuid,p_payment_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_payment public.supplier_payments%rowtype; v_reversal uuid;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_payment from public.supplier_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Supplier payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_payment.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_payment.status<>'recorded' then raise exception 'Only recorded supplier payments can be reversed'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 if v_payment.journal_entry_id is not null then
  v_reversal:=private.reverse_journal_entry_impl(p_business_id,v_payment.journal_entry_id,p_reversal_number,coalesce(p_reversal_date,current_date),p_reason);
  perform private.post_journal_entry_impl(p_business_id,v_reversal);
 end if;
 update public.supplier_payments set status='reversed' where business_id=p_business_id and id=p_payment_id;
 return v_reversal;
end; $$;
revoke all on function public.owner_reverse_supplier_payment(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.owner_reverse_supplier_payment(uuid,uuid,text,date,text) to authenticated;

create or replace function public.owner_reverse_customer_payment(p_business_id uuid,p_payment_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_payment public.customer_payments%rowtype; v_invoice public.invoices%rowtype;
 v_reversal uuid; v_new_paid numeric(18,2); v_new_paid_kes numeric(18,2); v_status text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_payment from public.customer_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Customer payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_payment.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_payment.status<>'recorded' then raise exception 'Only recorded customer payments can be reversed'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 if v_payment.invoice_id is not null then
  select * into v_invoice from public.invoices where business_id=p_business_id and id=v_payment.invoice_id for update;
  if not found then raise exception 'Linked invoice not found'; end if;
  v_new_paid:=v_invoice.amount_paid-v_payment.amount; v_new_paid_kes:=v_invoice.amount_paid_kes-v_payment.amount_kes;
  if v_new_paid<0 or v_new_paid_kes<0 then raise exception 'Invoice payment totals are inconsistent; reversal stopped'; end if;
  v_status:=case when v_new_paid<=0 then case when v_invoice.due_date is not null and v_invoice.due_date<coalesce(p_reversal_date,current_date) then 'overdue' else 'issued' end
   when v_invoice.due_date is not null and v_invoice.due_date<coalesce(p_reversal_date,current_date) then 'overdue' else 'partially_paid' end;
  update public.invoices set amount_paid=v_new_paid,amount_paid_kes=v_new_paid_kes,status=v_status,
   paid_at=case when v_new_paid<=0 then null else paid_at end,updated_at=now(),updated_by=v_uid
   where business_id=p_business_id and id=v_payment.invoice_id;
 end if;
 if v_payment.journal_entry_id is not null then
  v_reversal:=private.reverse_journal_entry_impl(p_business_id,v_payment.journal_entry_id,p_reversal_number,coalesce(p_reversal_date,current_date),p_reason);
  perform private.post_journal_entry_impl(p_business_id,v_reversal);
 end if;
 update public.customer_payments set status='reversed' where business_id=p_business_id and id=p_payment_id;
 return v_reversal;
end; $$;
revoke all on function public.owner_reverse_customer_payment(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.owner_reverse_customer_payment(uuid,uuid,text,date,text) to authenticated;
