-- Integrity for owner-published dealer offers.
-- A selected response must belong to the same garage and spare request.
alter table public.spare_request_responses
  add constraint spare_request_responses_business_request_id_key
  unique (business_id, spare_request_id, id);

alter table public.owner_spare_pricing
  drop constraint if exists owner_spare_pricing_selected_response_id_fkey;

alter table public.owner_spare_pricing
  add constraint owner_spare_pricing_selected_response_same_request_fkey
  foreign key (business_id, spare_request_id, selected_response_id)
  references public.spare_request_responses (business_id, spare_request_id, id)
  on delete restrict;

-- Enforce the published customer total against the spare request quantity.
create or replace function public.enforce_owner_spare_price_total()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_quantity numeric;
begin
  select r.quantity into v_quantity
  from public.spare_requests r
  where r.id = new.spare_request_id
    and r.business_id = new.business_id;

  if not found then
    raise exception 'Spare request not found for this garage.';
  end if;

  if new.customer_unit_price_kes < 0
     or new.customer_shipping_kes < 0
     or new.markup_percent < 0
     or new.markup_fixed_kes < 0 then
    raise exception 'Prices and markups cannot be negative.';
  end if;

  if new.customer_total_kes <> round((new.customer_unit_price_kes * v_quantity) + new.customer_shipping_kes, 2) then
    raise exception 'Customer total must equal marked-up unit price multiplied by quantity plus shipping.';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_owner_spare_price_total
  on public.owner_spare_pricing;
create trigger enforce_owner_spare_price_total
before insert or update on public.owner_spare_pricing
for each row execute function public.enforce_owner_spare_price_total();

-- If a dealer changes the selected offer's price, availability or delivery,
-- withdraw that publication. The owner must review and publish it again.
create or replace function public.invalidate_published_spare_offer_on_dealer_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_invalidated integer;
begin
  if new.quoted_unit_price is distinct from old.quoted_unit_price
     or new.estimated_shipping_kes is distinct from old.estimated_shipping_kes
     or new.availability is distinct from old.availability
     or new.estimated_days is distinct from old.estimated_days then

    update public.owner_spare_pricing p
       set selected_response_id = null,
           updated_at = now()
     where p.business_id = new.business_id
       and p.spare_request_id = new.spare_request_id
       and p.selected_response_id = new.id;

    get diagnostics v_invalidated = row_count;

    if v_invalidated > 0 then
      update public.spare_requests
         set status = 'requested',
             updated_at = now()
       where id = new.spare_request_id
         and business_id = new.business_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists invalidate_published_spare_offer_on_dealer_change
  on public.spare_request_responses;
create trigger invalidate_published_spare_offer_on_dealer_change
after update on public.spare_request_responses
for each row execute function public.invalidate_published_spare_offer_on_dealer_change();

-- Explicitly prevent anonymous/public execution of customer-facing definer RPCs.
-- These are authenticated customer operations and enforce auth.uid() ownership.
revoke all on function public.customer_add_vehicle(text, text, text, smallint) from public, anon;
revoke all on function public.customer_portal_snapshot() from public, anon;
revoke all on function public.customer_published_spare_quotes() from public, anon;
revoke all on function public.customer_request_service(uuid, text, text, timestamptz) from public, anon;
revoke all on function public.customer_request_spare(text, text, text, text, text, smallint, numeric, text) from public, anon;
revoke all on function public.customer_respond_to_quotation(uuid, boolean, text) from public, anon;

grant execute on function public.customer_add_vehicle(text, text, text, smallint) to authenticated, service_role;
grant execute on function public.customer_portal_snapshot() to authenticated, service_role;
grant execute on function public.customer_published_spare_quotes() to authenticated, service_role;
grant execute on function public.customer_request_service(uuid, text, text, timestamptz) to authenticated, service_role;
grant execute on function public.customer_request_spare(text, text, text, text, text, smallint, numeric, text) to authenticated, service_role;
grant execute on function public.customer_respond_to_quotation(uuid, boolean, text) to authenticated, service_role;
