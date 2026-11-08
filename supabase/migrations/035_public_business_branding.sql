-- Expose only the trading name needed for public website branding.
-- The businesses table remains private to assigned users; this RPC returns no identifiers or legal/contact data.
create or replace function public.get_public_business_branding()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select nullif(btrim(b.name), '')
  from public.businesses b
  order by b.id
  limit 1;
$$;

revoke all on function public.get_public_business_branding() from public;
grant execute on function public.get_public_business_branding() to anon, authenticated;