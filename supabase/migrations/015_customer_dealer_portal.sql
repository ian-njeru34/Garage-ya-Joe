-- The Garage: customer self-service, dealer access and customer spare requests.
-- Apply after migrations 001-014. No Vercel/serverless endpoint is added by this migration.

insert into public.role_definitions(code,name,description)
values ('dealer','Dealer','Views and responds to spare-parts requests assigned by the owner.')
on conflict (code) do nothing;

insert into public.permission_definitions(code,description) values
 ('spares.requests.view_assigned','View spare-parts requests assigned to this dealer.'),
 ('spares.requests.respond','Respond to spare-parts requests assigned to this dealer.')
on conflict (code) do nothing;

insert into public.role_permissions(role_code,permission_code) values
 ('owner','spares.requests.view_assigned'),
 ('owner','spares.requests.respond'),
 ('dealer','spares.requests.view_assigned'),
 ('dealer','spares.requests.respond')
on conflict do nothing;

-- A dealer login is linked to an existing supplier record.
create table if not exists public.dealer_accounts (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete restrict,
 supplier_id uuid not null,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique (business_id,id),
 unique (business_id,supplier_id),
 unique (profile_id),
 foreign key (business_id,supplier_id) references public.suppliers(business_id,id) on delete restrict
);
alter table public.dealer_accounts enable row level security;
create policy "Owners manage dealer accounts"
 on public.dealer_accounts for all to authenticated
 using (private.has_business_permission(business_id,'staff.manage'))
 with check (private.has_business_permission(business_id,'staff.manage'));
create policy "Dealers view their own dealer account"
 on public.dealer_accounts for select to authenticated
 using (profile_id=(select auth.uid()));
revoke all on public.dealer_accounts from anon,authenticated;
grant select on public.dealer_accounts to authenticated;
grant all on public.dealer_accounts to service_role;

