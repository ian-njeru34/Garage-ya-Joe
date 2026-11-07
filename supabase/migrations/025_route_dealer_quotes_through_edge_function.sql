-- All dealer responses must pass through the authenticated garage-portal Edge Function,
-- which validates dealer assignment and captures unit price, shipping and lead time together.
revoke all on function public.dealer_respond_to_spare_request(uuid,text,numeric,char,integer,text)
  from public, anon, authenticated;
