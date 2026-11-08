-- Supplier bills and payment allocation: posted bills create AP journals; payments are allocated without duplicate journals.
create table public.supplier_bills (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete restrict,
 location_id uuid not null,
 supplier_id uuid not null,
 purchase_order_id uuid,
 supplier_invoice_number text not null,
 bill_date date not null default current_date,
 due_date date,
 currency_code char(3) not null references public.currencies(code),
 exchange_rate_to_kes numeric(18,8) not null check(exchange_rate_to_kes>0),
 subtotal_amount numeric(18,2) not null default 0 check(subtotal_amount>=0),
 tax_amount numeric(18,2) not null default 0 check(tax_amount>=0),
 total_amount numeric(18,2) not null check(total_amount>0),
 total_kes numeric(18,2) not null check(total_kes>0),
 amount_paid_kes numeric(18,2) not null default 0 check(amount_paid_kes>=0 and amount_paid_kes<=total_kes),
 status text not null default 'draft' check(status in ('draft','approved','partially_paid','paid','void')),
 notes text,
 journal_entry_id uuid,
 created_by uuid references public.profiles(id) on delete set null,
 approved_by uuid references public.profiles(id) on delete set null,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(business_id,id),
 unique(business_id,supplier_id,supplier_invoice_number),
 foreign key(business_id,location_id) references public.locations(business_id,id) on delete restrict,
 foreign key(business_id,supplier_id) references public.suppliers(business_id,id) on delete restrict,
 foreign key(business_id,purchase_order_id) references public.purchase_orders(business_id,id) on delete restrict,
 foreign key(business_id,journal_entry_id) references public.journal_entries(business_id,id) on delete restrict
);
create index supplier_bills_due_idx on public.supplier_bills(business_id,supplier_id,due_date) where status in ('approved','partially_paid');
create table public.supplier_bill_lines (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 supplier_bill_id uuid not null,
 line_number integer not null check(line_number>0),
 account_id uuid not null,
 description text not null,
 amount numeric(18,2) not null check(amount>0),
 amount_kes numeric(18,2) not null check(amount_kes>0),
 created_at timestamptz not null default now(),
 unique(business_id,supplier_bill_id,line_number),
 foreign key(business_id,supplier_bill_id) references public.supplier_bills(business_id,id) on delete restrict,
 foreign key(business_id,account_id) references public.chart_of_accounts(business_id,id) on delete restrict
);
create table public.supplier_bill_payment_allocations (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null,
 supplier_bill_id uuid not null,
 supplier_payment_id uuid not null,
 amount_kes numeric(18,2) not null check(amount_kes>0),
 allocated_by uuid references public.profiles(id) on delete set null,
 allocated_at timestamptz not null default now(),
 allocation_status text not null default 'active' check(allocation_status in ('active','reversed')),
 reversed_at timestamptz,
 reversal_reason text,
 foreign key(business_id,supplier_bill_id) references public.supplier_bills(business_id,id) on delete restrict,
 foreign key(business_id,supplier_payment_id) references public.supplier_payments(business_id,id) on delete restrict
);
create index supplier_bill_allocations_payment_idx on public.supplier_bill_payment_allocations(business_id,supplier_payment_id);
alter table public.supplier_bills enable row level security;
alter table public.supplier_bill_lines enable row level security;
alter table public.supplier_bill_payment_allocations enable row level security;
create policy "Finance users view supplier bills" on public.supplier_bills for select to authenticated
 using(private.has_business_permission(business_id,'finance.view',location_id) or private.has_business_permission(business_id,'procurement.manage',location_id));
create policy "Finance users view supplier bill lines" on public.supplier_bill_lines for select to authenticated
 using(exists(select 1 from public.supplier_bills b where b.business_id=supplier_bill_lines.business_id and b.id=supplier_bill_lines.supplier_bill_id and (private.has_business_permission(b.business_id,'finance.view',b.location_id) or private.has_business_permission(b.business_id,'procurement.manage',b.location_id))));