create table if not exists public.spare_requests (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete restrict,
 customer_id uuid not null,
 created_by uuid not null references public.profiles(id) on delete restrict,
 assigned_dealer_id uuid references public.profiles(id) on delete set null,
 part_name text not null,
 part_number text,
 vehicle_make text,
 vehicle_model text,
 vehicle_year smallint,
 quantity numeric(12,2) not null default 1 check(quantity>0),
 customer_whatsapp text not null,
 customer_notes text,
 status text not null default 'new'
   check(status in ('new','assigned','dealer_responded','quoted','ordered','fulfilled','unavailable','closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
 check(length(trim(part_name))>0),
 check(length(trim(customer_whatsapp))>0),
 check(vehicle_year is null or vehicle_year between 1900 and 2100),
 unique(business_id,id)
);
create index if not exists spare_requests_business_status_idx
 on public.spare_requests(business_id,status,created_at desc);
create index if not exists spare_requests_dealer_idx
 on public.spare_requests(assigned_dealer_id,status,created_at desc);
alter table public.spare_requests enable row level security;
create policy "Owners view and manage all spare requests"
 on public.spare_requests for all to authenticated
 using (private.has_business_permission(business_id,'staff.manage'))
 with check (private.has_business_permission(business_id,'staff.manage'));
create policy "Customers view their own spare requests"
 on public.spare_requests for select to authenticated
 using (exists(select 1 from public.customers c where c.id=customer_id and c.business_id=spare_requests.business_id and c.profile_id=(select auth.uid())));
create policy "Assigned dealers view their requests"
 on public.spare_requests for select to authenticated
 using (assigned_dealer_id=(select auth.uid()) and private.has_business_permission(business_id,'spares.requests.view_assigned'));
revoke all on public.spare_requests from anon,authenticated;
grant select,update on public.spare_requests to authenticated;
grant all on public.spare_requests to service_role;

create table if not exists public.spare_request_responses (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 spare_request_id uuid not null,
 dealer_profile_id uuid not null references public.profiles(id) on delete restrict,
 availability text not null check(availability in ('available','to_order','unavailable')),
 quoted_unit_price numeric(18,2) check(quoted_unit_price is null or quoted_unit_price>=0),
 currency_code char(3) not null default 'KES' references public.currencies(code),
 estimated_days integer check(estimated_days is null or estimated_days>=0),
 response_notes text,
 created_at timestamptz not null default now(),
 foreign key(business_id,spare_request_id) references public.spare_requests(business_id,id) on delete restrict,
 unique(business_id,id)
);
alter table public.spare_request_responses enable row level security;
create policy "Owners view dealer responses"
 on public.spare_request_responses for select to authenticated
 using(private.has_business_permission(business_id,'staff.manage'));
create policy "Customers view responses to their own requests"
 on public.spare_request_responses for select to authenticated
 using(exists(select 1 from public.spare_requests r join public.customers c on c.id=r.customer_id and c.business_id=r.business_id where r.id=spare_request_id and r.business_id=spare_request_responses.business_id and c.profile_id=(select auth.uid())));
create policy "Assigned dealer views own responses"
 on public.spare_request_responses for select to authenticated
 using(dealer_profile_id=(select auth.uid()));
revoke all on public.spare_request_responses from anon,authenticated;
grant select on public.spare_request_responses to authenticated;
grant all on public.spare_request_responses to service_role;

-- Ensure the single-business installation has a usable business and booking location.
-- Existing business/location records are preserved.
insert into public.businesses(name,legal_name,base_currency)
select 'The Garage', 'The Garage', 'KES'
where not exists(select 1 from public.businesses);

insert into public.locations(business_id,code,name,location_type,is_active)
select b.id,'MAIN','Main Garage','garage',true
from public.businesses b
where not exists(select 1 from public.locations l where l.business_id=b.id);

-- Auth trigger provisions only the public customer role. Public metadata can never
-- grant staff, owner or dealer access. The first configured business is used.
create or replace function public.provision_auth_profile()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
 v_business_id uuid;
 v_name text;
 v_phone text;
 v_customer_id uuid;
begin
 v_name := nullif(trim(coalesce(new.raw_user_meta_data->>'full_name','')), '');
 v_phone := nullif(trim(coalesce(new.raw_user_meta_data->>'whatsapp_number',new.raw_user_meta_data->>'phone','')), '');

 insert into public.profiles(id,full_name,phone)
 values(new.id,v_name,v_phone)
 on conflict(id) do update set
   full_name=coalesce(excluded.full_name,public.profiles.full_name),
   phone=coalesce(excluded.phone,public.profiles.phone);

 if coalesce(new.raw_user_meta_data->>'account_type','')='customer' then
   select id into v_business_id from public.businesses order by created_at asc limit 1;
   if v_business_id is null then
     raise exception 'The garage business has not been configured yet. Please try again later.';
   end if;

   insert into public.user_roles(user_id,business_id,role_code)
   values(new.id,v_business_id,'customer')
   on conflict(user_id,business_id,location_id,role_code) do nothing;

   insert into public.customers(business_id,profile_id,display_name,email,phone)
   values(v_business_id,new.id,coalesce(v_name,new.email),new.email,v_phone)
   on conflict do nothing;
 end if;
 return new;
end;
$$;

drop trigger if exists on_auth_user_provision_profile on auth.users;
create trigger on_auth_user_provision_profile
 after insert on auth.users
 for each row execute function public.provision_auth_profile();

-- Customer-owned vehicle creation. The caller cannot choose a customer or business ID.
create or replace function public.customer_add_vehicle(
 p_registration_number text,p_make text,p_model text,p_year smallint default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_vehicle_id uuid;
begin
 select * into v_customer from public.customers where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Customer profile not found' using errcode='42501'; end if;
 if length(trim(coalesce(p_registration_number,'')))=0 or length(trim(coalesce(p_make,'')))=0 or length(trim(coalesce(p_model,'')))=0 then
   raise exception 'Registration, make and model are required';
 end if;
 insert into public.vehicles(business_id,registration_number,make,model,manufacture_year)
 values(v_customer.business_id,trim(p_registration_number),trim(p_make),trim(p_model),p_year)
 returning id into v_vehicle_id;
 insert into public.vehicle_customer_relationships(business_id,vehicle_id,customer_id,relationship_type)
 values(v_customer.business_id,v_vehicle_id,v_customer.id,'owner');
 return v_vehicle_id;
end;
$$;

create or replace function public.customer_request_service(
 p_vehicle_id uuid,p_requested_service text,p_customer_concern text default null,p_preferred_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_location_id uuid; v_appointment_id uuid;
begin
 select * into v_customer from public.customers where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Customer profile not found' using errcode='42501'; end if;
 if not exists(select 1 from public.vehicle_customer_relationships where customer_id=v_customer.id and vehicle_id=p_vehicle_id and business_id=v_customer.business_id and ended_at is null) then
   raise exception 'Choose a vehicle registered to your account' using errcode='42501';
 end if;
 select id into v_location_id from public.locations where business_id=v_customer.business_id and is_active=true order by case when location_type='garage' then 0 else 1 end,created_at asc limit 1;
 if v_location_id is null then raise exception 'The garage has not configured an active service location yet'; end if;
 insert into public.service_appointments(business_id,location_id,customer_id,vehicle_id,requested_service,customer_concern,preferred_at,booking_source,status)
 values(v_customer.business_id,v_location_id,v_customer.id,p_vehicle_id,trim(p_requested_service),nullif(trim(coalesce(p_customer_concern,'')),''),p_preferred_at,'customer','requested')
 returning id into v_appointment_id;
 return v_appointment_id;
end;
$$;

create or replace function public.customer_request_spare(
 p_part_name text,p_whatsapp text,p_part_number text default null,
 p_vehicle_make text default null,p_vehicle_model text default null,p_vehicle_year smallint default null,
 p_quantity numeric default 1,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_request_id uuid;
begin
 select * into v_customer from public.customers where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Customer profile not found' using errcode='42501'; end if;
 if length(trim(coalesce(p_part_name,'')))=0 or length(trim(coalesce(p_whatsapp,'')))=0 then raise exception 'Part name and WhatsApp number are required'; end if;
 insert into public.spare_requests(business_id,customer_id,created_by,part_name,part_number,vehicle_make,vehicle_model,vehicle_year,quantity,customer_whatsapp,customer_notes)
 values(v_customer.business_id,v_customer.id,(select auth.uid()),trim(p_part_name),nullif(trim(coalesce(p_part_number,'')),''),nullif(trim(coalesce(p_vehicle_make,'')),''),nullif(trim(coalesce(p_vehicle_model,'')),''),p_vehicle_year,coalesce(p_quantity,1),trim(p_whatsapp),nullif(trim(coalesce(p_notes,'')),''))
 returning id into v_request_id;
 return v_request_id;
end;
$$;

-- A compact, safe customer-facing snapshot. Internal notes, mechanic-only inspection data
-- and staff contact details are deliberately excluded.
create or replace function public.customer_portal_snapshot()
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_result jsonb;
begin
 select * into v_customer from public.customers where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Customer profile not found' using errcode='42501'; end if;
 select jsonb_build_object(
  'customer',jsonb_build_object('id',v_customer.id,'display_name',v_customer.display_name,'email',v_customer.email,'whatsapp',v_customer.phone),
  'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'registration_number',v.registration_number,'make',v.make,'model',v.model,'year',v.manufacture_year) order by v.created_at desc) from public.vehicles v join public.vehicle_customer_relationships r on r.vehicle_id=v.id and r.business_id=v.business_id where r.customer_id=v_customer.id and r.ended_at is null),'[]'::jsonb),
  'appointments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'service',a.requested_service,'status',a.status,'preferred_at',a.preferred_at,'scheduled_at',a.scheduled_at,'created_at',a.created_at,'vehicle',v.registration_number||' · '||v.make||' '||v.model) order by a.created_at desc) from public.service_appointments a join public.vehicles v on v.id=a.vehicle_id and v.business_id=a.business_id where a.customer_id=v_customer.id),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'job_number',j.job_number,'status',j.status,'diagnosis',j.diagnosis_summary,'work_summary',j.work_summary,'vehicle',v.registration_number||' · '||v.make||' '||v.model,'tasks',coalesce((select jsonb_agg(jsonb_build_object('title',t.task_title,'status',t.status) order by t.created_at) from public.job_tasks t where t.job_card_id=j.id and t.business_id=j.business_id and t.status<>'cancelled'),'[]'::jsonb)) order by j.opened_at desc) from public.job_cards j join public.vehicles v on v.id=j.vehicle_id and v.business_id=j.business_id where j.customer_id=v_customer.id),'[]'::jsonb),
  'quotations',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'number',q.quote_number,'status',q.status,'total',q.total_amount,'currency',q.currency_code,'issued_at',q.sent_at,'valid_until',q.valid_until,'job_card_id',q.job_card_id,'items',coalesce((select jsonb_agg(jsonb_build_object('description',i.description,'quantity',i.quantity,'unit_price',i.unit_price,'line_total',i.line_total) order by i.line_number) from public.quotation_items i where i.quotation_id=q.id and i.business_id=q.business_id),'[]'::jsonb)) order by q.created_at desc) from public.quotations q where q.customer_id=v_customer.id and q.business_id=v_customer.business_id and q.status<>'draft'),'[]'::jsonb),
  'spare_requests',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'part_name',s.part_name,'part_number',s.part_number,'status',s.status,'created_at',s.created_at) order by s.created_at desc) from public.spare_requests s where s.customer_id=v_customer.id and s.business_id=v_customer.business_id),'[]'::jsonb)
 ) into v_result;
 return v_result;
