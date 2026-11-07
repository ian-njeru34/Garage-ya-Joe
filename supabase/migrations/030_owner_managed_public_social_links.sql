-- Owner-managed public WhatsApp and Facebook contacts for The Garage.
create table if not exists public.business_social_links (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null unique references public.businesses(id) on delete cascade,
 whatsapp_number text,
 facebook_url text,
 updated_by uuid references public.profiles(id) on delete set null,
 updated_at timestamptz not null default now(),
 constraint business_social_links_whatsapp_format check (whatsapp_number is null or whatsapp_number ~ '^\\+?[0-9][0-9 ()-]{6,19}$'),
 constraint business_social_links_facebook_https check (facebook_url is null or facebook_url ~ '^https://(www\\.)?facebook\\.com/')
);
alter table public.business_social_links enable row level security;
drop policy if exists "Public can view business social links" on public.business_social_links;
create policy "Public can view business social links" on public.business_social_links for select to anon, authenticated using (true);
drop policy if exists "Owners manage business social links" on public.business_social_links;
create policy "Owners manage business social links" on public.business_social_links for all to authenticated using (private.has_business_permission(business_id,'business.manage')) with check (private.has_business_permission(business_id,'business.manage'));
grant select on public.business_social_links to anon, authenticated;
grant insert,update,delete on public.business_social_links to authenticated;