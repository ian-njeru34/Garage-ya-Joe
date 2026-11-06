-- Garage ya Joe: finance and double-entry accounting foundation.
-- Monetary values use NUMERIC. KES is the base reporting currency.
-- Posted journals are immutable; corrections are represented by reversal journals.

create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  period_name text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open' check (status in ('open','closed','locked')),
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint accounting_period_dates_check check (ends_on >= starts_on),
  unique (business_id,id),
  unique (business_id,period_name),
  unique (business_id,starts_on,ends_on)
);

create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  account_code text not null,
  account_name text not null,
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  parent_account_id uuid,
  is_control_account boolean not null default false,
  is_system_account boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chart_accounts_code_nonblank check (length(trim(account_code)) > 0),
  constraint chart_accounts_name_nonblank check (length(trim(account_name)) > 0),
  unique (business_id,id),
  unique (business_id,account_code),
  foreign key (business_id,parent_account_id)
    references public.chart_of_accounts(business_id,id) on delete restrict,
  check (parent_account_id is null or parent_account_id <> id)
);

create index chart_accounts_type_idx on public.chart_of_accounts(business_id,account_type,is_active);

create table public.cash_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  ledger_account_id uuid not null,
  account_name text not null,
  account_type text not null check (account_type in ('cash','bank','mobile_money','card_clearing','other')),
  currency_code char(3) not null references public.currencies(code),
  provider_name text,
  account_reference text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,id),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,ledger_account_id) references public.chart_of_accounts(business_id,id) on delete restrict
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  accounting_period_id uuid not null,
  entry_number text not null,
  entry_date date not null,
  description text not null,
  source_type text,
  source_id uuid,
  currency_code char(3) not null default 'KES' references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null default 1 check (exchange_rate_to_kes > 0),
  status text not null default 'draft' check (status in ('draft','posted','reversed')),
  reversal_of_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  posted_by uuid references public.profiles(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint journal_entry_number_nonblank check (length(trim(entry_number)) > 0),
  constraint journal_entry_description_nonblank check (length(trim(description)) > 0),
  unique (business_id,id),
  unique (business_id,entry_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,accounting_period_id) references public.accounting_periods(business_id,id) on delete restrict,
  foreign key (business_id,reversal_of_id) references public.journal_entries(business_id,id) on delete restrict,
  check (reversal_of_id is null or reversal_of_id <> id)
);

create index journal_entries_period_date_idx on public.journal_entries(business_id,accounting_period_id,entry_date);
create index journal_entries_source_idx on public.journal_entries(business_id,source_type,source_id) where source_id is not null;

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  journal_entry_id uuid not null,
  line_number integer not null check (line_number > 0),
  account_id uuid not null,
  description text,
  currency_code char(3) not null default 'KES' references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null default 1 check (exchange_rate_to_kes > 0),
  debit_amount numeric(18,2) not null default 0 check (debit_amount >= 0),
  credit_amount numeric(18,2) not null default 0 check (credit_amount >= 0),
  debit_kes numeric(18,2) not null default 0 check (debit_kes >= 0),
  credit_kes numeric(18,2) not null default 0 check (credit_kes >= 0),
  created_at timestamptz not null default now(),
  constraint journal_line_one_side check (
    (debit_amount > 0 and credit_amount = 0 and debit_kes > 0 and credit_kes = 0)
    or (credit_amount > 0 and debit_amount = 0 and credit_kes > 0 and debit_kes = 0)
  ),
  unique (business_id,journal_entry_id,line_number),
  foreign key (business_id,journal_entry_id) references public.journal_entries(business_id,id) on delete restrict,
  foreign key (business_id,account_id) references public.chart_of_accounts(business_id,id) on delete restrict
);

create index journal_lines_account_idx on public.journal_lines(business_id,account_id,journal_entry_id);

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  customer_id uuid not null,
  invoice_id uuid,
  cash_account_id uuid not null,
  payment_number text not null,
  payment_date date not null default current_date,
  payment_method text not null check (payment_method in ('cash','bank_transfer','card','mobile_money','cheque','other')),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  amount numeric(18,2) not null check (amount > 0),
  amount_kes numeric(18,2) not null check (amount_kes > 0),
  external_reference text,
  status text not null default 'recorded' check (status in ('recorded','reversed')),
  journal_entry_id uuid,
  notes text,
  received_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,payment_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id,invoice_id) references public.invoices(business_id,id) on delete restrict,
  foreign key (business_id,cash_account_id) references public.cash_accounts(business_id,id) on delete restrict,
  foreign key (business_id,journal_entry_id) references public.journal_entries(business_id,id) on delete restrict
);

