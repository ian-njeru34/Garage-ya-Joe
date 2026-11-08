-- Bank and M-Pesa statement import, automatic payment matching and duplicate controls.
-- The same transaction reference may be verified once per business only.

alter table public.customer_payments
 add column if not exists verification_status text not null default 'pending',
 add column if not exists verified_at timestamptz,
 add column if not exists verified_by uuid references public.profiles(id) on delete set null,
 add column if not exists verification_statement_line_id uuid;
alter table public.supplier_payments
 add column if not exists verification_status text not null default 'pending',
 add column if not exists verified_at timestamptz,
 add column if not exists verified_by uuid references public.profiles(id) on delete set null,
 add column if not exists verification_statement_line_id uuid;
alter table public.customer_payments drop constraint if exists customer_payments_verification_status_check;
alter table public.customer_payments add constraint customer_payments_verification_status_check check(verification_status in('pending','verified','duplicate','duplicate_entry','needs_review'));
alter table public.supplier_payments drop constraint if exists supplier_payments_verification_status_check;
alter table public.supplier_payments add constraint supplier_payments_verification_status_check check(verification_status in('pending','verified','duplicate','duplicate_entry','needs_review'));

create table if not exists public.payment_statement_imports(
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id) on delete cascade,
 location_id uuid not null,cash_account_id uuid not null,source text not null check(source in('bank','mpesa')),
 flow text not null check(flow in('incoming','outgoing')),file_name text not null,file_path text not null,
 row_count int not null default 0,verified_count int not null default 0,unmatched_count int not null default 0,review_count int not null default 0,
 status text not null default 'processed' check(status in('processed','partial','failed')),
 uploaded_by uuid references public.profiles(id) on delete set null,created_at timestamptz not null default now(),
 unique(business_id,id),foreign key(business_id,location_id) references public.locations(business_id,id) on delete restrict,
 foreign key(business_id,cash_account_id) references public.cash_accounts(business_id,id) on delete restrict
);
create table if not exists public.payment_statement_lines(
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id) on delete cascade,
 import_id uuid not null,location_id uuid not null,cash_account_id uuid not null,row_number int not null,
 transaction_reference text,normalized_reference text,transaction_date date,amount numeric(18,2),currency_code char(3) not null,
 description text,counterparty text,raw_data jsonb not null default '{}'::jsonb,
 status text not null default 'unmatched' check(status in('pending','verified','unmatched','duplicate_reference','duplicate_statement_reference','already_verified','amount_mismatch','date_mismatch','currency_mismatch','invalid_reference')),
 matched_payment_table text check(matched_payment_table in('customer_payments','supplier_payments')),matched_payment_id uuid,review_reason text,
 verified_at timestamptz,verified_by uuid references public.profiles(id) on delete set null,created_at timestamptz not null default now(),
 unique(import_id,row_number),unique(business_id,id),
 foreign key(business_id,import_id) references public.payment_statement_imports(business_id,id) on delete cascade,
 foreign key(business_id,location_id) references public.locations(business_id,id) on delete restrict,
 foreign key(business_id,cash_account_id) references public.cash_accounts(business_id,id) on delete restrict
);
create table if not exists public.payment_verifications(
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id) on delete cascade,
 location_id uuid not null,cash_account_id uuid not null,normalized_reference text not null,transaction_reference text not null,
 payment_table text not null check(payment_table in('customer_payments','supplier_payments')),payment_id uuid not null,
 statement_line_id uuid not null,verified_by uuid references public.profiles(id) on delete set null,
 verified_at timestamptz not null default now(),owner_review_reason text,
 unique(business_id,normalized_reference),unique(business_id,payment_table,payment_id),unique(statement_line_id),
 foreign key(business_id,location_id) references public.locations(business_id,id) on delete restrict,
 foreign key(business_id,cash_account_id) references public.cash_accounts(business_id,id) on delete restrict,
 foreign key(business_id,statement_line_id) references public.payment_statement_lines(business_id,id) on delete restrict
);
create index if not exists payment_statement_imports_business_date_idx on public.payment_statement_imports(business_id,created_at desc);
create index if not exists payment_statement_lines_business_ref_idx on public.payment_statement_lines(business_id,normalized_reference);

