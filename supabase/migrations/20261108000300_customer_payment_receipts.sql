alter table public.customer_payments
  add column if not exists receipt_share_token uuid not null default gen_random_uuid();
create unique index if not exists customer_payments_receipt_share_token_uidx
  on public.customer_payments(receipt_share_token);

create or replace function public.get_customer_payment_receipt_by_token(p_token uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'payment',jsonb_build_object(
      'id',p.id,'payment_number',p.payment_number,'payment_date',p.payment_date,
      'payment_method',p.payment_method,'currency_code',p.currency_code,
      'amount',p.amount,'amount_kes',p.amount_kes,'external_reference',p.external_reference,
      'notes',p.notes,'status',p.status
    ),
    'business',jsonb_build_object('name',b.name,'legal_name',b.legal_name),
    'customer',jsonb_build_object('name',c.display_name,'phone',c.phone),
    'invoice',case when i.id is null then null else jsonb_build_object(
      'invoice_number',i.invoice_number,'currency_code',i.currency_code,
      'total_amount',i.total_amount,'amount_paid',i.amount_paid,
      'balance',greatest(i.total_amount-i.amount_paid,0)
    ) end
  )
  from public.customer_payments p
  join public.businesses b on b.id=p.business_id
  join public.customers c on c.id=p.customer_id and c.business_id=p.business_id
  left join public.invoices i on i.id=p.invoice_id and i.business_id=p.business_id
  where p.receipt_share_token=p_token and p.status='recorded'
  limit 1;
$$;
revoke all on function public.get_customer_payment_receipt_by_token(uuid) from public;
grant execute on function public.get_customer_payment_receipt_by_token(uuid) to anon,authenticated;