end;
$$;

create or replace function public.customer_respond_to_quotation(p_quotation_id uuid,p_accept boolean,p_reason text default null)
returns void
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_quote public.quotations%rowtype; v_new_status text;
begin
 select * into v_customer from public.customers where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Customer profile not found' using errcode='42501'; end if;
 select * into v_quote from public.quotations where id=p_quotation_id and business_id=v_customer.business_id and customer_id=v_customer.id for update;
 if not found then raise exception 'Quotation not found' using errcode='42501'; end if;
 if v_quote.status<>'sent' then raise exception 'Only a quotation sent by the garage can be accepted or declined'; end if;
 v_new_status:=case when p_accept then 'accepted' else 'rejected' end;
 update public.quotations set status=v_new_status,accepted_at=case when p_accept then now() else accepted_at end,rejected_at=case when not p_accept then now() else rejected_at end,updated_at=now() where id=v_quote.id;
 insert into public.quotation_status_history(business_id,quotation_id,previous_status,new_status,changed_by,change_source,reason)
 values(v_quote.business_id,v_quote.id,v_quote.status,v_new_status,(select auth.uid()),'customer',nullif(trim(coalesce(p_reason,'')),''));
end;
$$;

create or replace function public.dealer_respond_to_spare_request(
 p_request_id uuid,p_availability text,p_price numeric default null,p_currency char(3) default 'KES',
 p_estimated_days integer default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_request public.spare_requests%rowtype; v_response_id uuid; v_dealer public.dealer_accounts%rowtype;
begin
 select * into v_dealer from public.dealer_accounts where profile_id=(select auth.uid()) limit 1;
 if not found then raise exception 'Dealer account not found' using errcode='42501'; end if;
 select * into v_request from public.spare_requests where id=p_request_id and business_id=v_dealer.business_id and assigned_dealer_id=(select auth.uid()) for update;
 if not found then raise exception 'This spare request is not assigned to your dealer account' using errcode='42501'; end if;
 if p_availability not in ('available','to_order','unavailable') then raise exception 'Invalid availability status'; end if;
 insert into public.spare_request_responses(business_id,spare_request_id,dealer_profile_id,availability,quoted_unit_price,currency_code,estimated_days,response_notes)
 values(v_request.business_id,v_request.id,(select auth.uid()),p_availability,p_price,coalesce(p_currency,'KES'),p_estimated_days,nullif(trim(coalesce(p_notes,'')),''))
 returning id into v_response_id;
 update public.spare_requests set status='dealer_responded',updated_at=now() where id=v_request.id;
 return v_response_id;
end;
$$;

revoke all on function public.customer_add_vehicle(text,text,text,smallint) from public,anon;
revoke all on function public.customer_request_service(uuid,text,text,timestamptz) from public,anon;
revoke all on function public.customer_request_spare(text,text,text,text,text,smallint,numeric,text) from public,anon;
revoke all on function public.customer_portal_snapshot() from public,anon;
revoke all on function public.customer_respond_to_quotation(uuid,boolean,text) from public,anon;
revoke all on function public.dealer_respond_to_spare_request(uuid,text,numeric,char,integer,text) from public,anon;
grant execute on function public.customer_add_vehicle(text,text,text,smallint) to authenticated;
grant execute on function public.customer_request_service(uuid,text,text,timestamptz) to authenticated;
grant execute on function public.customer_request_spare(text,text,text,text,text,smallint,numeric,text) to authenticated;
grant execute on function public.customer_portal_snapshot() to authenticated;
grant execute on function public.customer_respond_to_quotation(uuid,boolean,text) to authenticated;
grant execute on function public.dealer_respond_to_spare_request(uuid,text,numeric,char,integer,text) to authenticated;
