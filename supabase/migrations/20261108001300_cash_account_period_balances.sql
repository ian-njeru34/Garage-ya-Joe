create table if not exists public.cash_account_period_balances (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 cash_account_id uuid not null references public.cash_accounts(id) on delete cascade,
 accounting_period_id uuid not null references public.accounting_periods(id) on delete restrict,
 opening_balance_kes numeric(18,2) not null,
 statement_closing_balance_kes numeric(18,2),
 opening_balance_as_at date not null,
 statement_closing_as_at date,
 note text, updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now(),
 unique(cash_account_id,accounting_period_id),
 check(opening_balance_kes>=0),
 check(statement_closing_balance_kes is null or statement_closing_balance_kes>=0),
 check(statement_closing_as_at is null or statement_closing_as_at>=opening_balance_as_at)
);
create table if not exists public.cash_account_period_balance_audit (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 cash_account_id uuid not null references public.cash_accounts(id) on delete cascade,
 accounting_period_id uuid not null references public.accounting_periods(id) on delete restrict,
 opening_balance_kes numeric(18,2) not null, statement_closing_balance_kes numeric(18,2),
 opening_balance_as_at date not null, statement_closing_as_at date, change_note text not null,
 changed_by uuid references auth.users(id) on delete set null, changed_at timestamptz not null default now()
);
alter table public.cash_account_period_balances enable row level security;
alter table public.cash_account_period_balance_audit enable row level security;
drop policy if exists cash_account_period_balances_read_staff on public.cash_account_period_balances;
create policy cash_account_period_balances_read_staff on public.cash_account_period_balances for select to authenticated using (exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.business_id=cash_account_period_balances.business_id and r.role_code in('owner','accountant','administrator')));
drop policy if exists cash_account_period_balance_audit_read_staff on public.cash_account_period_balance_audit;
create policy cash_account_period_balance_audit_read_staff on public.cash_account_period_balance_audit for select to authenticated using (exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.business_id=cash_account_period_balance_audit.business_id and r.role_code in('owner','accountant','administrator')));
create or replace function public.owner_set_cash_account_period_balances(p_business_id uuid,p_cash_account_id uuid,p_period_id uuid,p_opening_balance_kes numeric,p_statement_closing_balance_kes numeric,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_period public.accounting_periods%rowtype; v_account public.cash_accounts%rowtype; v_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.user_roles where user_id=v_uid and business_id=p_business_id and role_code='owner') then raise exception 'Only the owner can set or amend bank balances' using errcode='42501'; end if;
 select * into v_period from public.accounting_periods where id=p_period_id and business_id=p_business_id;
 if not found then raise exception 'Accounting period not found'; end if;
 if v_period.status<>'open' then raise exception 'Balances cannot be amended after period closure'; end if;
 select * into v_account from public.cash_accounts where id=p_cash_account_id and business_id=p_business_id and is_active=true;
 if not found then raise exception 'Active cash or bank account not found'; end if;
 if v_account.currency_code<>'KES' then raise exception 'Balance comparison currently supports KES accounts only'; end if;
 if p_opening_balance_kes is null or p_opening_balance_kes<0 then raise exception 'Enter a valid non-negative opening balance'; end if;
 if p_statement_closing_balance_kes is not null and p_statement_closing_balance_kes<0 then raise exception 'Statement closing balance cannot be negative'; end if;
 if length(btrim(coalesce(p_note,'')))<5 then raise exception 'A reason of at least five characters is required'; end if;
 insert into public.cash_account_period_balances(business_id,cash_account_id,accounting_period_id,opening_balance_kes,statement_closing_balance_kes,opening_balance_as_at,statement_closing_as_at,note,updated_by,updated_at)
 values(p_business_id,p_cash_account_id,p_period_id,p_opening_balance_kes,p_statement_closing_balance_kes,v_period.starts_on,case when p_statement_closing_balance_kes is null then null else v_period.ends_on end,btrim(p_note),v_uid,now())
 on conflict(cash_account_id,accounting_period_id) do update set opening_balance_kes=excluded.opening_balance_kes,statement_closing_balance_kes=excluded.statement_closing_balance_kes,opening_balance_as_at=excluded.opening_balance_as_at,statement_closing_as_at=excluded.statement_closing_as_at,note=excluded.note,updated_by=excluded.updated_by,updated_at=now() returning id into v_id;
 insert into public.cash_account_period_balance_audit(business_id,cash_account_id,accounting_period_id,opening_balance_kes,statement_closing_balance_kes,opening_balance_as_at,statement_closing_as_at,change_note,changed_by)
 values(p_business_id,p_cash_account_id,p_period_id,p_opening_balance_kes,p_statement_closing_balance_kes,v_period.starts_on,case when p_statement_closing_balance_kes is null then null else v_period.ends_on end,btrim(p_note),v_uid);
 return v_id;
end $$;
revoke all on function public.owner_set_cash_account_period_balances(uuid,uuid,uuid,numeric,numeric,text) from public,anon;
grant execute on function public.owner_set_cash_account_period_balances(uuid,uuid,uuid,numeric,numeric,text) to authenticated;