alter table public.payment_statement_imports enable row level security;
alter table public.payment_statement_lines enable row level security;
alter table public.payment_verifications enable row level security;
drop policy if exists "Finance staff view payment statement imports" on public.payment_statement_imports;
create policy "Finance staff view payment statement imports" on public.payment_statement_imports for select to authenticated using(private.has_business_permission(business_id,'finance.view',location_id));
drop policy if exists "Finance staff view payment statement lines" on public.payment_statement_lines;
create policy "Finance staff view payment statement lines" on public.payment_statement_lines for select to authenticated using(private.has_business_permission(business_id,'finance.view',location_id));
drop policy if exists "Finance staff view payment verifications" on public.payment_verifications;
create policy "Finance staff view payment verifications" on public.payment_verifications for select to authenticated using(private.has_business_permission(business_id,'finance.view',location_id));
grant select on public.payment_statement_imports,public.payment_statement_lines,public.payment_verifications to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-statements','payment-statements',false,10485760,array['text/csv','text/plain','application/vnd.ms-excel','application/octet-stream'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['text/csv','text/plain','application/vnd.ms-excel','application/octet-stream'];
drop policy if exists "Finance users upload payment statements" on storage.objects;
create policy "Finance users upload payment statements" on storage.objects for insert to authenticated
with check(bucket_id='payment-statements' and private.has_business_permission((storage.foldername(name))[1]::uuid,'finance.manage',(storage.foldername(name))[2]::uuid));
drop policy if exists "Finance users read payment statements" on storage.objects;
create policy "Finance users read payment statements" on storage.objects for select to authenticated
using(bucket_id='payment-statements' and private.has_business_permission((storage.foldername(name))[1]::uuid,'finance.view',(storage.foldername(name))[2]::uuid));

create or replace function private.flag_duplicate_manual_payment_reference()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_norm text;v_count int;v_claimed boolean;
begin
 if tg_op='UPDATE' and old.external_reference is distinct from new.external_reference and old.verification_status='verified' then
  raise exception 'A verified transaction reference cannot be changed. Use owner review.';
 end if;
 v_norm:=upper(regexp_replace(btrim(coalesce(new.external_reference,'')),'[^A-Za-z0-9]','','g'));
 if v_norm='' then return new;end if;
 select exists(select 1 from public.payment_verifications where business_id=new.business_id and normalized_reference=v_norm) into v_claimed;
 select (select count(*) from public.customer_payments p where p.business_id=new.business_id and upper(regexp_replace(btrim(coalesce(p.external_reference,'')),'[^A-Za-z0-9]','','g'))=v_norm)
 +(select count(*) from public.supplier_payments p where p.business_id=new.business_id and upper(regexp_replace(btrim(coalesce(p.external_reference,'')),'[^A-Za-z0-9]','','g'))=v_norm) into v_count;
 if v_claimed or v_count>1 then
  update public.customer_payments set verification_status='duplicate' where business_id=new.business_id and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_norm and verification_status<>'verified';
  update public.supplier_payments set verification_status='duplicate' where business_id=new.business_id and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_norm and verification_status<>'verified';
 end if;return new;
end $$;
revoke all on function private.flag_duplicate_manual_payment_reference() from public,anon,authenticated;
drop trigger if exists customer_payment_reference_duplicate_guard on public.customer_payments;
create trigger customer_payment_reference_duplicate_guard after insert or update of external_reference on public.customer_payments for each row execute function private.flag_duplicate_manual_payment_reference();
drop trigger if exists supplier_payment_reference_duplicate_guard on public.supplier_payments;
create trigger supplier_payment_reference_duplicate_guard after insert or update of external_reference on public.supplier_payments for each row execute function private.flag_duplicate_manual_payment_reference();

create or replace function private.require_digital_payment_reference()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.payment_method in('mobile_money','bank_transfer','card') and nullif(btrim(coalesce(new.external_reference,'')),'') is null then
  raise exception 'Enter the M-Pesa, bank or card transaction reference before recording this payment.';
 end if;return new;
end $$;
drop trigger if exists customer_payment_reference_required on public.customer_payments;
create trigger customer_payment_reference_required before insert or update of payment_method,external_reference on public.customer_payments for each row execute function private.require_digital_payment_reference();
drop trigger if exists supplier_payment_reference_required on public.supplier_payments;
create trigger supplier_payment_reference_required before insert or update of payment_method,external_reference on public.supplier_payments for each row execute function private.require_digital_payment_reference();
revoke all on function private.require_digital_payment_reference() from public,anon,authenticated;