create index customer_payments_invoice_idx on public.customer_payments(business_id,invoice_id,payment_date desc);
create index customer_payments_date_idx on public.customer_payments(business_id,location_id,payment_date desc);

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  supplier_id uuid not null,
  purchase_order_id uuid,
  cash_account_id uuid not null,
  payment_number text not null,
  payment_date date not null default current_date,
  payment_method text not null check (payment_method in ('cash','bank_transfer','card','mobile_money','cheque','other')),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  amount numeric(18,2) not null check (amount > 0),
  amount_kes numeric(18,2) not null check (amount_kes > 0),
  external_reference text,
  status text not null default 'recorded' check (status in ('recorded','reversed')),
  journal_entry_id uuid,
  notes text,
  paid_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,payment_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,supplier_id) references public.suppliers(business_id,id) on delete restrict,
  foreign key (business_id,purchase_order_id) references public.purchase_orders(business_id,id) on delete restrict,
  foreign key (business_id,cash_account_id) references public.cash_accounts(business_id,id) on delete restrict,
  foreign key (business_id,journal_entry_id) references public.journal_entries(business_id,id) on delete restrict
);

create index supplier_payments_supplier_date_idx on public.supplier_payments(business_id,supplier_id,payment_date desc);

create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  customer_id uuid not null,
  invoice_id uuid not null,
  credit_note_number text not null,
  issue_date date not null default current_date,
  reason text not null,
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  amount numeric(18,2) not null check (amount > 0),
  amount_kes numeric(18,2) not null check (amount_kes > 0),
  status text not null default 'draft' check (status in ('draft','issued','applied','void')),
  journal_entry_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,credit_note_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id,invoice_id) references public.invoices(business_id,id) on delete restrict,
  foreign key (business_id,journal_entry_id) references public.journal_entries(business_id,id) on delete restrict
);

create index credit_notes_invoice_idx on public.credit_notes(business_id,invoice_id,issue_date desc);

-- A posted journal cannot be edited or deleted. Draft lines may be maintained only while the parent is draft.
create or replace function private.guard_posted_journal_entry()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then raise exception 'Posted or reversed journal entries cannot be deleted'; end if;
    return old;
  end if;
  if old.status = 'posted' and new.status = 'reversed'
     and (to_jsonb(new) - 'status' - 'updated_at') = (to_jsonb(old) - 'status' - 'updated_at') then
    return new;
  end if;
  if old.status in ('posted','reversed') then
    raise exception 'Posted or reversed journal entries are immutable; create a reversal instead';
  end if;
  return new;
end;
$$;

create or replace function private.guard_journal_line_parent()
returns trigger language plpgsql set search_path = ''
as $$
declare v_status text; v_business uuid;
begin
  select status,business_id into v_status,v_business
  from public.journal_entries where id=coalesce(new.journal_entry_id,old.journal_entry_id);
  if not found or v_business <> coalesce(new.business_id,old.business_id) then
    raise exception 'Journal entry not found for this business';
  end if;
  if v_status <> 'draft' then raise exception 'Journal lines can only be changed while the entry is draft'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create trigger journal_entries_immutable
before update or delete on public.journal_entries
for each row execute function private.guard_posted_journal_entry();

create trigger journal_lines_draft_only
before insert or update or delete on public.journal_lines
for each row execute function private.guard_journal_line_parent();

-- RLS: finance users are scoped to their assigned business/location.
alter table public.accounting_periods enable row level security;
alter table public.chart_of_accounts enable row level security;
alter table public.cash_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.customer_payments enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.credit_notes enable row level security;

create policy "Finance users view accounting periods"
on public.accounting_periods for select to authenticated
using (private.has_business_permission(business_id,'finance.view'));

create policy "Finance managers manage accounting periods"
on public.accounting_periods for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

create policy "Finance users view chart of accounts"
on public.chart_of_accounts for select to authenticated
using (private.has_business_permission(business_id,'finance.view'));

create policy "Finance managers manage chart of accounts"
on public.chart_of_accounts for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

create policy "Finance users view cash accounts"
on public.cash_accounts for select to authenticated
using (private.has_business_permission(business_id,'finance.view',location_id));

