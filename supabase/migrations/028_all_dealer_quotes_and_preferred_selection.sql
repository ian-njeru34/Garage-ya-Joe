-- Every dealer in a garage may quote every spare request. Each dealer keeps
-- one editable/current offer per request; the owner selects the preferred offer.
create unique index if not exists spare_request_responses_one_current_quote
  on public.spare_request_responses(spare_request_id,dealer_profile_id);

alter table public.owner_spare_pricing
  add column if not exists selected_response_id uuid
    references public.spare_request_responses(id) on delete restrict;

create or replace function public.customer_published_spare_quotes()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  select * into v_customer from public.customers
  where profile_id=(select auth.uid()) order by created_at asc limit 1;
  if not found then
    raise exception 'Customer profile not found' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'part_name',r.part_name,'part_number',r.part_number,'quantity',r.quantity,
    'status',r.status,'unit_price_kes',p.customer_unit_price_kes,
    'shipping_kes',p.customer_shipping_kes,'total_kes',p.customer_total_kes,
    'published_at',p.published_at
  ) order by r.created_at desc),'[]'::jsonb) into v_result
  from public.spare_requests r
  join public.owner_spare_pricing p
    on p.business_id=r.business_id and p.spare_request_id=r.id
  join public.spare_request_responses selected
    on selected.id=p.selected_response_id and selected.business_id=r.business_id
    and selected.spare_request_id=r.id
  where r.business_id=v_customer.business_id and r.customer_id=v_customer.id
    and p.selected_response_id is not null;
  return v_result;
end; $$;
revoke all on function public.customer_published_spare_quotes() from public,anon;
grant execute on function public.customer_published_spare_quotes() to authenticated;