create or replace function private.route_statement_review_status()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_flow text;
begin
 select flow into v_flow from public.payment_statement_imports where business_id=new.business_id and id=new.import_id;
 if new.status='duplicate_reference' then
  update public.payment_statement_lines set matched_payment_table=case when v_flow='incoming' then 'customer_payments' else 'supplier_payments' end where id=new.id and matched_payment_table is null;
 end if;
 if new.status in('amount_mismatch','date_mismatch') and new.matched_payment_id is not null then
  if new.matched_payment_table='customer_payments' then
   update public.customer_payments set verification_status='needs_review' where business_id=new.business_id and id=new.matched_payment_id and verification_status<>'verified';
  elsif new.matched_payment_table='supplier_payments' then
   update public.supplier_payments set verification_status='needs_review' where business_id=new.business_id and id=new.matched_payment_id and verification_status<>'verified';
  end if;
 end if;return new;
end $$;
revoke all on function private.route_statement_review_status() from public,anon,authenticated;
drop trigger if exists route_statement_review_status on public.payment_statement_lines;
create trigger route_statement_review_status after insert or update of status on public.payment_statement_lines for each row execute function private.route_statement_review_status();

create or replace function public.owner_import_payment_statement(p_business_id uuid,p_location_id uuid,p_cash_account_id uuid,p_import_id uuid,p_source text,p_flow text,p_file_name text,p_file_path text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_cash public.cash_accounts%rowtype;v_row jsonb;v_line public.payment_statement_lines%rowtype;v_ref text;v_norm text;v_date date;v_amount numeric(18,2);v_currency text;v_count int;v_pid uuid;v_ptable text;v_pamount numeric(18,2);v_pdate date;v_pcurrency text;v_verified uuid;v_n int:=0;v_ok int:=0;v_unmatched int:=0;v_review int:=0;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 if not private.has_business_permission(p_business_id,'finance.manage',p_location_id) then raise exception 'Finance management permission required' using errcode='42501';end if;
 if p_source not in('bank','mpesa') or p_flow not in('incoming','outgoing') then raise exception 'Invalid statement source or flow';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>5000 then raise exception 'Statement must contain 1–5000 transaction rows';end if;
 if p_file_path not like p_business_id::text||'/'||p_location_id::text||'/'||p_import_id::text||'/%' then raise exception 'Invalid statement file path';end if;
 select * into v_cash from public.cash_accounts where business_id=p_business_id and id=p_cash_account_id and location_id=p_location_id and is_active for share;
 if not found then raise exception 'Select an active receiving account';end if;
 insert into public.payment_statement_imports(id,business_id,location_id,cash_account_id,source,flow,file_name,file_path,uploaded_by)
 values(p_import_id,p_business_id,p_location_id,p_cash_account_id,p_source,p_flow,p_file_name,p_file_path,v_uid);
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_n:=v_n+1;v_ref:=nullif(btrim(v_row->>'reference'),'');v_norm:=upper(regexp_replace(coalesce(v_ref,''),'[^A-Za-z0-9]','','g'));v_date:=nullif(v_row->>'date','')::date;v_amount:=abs(coalesce(nullif(v_row->>'amount','')::numeric,0));v_currency:=upper(coalesce(nullif(v_row->>'currency',''),v_cash.currency_code));
  if v_amount<=0 or v_date is null then raise exception 'Row % has an invalid date or amount',v_n;end if;
  insert into public.payment_statement_lines(business_id,import_id,location_id,cash_account_id,row_number,transaction_reference,normalized_reference,transaction_date,amount,currency_code,description,counterparty,raw_data,status)
  values(p_business_id,p_import_id,p_location_id,p_cash_account_id,v_n,v_ref,nullif(v_norm,''),v_date,v_amount,v_currency,left(v_row->>'description',1000),left(v_row->>'counterparty',250),coalesce(v_row->'raw','{}'::jsonb),case when length(v_norm)<3 then 'invalid_reference' else 'pending' end);
 end loop;
 update public.payment_statement_lines l set status='duplicate_statement_reference',review_reason='Transaction reference appears more than once in this statement.'
 where l.import_id=p_import_id and l.normalized_reference in(select normalized_reference from public.payment_statement_lines where import_id=p_import_id and normalized_reference is not null group by normalized_reference having count(*)>1);
 for v_line in select * from public.payment_statement_lines where import_id=p_import_id and status='pending' order by row_number loop
  v_pid:=null;v_ptable:=null;v_count:=0;
  if v_line.currency_code<>v_cash.currency_code then update public.payment_statement_lines set status='currency_mismatch',review_reason='Currency differs from receiving account.' where id=v_line.id;continue;end if;
  select id into v_verified from public.payment_verifications where business_id=p_business_id and normalized_reference=v_line.normalized_reference;
  if v_verified is not null then update public.payment_statement_lines set status='already_verified',review_reason='Reference has already been verified once.' where id=v_line.id;continue;end if;
  if p_flow='incoming' then
   select count(*) into v_count from public.customer_payments where business_id=p_business_id and location_id=p_location_id and cash_account_id=p_cash_account_id and status='recorded' and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference;
   if v_count=1 then select id,amount,payment_date,currency_code into v_pid,v_pamount,v_pdate,v_pcurrency from public.customer_payments where business_id=p_business_id and location_id=p_location_id and cash_account_id=p_cash_account_id and status='recorded' and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference;v_ptable:='customer_payments';end if;
  else
   select count(*) into v_count from public.supplier_payments where business_id=p_business_id and location_id=p_location_id and cash_account_id=p_cash_account_id and status='recorded' and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference;
   if v_count=1 then select id,amount,payment_date,currency_code into v_pid,v_pamount,v_pdate,v_pcurrency from public.supplier_payments where business_id=p_business_id and location_id=p_location_id and cash_account_id=p_cash_account_id and status='recorded' and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference;v_ptable:='supplier_payments';end if;
  end if;
  if v_count=0 then update public.payment_statement_lines set status='unmatched',review_reason='No manually recorded payment found for this account and reference.' where id=v_line.id;v_unmatched:=v_unmatched+1;continue;
  elsif v_count>1 then update public.payment_statement_lines set status='duplicate_reference',review_reason='Multiple manual entries use this reference. Owner review required.' where id=v_line.id;
   if p_flow='incoming' then update public.customer_payments set verification_status='duplicate' where business_id=p_business_id and cash_account_id=p_cash_account_id and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference and verification_status<>'verified';
   else update public.supplier_payments set verification_status='duplicate' where business_id=p_business_id and cash_account_id=p_cash_account_id and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_line.normalized_reference and verification_status<>'verified';end if;v_review:=v_review+1;continue;
  end if;
  if v_pcurrency<>v_line.currency_code or round(v_pamount,2)<>round(v_line.amount,2) then update public.payment_statement_lines set status='amount_mismatch',matched_payment_table=v_ptable,matched_payment_id=v_pid,review_reason='Amount or currency does not match.' where id=v_line.id;v_review:=v_review+1;continue;
  elsif v_pdate<>v_line.transaction_date then update public.payment_statement_lines set status='date_mismatch',matched_payment_table=v_ptable,matched_payment_id=v_pid,review_reason='Transaction date does not match.' where id=v_line.id;v_review:=v_review+1;continue;end if;
  insert into public.payment_verifications(business_id,location_id,cash_account_id,normalized_reference,transaction_reference,payment_table,payment_id,statement_line_id,verified_by)
  values(p_business_id,p_location_id,p_cash_account_id,v_line.normalized_reference,v_line.transaction_reference,v_ptable,v_pid,v_line.id,v_uid);
  if v_ptable='customer_payments' then update public.customer_payments set verification_status='verified',verified_at=now(),verified_by=v_uid,verification_statement_line_id=v_line.id where id=v_pid;
  else update public.supplier_payments set verification_status='verified',verified_at=now(),verified_by=v_uid,verification_statement_line_id=v_line.id where id=v_pid;end if;
  update public.payment_statement_lines set status='verified',matched_payment_table=v_ptable,matched_payment_id=v_pid,verified_at=now(),verified_by=v_uid where id=v_line.id;v_ok:=v_ok+1;
 end loop;
 select count(*) filter(where status='unmatched')+count(*) filter(where status='invalid_reference')+count(*) filter(where status='already_verified'),
 count(*) filter(where status not in('verified','unmatched','invalid_reference','already_verified')) into v_unmatched,v_review from public.payment_statement_lines where import_id=p_import_id;
 update public.payment_statement_imports set row_count=v_n,verified_count=v_ok,unmatched_count=v_unmatched,review_count=v_review,status=case when v_review+v_unmatched=0 then 'processed' else 'partial' end where id=p_import_id;
 return jsonb_build_object('import_id',p_import_id,'rows',v_n,'verified',v_ok,'unmatched',v_unmatched,'review',v_review);
end $$;
revoke all on function public.owner_import_payment_statement(uuid,uuid,uuid,uuid,text,text,text,text,jsonb) from public,anon;
grant execute on function public.owner_import_payment_statement(uuid,uuid,uuid,uuid,text,text,text,text,jsonb) to authenticated;

create or replace function public.owner_resolve_payment_duplicate(p_business_id uuid,p_payment_table text,p_payment_id uuid,p_statement_line_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_line public.payment_statement_lines%rowtype;v_ref text;v_amount numeric(18,2);v_date date;v_account uuid;v_location uuid;v_status text;v_count int;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 if not exists(select 1 from public.user_roles where user_id=v_uid and business_id=p_business_id and role_code='owner') then raise exception 'Only the business owner may resolve duplicate payments' using errcode='42501';end if;
 if p_payment_table not in('customer_payments','supplier_payments') or nullif(btrim(p_reason),'') is null then raise exception 'Select a payment and enter an owner review reason';end if;
 select * into v_line from public.payment_statement_lines where business_id=p_business_id and id=p_statement_line_id for update;
 if not found or v_line.status not in('duplicate_reference','amount_mismatch','date_mismatch') then raise exception 'Statement row is not awaiting owner review';end if;
 if exists(select 1 from public.payment_verifications where business_id=p_business_id and normalized_reference=v_line.normalized_reference) then raise exception 'This transaction reference has already been verified';end if;
 if p_payment_table='customer_payments' then select upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g')),amount,payment_date,cash_account_id,location_id,status into v_ref,v_amount,v_date,v_account,v_location,v_status from public.customer_payments where business_id=p_business_id and id=p_payment_id and verification_status in('duplicate','needs_review') for update;
 else select upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g')),amount,payment_date,cash_account_id,location_id,status into v_ref,v_amount,v_date,v_account,v_location,v_status from public.supplier_payments where business_id=p_business_id and id=p_payment_id and verification_status in('duplicate','needs_review') for update;end if;
 if v_ref is distinct from v_line.normalized_reference or v_amount is distinct from v_line.amount or v_date is distinct from v_line.transaction_date or v_account is distinct from v_line.cash_account_id or v_location is distinct from v_line.location_id or v_status<>'recorded' then raise exception 'Payment does not match statement reference, amount, date and account';end if;
 if p_payment_table='customer_payments' then
  select count(*) into v_count from public.customer_payments where business_id=p_business_id and cash_account_id=v_account and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_ref;
  if v_count<2 then raise exception 'Duplicate group no longer exists';end if;
  update public.customer_payments set verification_status='duplicate_entry' where business_id=p_business_id and cash_account_id=v_account and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_ref and id<>p_payment_id;
  update public.customer_payments set verification_status='verified',verified_at=now(),verified_by=v_uid,verification_statement_line_id=v_line.id where business_id=p_business_id and id=p_payment_id;
 else
  select count(*) into v_count from public.supplier_payments where business_id=p_business_id and cash_account_id=v_account and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_ref;
  if v_count<2 then raise exception 'Duplicate group no longer exists';end if;
  update public.supplier_payments set verification_status='duplicate_entry' where business_id=p_business_id and cash_account_id=v_account and upper(regexp_replace(btrim(coalesce(external_reference,'')),'[^A-Za-z0-9]','','g'))=v_ref and id<>p_payment_id;
  update public.supplier_payments set verification_status='verified',verified_at=now(),verified_by=v_uid,verification_statement_line_id=v_line.id where business_id=p_business_id and id=p_payment_id;
 end if;
 insert into public.payment_verifications(business_id,location_id,cash_account_id,normalized_reference,transaction_reference,payment_table,payment_id,statement_line_id,verified_by,owner_review_reason)
 values(p_business_id,v_line.location_id,v_line.cash_account_id,v_ref,v_line.transaction_reference,p_payment_table,p_payment_id,v_line.id,v_uid,btrim(p_reason));
 update public.payment_statement_lines set status='verified',matched_payment_table=p_payment_table,matched_payment_id=p_payment_id,verified_at=now(),verified_by=v_uid,review_reason='Owner approved duplicate: '||btrim(p_reason) where id=v_line.id;
end $$;
revoke all on function public.owner_resolve_payment_duplicate(uuid,text,uuid,uuid,text) from public,anon;
grant execute on function public.owner_resolve_payment_duplicate(uuid,text,uuid,uuid,text) to authenticated;