create policy "Finance managers manage cash accounts"
on public.cash_accounts for all to authenticated
using (private.has_business_permission(business_id,'finance.manage',location_id))
with check (private.has_business_permission(business_id,'finance.manage',location_id));

create policy "Finance users view journal entries"
on public.journal_entries for select to authenticated
using (private.has_business_permission(business_id,'finance.view',location_id));

create policy "Finance managers manage draft journal entries"
on public.journal_entries for all to authenticated
using (status='draft' and private.has_business_permission(business_id,'finance.manage',location_id))
with check (private.has_business_permission(business_id,'finance.manage',location_id));

create policy "Finance users view journal lines"
on public.journal_lines for select to authenticated
using (exists (
  select 1 from public.journal_entries je
  where je.business_id=journal_lines.business_id and je.id=journal_lines.journal_entry_id
    and private.has_business_permission(je.business_id,'finance.view',je.location_id)
));

create policy "Finance managers manage draft journal lines"
on public.journal_lines for all to authenticated
using (exists (
  select 1 from public.journal_entries je
  where je.business_id=journal_lines.business_id and je.id=journal_lines.journal_entry_id
    and je.status='draft' and private.has_business_permission(je.business_id,'finance.manage',je.location_id)
))
with check (exists (
  select 1 from public.journal_entries je
  where je.business_id=journal_lines.business_id and je.id=journal_lines.journal_entry_id
    and je.status='draft' and private.has_business_permission(je.business_id,'finance.manage',je.location_id)
));

create policy "Payment staff view customer payments"
on public.customer_payments for select to authenticated
using (private.has_business_permission(business_id,'finance.view',location_id)
  or private.has_business_permission(business_id,'sales.view',location_id));

create policy "Authorized staff record customer payments"
on public.customer_payments for insert to authenticated
with check (private.has_business_permission(business_id,'payments.record',location_id));

create policy "Finance staff update customer payment status"
on public.customer_payments for update to authenticated
using (status='recorded' and private.has_business_permission(business_id,'finance.manage',location_id))
with check (private.has_business_permission(business_id,'finance.manage',location_id));

create policy "Finance staff view supplier payments"
on public.supplier_payments for select to authenticated
using (private.has_business_permission(business_id,'finance.view',location_id)
  or private.has_business_permission(business_id,'procurement.manage',location_id));

create policy "Authorized staff record supplier payments"
on public.supplier_payments for insert to authenticated
with check (private.has_business_permission(business_id,'payments.record',location_id)
  or private.has_business_permission(business_id,'procurement.manage',location_id));

create policy "Finance staff update supplier payment status"
on public.supplier_payments for update to authenticated
using (status='recorded' and private.has_business_permission(business_id,'finance.manage',location_id))
with check (private.has_business_permission(business_id,'finance.manage',location_id));

create policy "Finance users view credit notes"
on public.credit_notes for select to authenticated
using (private.has_business_permission(business_id,'finance.view',location_id)
  or private.has_business_permission(business_id,'sales.view',location_id));

create policy "Sales staff create draft credit notes"
on public.credit_notes for insert to authenticated
with check (status='draft' and private.has_business_permission(business_id,'sales.manage',location_id));

create policy "Finance staff update draft credit notes"
on public.credit_notes for update to authenticated
using (status='draft' and private.has_business_permission(business_id,'finance.manage',location_id))
with check (private.has_business_permission(business_id,'finance.manage',location_id));