create policy "Finance users view supplier bill allocations" on public.supplier_bill_payment_allocations for select to authenticated
 using(exists(select 1 from public.supplier_bills b where b.business_id=supplier_bill_payment_allocations.business_id and b.id=supplier_bill_payment_allocations.supplier_bill_id and private.has_business_permission(b.business_id,'finance.view',b.location_id)));
revoke all on public.supplier_bills,public.supplier_bill_lines,public.supplier_bill_payment_allocations from anon,authenticated;
grant select on public.supplier_bills,public.supplier_bill_lines,public.supplier_bill_payment_allocations to authenticated;

create or replace function public.owner_create_supplier_bill(
 p_business_id uuid,p_location_id uuid,p_supplier_id uuid,p_purchase_order_id uuid,
 p_supplier_invoice_number text,p_bill_date date,p_due_date date,p_currency_code char(3),
 p_exchange_rate_to_kes numeric,p_total_amount numeric,p_total_kes numeric,p_notes text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_line jsonb; v_no integer:=0; v_sum numeric(18,2):=0;
 v_supplier public.suppliers%rowtype; v_loc public.locations%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'procurement.manage',p_location_id) and not private.has_business_permission(p_business_id,'finance.manage',p_location_id) then raise exception 'Supplier bill entry permission required' using errcode='42501'; end if;
 if nullif(btrim(p_supplier_invoice_number),'') is null then raise exception 'Supplier invoice number is required'; end if;
 if p_total_amount is null or p_total_amount<=0 or p_total_kes is null or p_total_kes<=0 or p_exchange_rate_to_kes is null or p_exchange_rate_to_kes<=0 then raise exception 'Enter valid positive bill totals and exchange rate'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one bill line is required'; end if;
 select * into v_supplier from public.suppliers where business_id=p_business_id and id=p_supplier_id and is_active;
 if not found then raise exception 'Active supplier not found'; end if;
 select * into v_loc from public.locations where business_id=p_business_id and id=p_location_id and is_active;
 if not found then raise exception 'Active branch not found'; end if;
 if p_purchase_order_id is not null and not exists(select 1 from public.purchase_orders where business_id=p_business_id and id=p_purchase_order_id and supplier_id=p_supplier_id) then raise exception 'Purchase order does not belong to this supplier'; end if;
 insert into public.supplier_bills(id,business_id,location_id,supplier_id,purchase_order_id,supplier_invoice_number,bill_date,due_date,currency_code,exchange_rate_to_kes,total_amount,total_kes,subtotal_amount,notes,created_by)
 values(v_id,p_business_id,p_location_id,p_supplier_id,p_purchase_order_id,btrim(p_supplier_invoice_number),coalesce(p_bill_date,current_date),p_due_date,p_currency_code,p_exchange_rate_to_kes,p_total_amount,p_total_kes,p_total_amount,nullif(btrim(coalesce(p_notes,'')),''),v_uid);
 for v_line in select value from jsonb_array_elements(p_lines) loop
  v_no:=v_no+1;
  if coalesce((v_line->>'amount')::numeric,0)<=0 or coalesce((v_line->>'amount_kes')::numeric,0)<=0 then raise exception 'Bill line amounts must be positive'; end if;
  if not exists(select 1 from public.chart_of_accounts a where a.business_id=p_business_id and a.id=(v_line->>'account_id')::uuid and a.is_active and a.account_type in ('asset','expense')) then raise exception 'Each bill line must use an active asset or expense account'; end if;
  insert into public.supplier_bill_lines(business_id,supplier_bill_id,line_number,account_id,description,amount,amount_kes)
  values(p_business_id,v_id,v_no,(v_line->>'account_id')::uuid,coalesce(nullif(btrim(v_line->>'description'),''),'Supplier bill line'),(v_line->>'amount')::numeric,(v_line->>'amount_kes')::numeric);
  v_sum:=v_sum+(v_line->>'amount_kes')::numeric;
 end loop;
 if abs(v_sum-p_total_kes)>0.01 then raise exception 'Bill line KES total (%) does not equal bill total (%)',v_sum,p_total_kes; end if;
 return v_id;
