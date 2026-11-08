alter table public.invoices add column if not exists receipt_share_token uuid unique;

create or replace function public.owner_issue_invoice(
  p_business_id uuid,
  p_invoice_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice public.invoices%rowtype;
  v_uid uuid := auth.uid();
  v_token uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into v_invoice from public.invoices
  where business_id=p_business_id and id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not private.has_business_permission(p_business_id,'sales.manage',v_invoice.location_id) then
    raise exception 'Sales management permission required' using errcode='42501';
  end if;
  if v_invoice.status <> 'draft' then raise exception 'Only draft invoices can be issued'; end if;
  if v_invoice.total_kes <= 0 or not exists (
    select 1 from public.invoice_items where business_id=p_business_id and invoice_id=p_invoice_id
  ) then raise exception 'Invoice needs at least one priced line before issuing'; end if;
  update public.invoices
  set status='issued',issued_at=now(),updated_at=now(),updated_by=v_uid,receipt_share_token=v_token
  where business_id=p_business_id and id=p_invoice_id;
  return v_token;
end;
$$;

create or replace function public.owner_record_invoice_payment(
  p_business_id uuid,
  p_invoice_id uuid,
  p_cash_account_id uuid,
  p_payment_number text,
  p_payment_date date,
  p_payment_method text,
  p_amount numeric,
  p_external_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice public.invoices%rowtype;
  v_cash public.cash_accounts%rowtype;
  v_uid uuid := auth.uid();
  v_paid numeric(18,2);
  v_paid_kes numeric(18,2);
  v_remaining numeric(18,2);
  v_payment_id uuid := gen_random_uuid();
  v_new_status text;
  v_expected_account text;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if nullif(btrim(p_payment_number),'') is null then raise exception 'Payment number is required'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000 then raise exception 'Enter a valid positive payment amount'; end if;
  if p_payment_method not in ('cash','bank_transfer','card','mobile_money','cheque','other') then
    raise exception 'Unsupported payment method';
  end if;
  select * into v_invoice from public.invoices
  where business_id=p_business_id and id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not private.has_business_permission(p_business_id,'payments.record',v_invoice.location_id)
     and not private.has_business_permission(p_business_id,'finance.manage',v_invoice.location_id) then
    raise exception 'Payment recording permission required' using errcode='42501';
  end if;
  if v_invoice.status not in ('issued','partially_paid','overdue') then
    raise exception 'Only issued invoices can receive payments';
  end if;
  select * into v_cash from public.cash_accounts
  where business_id=p_business_id and id=p_cash_account_id for share;
  if not found or not v_cash.is_active then raise exception 'Select an active cash, bank or mobile-money account'; end if;
  if v_cash.location_id <> v_invoice.location_id then raise exception 'Cash account must belong to the invoice location'; end if;
  if v_cash.currency_code <> v_invoice.currency_code then raise exception 'Cash account currency must match the invoice currency'; end if;
  v_expected_account := case
    when p_payment_method='cash' then 'cash'
    when p_payment_method='bank_transfer' then 'bank'
    when p_payment_method='card' then 'card_clearing'
    when p_payment_method='mobile_money' then 'mobile_money'
    when p_payment_method='cheque' then 'bank'
    else v_cash.account_type end;
  if v_cash.account_type <> v_expected_account then
    raise exception 'The selected receiving account does not match the payment method';
  end if;
  v_paid := v_invoice.amount_paid + p_amount;
  v_paid_kes := v_invoice.amount_paid_kes + round(p_amount*v_invoice.exchange_rate_to_kes,2);
  v_remaining := v_invoice.total_amount - v_invoice.amount_paid;
  if p_amount > v_remaining then raise exception 'Payment exceeds outstanding balance of %',round(v_remaining,2); end if;
  if v_paid >= v_invoice.total_amount then v_new_status := 'paid';
  elsif v_invoice.due_date is not null and v_invoice.due_date < coalesce(p_payment_date,current_date) then v_new_status := 'overdue';
  else v_new_status := 'partially_paid'; end if;

  insert into public.customer_payments(
    id,business_id,location_id,customer_id,invoice_id,cash_account_id,payment_number,
    payment_date,payment_method,currency_code,exchange_rate_to_kes,amount,amount_kes,
    external_reference,status,notes,received_by
  ) values (
    v_payment_id,p_business_id,v_invoice.location_id,v_invoice.customer_id,v_invoice.id,
    p_cash_account_id,btrim(p_payment_number),coalesce(p_payment_date,current_date),
    p_payment_method,v_invoice.currency_code,v_invoice.exchange_rate_to_kes,p_amount,
    round(p_amount*v_invoice.exchange_rate_to_kes,2),nullif(btrim(coalesce(p_external_reference,'')),''),
    'recorded',nullif(btrim(coalesce(p_notes,'')),''),v_uid
  );
  update public.invoices set amount_paid=v_paid,amount_paid_kes=v_paid_kes,status=v_new_status,
    paid_at=case when v_new_status='paid' then now() else paid_at end,
    updated_at=now(),updated_by=v_uid
  where business_id=p_business_id and id=p_invoice_id;
  return v_payment_id;
end;
$$;

create or replace function public.get_invoice_receipt_by_token(p_token uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'invoice',jsonb_build_object(
      'id',i.id,'invoice_number',i.invoice_number,'status',i.status,'currency_code',i.currency_code,
      'subtotal_amount',i.subtotal_amount,'discount_amount',i.discount_amount,'tax_amount',i.tax_amount,
      'total_amount',i.total_amount,'amount_paid',i.amount_paid,'due_date',i.due_date,
      'issued_at',i.issued_at,'customer_notes',i.customer_notes
    ),
    'business',jsonb_build_object('name',b.name,'legal_name',b.legal_name),
    'customer',jsonb_build_object('name',c.display_name,'phone',c.phone),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'description',ii.description,'quantity',ii.quantity,'unit_of_measure',ii.unit_of_measure,
      'unit_price',ii.unit_price,'line_total',ii.line_total
    ) order by ii.line_number) from public.invoice_items ii
      where ii.business_id=i.business_id and ii.invoice_id=i.id),'[]'::jsonb)
  )
  from public.invoices i
  join public.businesses b on b.id=i.business_id
  join public.customers c on c.id=i.customer_id and c.business_id=i.business_id
  where i.receipt_share_token=p_token and i.status in ('issued','partially_paid','paid','overdue')
  limit 1;
$$;

revoke all on function public.owner_issue_invoice(uuid,uuid) from public,anon;
revoke all on function public.owner_record_invoice_payment(uuid,uuid,uuid,text,date,text,numeric,text,text) from public,anon;
grant execute on function public.owner_issue_invoice(uuid,uuid) to authenticated;
grant execute on function public.owner_record_invoice_payment(uuid,uuid,uuid,text,date,text,numeric,text,text) to authenticated;
revoke all on function public.get_invoice_receipt_by_token(uuid) from public;
grant execute on function public.get_invoice_receipt_by_token(uuid) to anon,authenticated;