-- Internal posting routine. It is not exposed through the Data API schema.
create or replace function private.post_journal_entry_impl(p_business_id uuid,p_journal_entry_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_period uuid;
  v_period_status text;
  v_status text;
  v_debits numeric(18,2);
  v_credits numeric(18,2);
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select location_id,accounting_period_id,status into v_location,v_period,v_status
  from public.journal_entries where business_id=p_business_id and id=p_journal_entry_id for update;
  if not found then raise exception 'Journal entry not found'; end if;
  if not private.has_business_permission(p_business_id,'finance.manage',v_location) then
    raise exception 'Not authorized to post journals' using errcode='42501';
  end if;
  if v_status <> 'draft' then raise exception 'Only draft journals can be posted'; end if;
  select status into v_period_status from public.accounting_periods
  where business_id=p_business_id and id=v_period for share;
  if v_period_status is distinct from 'open' then raise exception 'Accounting period is not open'; end if;
  select coalesce(sum(debit_kes),0),coalesce(sum(credit_kes),0)
    into v_debits,v_credits from public.journal_lines
    where business_id=p_business_id and journal_entry_id=p_journal_entry_id;
  if v_debits <= 0 or v_debits <> v_credits then
    raise exception 'Journal must contain balanced debit and credit lines in KES before posting';
  end if;
  update public.journal_entries set status='posted',posted_by=v_uid,posted_at=now(),updated_at=now()
  where business_id=p_business_id and id=p_journal_entry_id;
  return p_journal_entry_id;
end;
$$;

create or replace function private.reverse_journal_entry_impl(p_business_id uuid,p_journal_entry_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_original public.journal_entries%rowtype;
  v_period_status text;
  v_new_id uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into v_original from public.journal_entries
    where business_id=p_business_id and id=p_journal_entry_id for update;
  if not found then raise exception 'Original journal not found'; end if;
  if not private.has_business_permission(p_business_id,'finance.manage',v_original.location_id) then
    raise exception 'Not authorized to reverse journals' using errcode='42501';
  end if;
  if v_original.status <> 'posted' then raise exception 'Only posted journals can be reversed'; end if;
  if exists(select 1 from public.journal_entries where business_id=p_business_id and reversal_of_id=p_journal_entry_id) then
    raise exception 'This journal has already been reversed';
  end if;
  select status into v_period_status from public.accounting_periods
    where business_id=p_business_id and id=v_original.accounting_period_id;
  if v_period_status <> 'open' then raise exception 'Original accounting period is not open'; end if;

  insert into public.journal_entries(
    id,business_id,location_id,accounting_period_id,entry_number,entry_date,description,
    source_type,source_id,currency_code,exchange_rate_to_kes,status,reversal_of_id,created_by
  ) values (
    v_new_id,p_business_id,v_original.location_id,v_original.accounting_period_id,p_reversal_number,
    p_reversal_date,'Reversal: '||p_reason,v_original.source_type,v_original.source_id,
    v_original.currency_code,v_original.exchange_rate_to_kes,'draft',p_journal_entry_id,v_uid
  );

  insert into public.journal_lines(
    business_id,journal_entry_id,line_number,account_id,description,currency_code,
    exchange_rate_to_kes,debit_amount,credit_amount,debit_kes,credit_kes
  )
  select business_id,v_new_id,line_number,account_id,'Reversal: '||coalesce(description,''),
    currency_code,exchange_rate_to_kes,credit_amount,debit_amount,credit_kes,debit_kes
  from public.journal_lines where business_id=p_business_id and journal_entry_id=p_journal_entry_id;

  update public.journal_entries set status='reversed',updated_at=now()
  where business_id=p_business_id and id=p_journal_entry_id;
  return v_new_id;
end;
$$;

revoke all on function private.post_journal_entry_impl(uuid,uuid) from public,anon;
revoke all on function private.reverse_journal_entry_impl(uuid,uuid,text,date,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.post_journal_entry_impl(uuid,uuid) to authenticated;
grant execute on function private.reverse_journal_entry_impl(uuid,uuid,text,date,text) to authenticated;

create or replace function public.post_journal_entry(p_business_id uuid,p_journal_entry_id uuid)
returns uuid language sql security invoker set search_path = ''
as $$ select private.post_journal_entry_impl(p_business_id,p_journal_entry_id); $$;

create or replace function public.reverse_journal_entry(p_business_id uuid,p_journal_entry_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language sql security invoker set search_path = ''
as $$ select private.reverse_journal_entry_impl(p_business_id,p_journal_entry_id,p_reversal_number,p_reversal_date,p_reason); $$;

revoke all on function public.post_journal_entry(uuid,uuid) from public,anon;
revoke all on function public.reverse_journal_entry(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.post_journal_entry(uuid,uuid) to authenticated;
grant execute on function public.reverse_journal_entry(uuid,uuid,text,date,text) to authenticated;

-- Do not expose finance tables to anonymous clients.
revoke all on public.accounting_periods,public.chart_of_accounts,public.cash_accounts,
  public.journal_entries,public.journal_lines,public.customer_payments,
  public.supplier_payments,public.credit_notes from anon;
grant select,insert,update on public.accounting_periods,public.chart_of_accounts,public.cash_accounts,
  public.journal_entries,public.journal_lines,public.customer_payments,
  public.supplier_payments,public.credit_notes to authenticated;