end; $$;
revoke all on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) to authenticated;

create or replace function public.owner_approve_supplier_bill(p_business_id uuid,p_supplier_bill_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_bill public.supplier_bills%rowtype; v_period uuid; v_period_status text; v_ap uuid; v_journal uuid; v_line record; v_no integer:=0;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_bill from public.supplier_bills where business_id=p_business_id and id=p_supplier_bill_id for update;
 if not found then raise exception 'Supplier bill not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_bill.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_bill.status<>'draft' then raise exception 'Only draft supplier bills can be approved'; end if;
 select id,status into v_period,v_period_status from public.accounting_periods where business_id=p_business_id and v_bill.bill_date between starts_on and ends_on order by starts_on desc limit 1;
 if v_period is null or v_period_status<>'open' then raise exception 'No open accounting period covers the supplier bill date'; end if;
 select id into v_ap from public.chart_of_accounts where business_id=p_business_id and account_code='2000' and account_type='liability' and is_control_account and is_active;
 if v_ap is null then raise exception 'Accounts payable control account is not configured'; end if;
 v_journal:=gen_random_uuid();
 insert into public.journal_entries(id,business_id,location_id,accounting_period_id,entry_number,entry_date,description,source_type,source_id,currency_code,exchange_rate_to_kes,status,created_by)
 values(v_journal,p_business_id,v_bill.location_id,v_period,'BILL-'||left(replace(v_bill.supplier_invoice_number,' ',''),24)||'-'||left(replace(v_bill.id::text,'-',''),8),v_bill.bill_date,'Supplier bill '||v_bill.supplier_invoice_number,'supplier_bill',v_bill.id,v_bill.currency_code,v_bill.exchange_rate_to_kes,'draft',v_uid);
 for v_line in select * from public.supplier_bill_lines where business_id=p_business_id and supplier_bill_id=v_bill.id order by line_number loop
  v_no:=v_no+1;
  insert into public.journal_lines(business_id,journal_entry_id,line_number,account_id,description,currency_code,exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes)
  values(p_business_id,v_journal,v_no,v_line.account_id,v_line.description,v_bill.currency_code,v_bill.exchange_rate_to_kes,v_line.amount,0,v_line.amount_kes,0);
 end loop;
 insert into public.journal_lines(business_id,journal_entry_id,line_number,account_id,description,currency_code,exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes)
 values(p_business_id,v_journal,v_no+1,v_ap,'Accounts payable · supplier bill '||v_bill.supplier_invoice_number,v_bill.currency_code,v_bill.exchange_rate_to_kes,0,v_bill.total_amount,0,v_bill.total_kes);
 perform private.post_journal_entry_impl(p_business_id,v_journal);
 update public.supplier_bills set status='approved',journal_entry_id=v_journal,approved_by=v_uid,approved_at=now(),updated_at=now() where business_id=p_business_id and id=v_bill.id;
 return v_journal;
end; $$;
revoke all on function public.owner_approve_supplier_bill(uuid,uuid) from public,anon;
grant execute on function public.owner_approve_supplier_bill(uuid,uuid) to authenticated;

create or replace function public.owner_allocate_supplier_payment(p_business_id uuid,p_payment_id uuid,p_supplier_bill_id uuid,p_amount_kes numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_pay public.supplier_payments%rowtype; v_bill public.supplier_bills%rowtype; v_alloc numeric(18,2); v_unallocated numeric(18,2); v_outstanding numeric(18,2); v_id uuid:=gen_random_uuid();
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_pay from public.supplier_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Supplier payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_pay.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_pay.status<>'recorded' then raise exception 'Only recorded supplier payments can be allocated'; end if;
 select * into v_bill from public.supplier_bills where business_id=p_business_id and id=p_supplier_bill_id for update;
 if not found then raise exception 'Supplier bill not found'; end if;
 if v_bill.supplier_id<>v_pay.supplier_id then raise exception 'Payment and bill must belong to the same supplier'; end if;
 if v_bill.status not in ('approved','partially_paid') then raise exception 'Only approved unpaid bills can receive allocations'; end if;
 if p_amount_kes is null or p_amount_kes<=0 then raise exception 'Enter a positive allocation amount'; end if;
 select coalesce(sum(amount_kes),0) into v_alloc from public.supplier_bill_payment_allocations where business_id=p_business_id and supplier_payment_id=p_payment_id and allocation_status='active';
 v_unallocated:=v_pay.amount_kes-v_alloc;
 v_outstanding:=v_bill.total_kes-v_bill.amount_paid_kes;
 if p_amount_kes>v_unallocated+0.001 then raise exception 'Allocation exceeds the unallocated payment balance (%)',v_unallocated; end if;
 if p_amount_kes>v_outstanding+0.001 then raise exception 'Allocation exceeds the outstanding bill balance (%)',v_outstanding; end if;
 insert into public.supplier_bill_payment_allocations(id,business_id,supplier_bill_id,supplier_payment_id,amount_kes,allocated_by)
 values(v_id,p_business_id,p_supplier_bill_id,p_payment_id,round(p_amount_kes,2),v_uid);
 update public.supplier_bills set amount_paid_kes=amount_paid_kes+round(p_amount_kes,2),
 status=case when amount_paid_kes+round(p_amount_kes,2)>=total_kes-0.001 then 'paid' else 'partially_paid' end,updated_at=now()
 where business_id=p_business_id and id=p_supplier_bill_id;
 return v_id;
end; $$;
revoke all on function public.owner_allocate_supplier_payment(uuid,uuid,uuid,numeric) from public,anon;
grant execute on function public.owner_allocate_supplier_payment(uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.owner_reverse_supplier_payment(p_business_id uuid,p_payment_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_payment public.supplier_payments%rowtype; v_reversal uuid; v_alloc record;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_payment from public.supplier_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Supplier payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_payment.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_payment.status<>'recorded' then raise exception 'Only recorded supplier payments can be reversed'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 for v_alloc in select supplier_bill_id,amount_kes from public.supplier_bill_payment_allocations where business_id=p_business_id and supplier_payment_id=p_payment_id and allocation_status='active' for update loop
  update public.supplier_bills set amount_paid_kes=greatest(0,amount_paid_kes-v_alloc.amount_kes),
   status=case when greatest(0,amount_paid_kes-v_alloc.amount_kes)<=0 then 'approved' else 'partially_paid' end,updated_at=now()
   where business_id=p_business_id and id=v_alloc.supplier_bill_id;
 end loop;
 update public.supplier_bill_payment_allocations set allocation_status='reversed',reversed_at=now(),reversal_reason=btrim(p_reason)
 where business_id=p_business_id and supplier_payment_id=p_payment_id and allocation_status='active';
 if v_payment.journal_entry_id is not null then
  v_reversal:=private.reverse_journal_entry_impl(p_business_id,v_payment.journal_entry_id,p_reversal_number,coalesce(p_reversal_date,current_date),p_reason);
  perform private.post_journal_entry_impl(p_business_id,v_reversal);
 end if;
 update public.supplier_payments set status='reversed',reversal_reason=btrim(p_reason),reversed_at=now(),reversed_by=v_uid,reversal_journal_entry_id=v_reversal
 where business_id=p_business_id and id=p_payment_id;
 return v_reversal;
end; $$;
revoke all on function public.owner_reverse_supplier_payment(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.owner_reverse_supplier_payment(uuid,uuid,text,date,text) to authenticated;
