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
  v_cash_ledger uuid;
  v_ar_account uuid;
  v_period_id uuid;
  v_period_status text;
  v_journal_id uuid;
  v_payment_date date := coalesce(p_payment_date,current_date);
  v_amount_kes numeric(18,2);
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
  elsif v_invoice.due_date is not null and v_invoice.due_date < v_payment_date then v_new_status := 'overdue';
  else v_new_status := 'partially_paid'; end if;
  v_amount_kes := round(p_amount*v_invoice.exchange_rate_to_kes,2);

  insert into public.customer_payments(
    id,business_id,location_id,customer_id,invoice_id,cash_account_id,payment_number,
    payment_date,payment_method,currency_code,exchange_rate_to_kes,amount,amount_kes,
    external_reference,status,notes,received_by
  ) values (
    v_payment_id,p_business_id,v_invoice.location_id,v_invoice.customer_id,v_invoice.id,
    p_cash_account_id,btrim(p_payment_number),v_payment_date,
    p_payment_method,v_invoice.currency_code,v_invoice.exchange_rate_to_kes,p_amount,
    v_amount_kes,nullif(btrim(coalesce(p_external_reference,'')),''),
    'recorded',nullif(btrim(coalesce(p_notes,'')),''),v_uid
  );

  -- Post a balanced cash/bank/mobile-money debit against accounts receivable when
  -- the owner has completed the ledger setup and the payment date falls in an open period.
  if private.has_business_permission(p_business_id,'finance.manage',v_invoice.location_id) then
    select id into v_cash_ledger from public.chart_of_accounts
    where business_id=p_business_id and id=v_cash.ledger_account_id
      and account_type='asset' and is_active;
    select id into v_ar_account from public.chart_of_accounts
    where business_id=p_business_id and account_code='1100'
      and account_type='asset' and is_control_account and is_active;
    select id,status into v_period_id,v_period_status from public.accounting_periods
    where business_id=p_business_id and v_payment_date between starts_on and ends_on
    order by starts_on desc limit 1;
    if v_cash_ledger is not null and v_ar_account is not null and v_period_id is not null and v_period_status='open' then
      insert into public.journal_entries(
        business_id,location_id,accounting_period_id,entry_number,entry_date,description,
        source_type,source_id,currency_code,exchange_rate_to_kes,status,created_by
      ) values (
        p_business_id,v_invoice.location_id,v_period_id,'PAY-'||btrim(p_payment_number),
        v_payment_date,'Customer payment '||btrim(p_payment_number)||' for invoice '||v_invoice.invoice_number,
        'customer_payment',v_payment_id,v_invoice.currency_code,v_invoice.exchange_rate_to_kes,'draft',v_uid
      ) returning id into v_journal_id;
      insert into public.journal_lines(
        business_id,journal_entry_id,line_number,account_id,description,currency_code,
        exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes
      ) values
        (p_business_id,v_journal_id,1,v_cash_ledger,'Payment received into '||v_cash.account_name,
         v_invoice.currency_code,v_invoice.exchange_rate_to_kes,p_amount,0,v_amount_kes,0),
        (p_business_id,v_journal_id,2,v_ar_account,'Reduce customer accounts receivable',
         v_invoice.currency_code,v_invoice.exchange_rate_to_kes,0,p_amount,0,v_amount_kes);
      perform private.post_journal_entry_impl(p_business_id,v_journal_id);
      update public.customer_payments set journal_entry_id=v_journal_id
      where business_id=p_business_id and id=v_payment_id;
    end if;
  end if;

  update public.invoices set amount_paid=v_paid,amount_paid_kes=v_paid_kes,status=v_new_status,
    paid_at=case when v_new_status='paid' then now() else paid_at end,
    updated_at=now(),updated_by=v_uid
  where business_id=p_business_id and id=p_invoice_id;
  return v_payment_id;
end;
$$;
revoke all on function public.owner_record_invoice_payment(uuid,uuid,uuid,text,date,text,numeric,text,text) from public,anon;
grant execute on function public.owner_record_invoice_payment(uuid,uuid,uuid,text,date,text,numeric,text,text) to authenticated;
