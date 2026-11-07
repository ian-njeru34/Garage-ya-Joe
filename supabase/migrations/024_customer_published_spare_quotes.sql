-- Customer receives only owner-published spare prices, never dealer quote details.
create or replace function public.customer_published_spare_quotes()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_customer public.customers%rowtype; v_result jsonb;
begin
  select * into v_customer
  from public.customers
  where profile_id=(select auth.uid())
  order by created_at asc
  limit 1;
  if not found then
    raise exception 'Customer profile not found' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'part_name',r.part_name,
    'part_number',r.part_number,
    'quantity',r.quantity,
    'status',r.status,
    'unit_price_kes',r.customer_unit_price_kes,
    'shipping_kes',r.customer_shipping_kes,
    'total_kes',r.customer_total_kes,
    'published_at',r.customer_quote_published_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_result
  from public.spare_requests r
  where r.business_id=v_customer.business_id
    and r.customer_id=v_customer.id
    and r.customer_quote_published_at is not null;
  return v_result;
end;
$$;
revoke all on function public.customer_published_spare_quotes() from public,anon;
grant execute on function public.customer_published_spare_quotes() to authenticated;
