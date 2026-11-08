create table if not exists public.accounting_period_reconciliations (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 accounting_period_id uuid not null references public.accounting_periods(id) on delete restrict,
 period_name text not null,
 starts_on date not null,
 ends_on date not null,
 statement_line_count integer not null default 0,
 verified_line_count integer not null default 0,
 classified_line_count integer not null default 0,
 posted_journal_count integer not null default 0,
 total_debits_kes numeric(18,2) not null default 0,
 total_credits_kes numeric(18,2) not null default 0,
 closed_by uuid references auth.users(id) on delete set null,
 closed_at timestamptz not null default now(),
 close_note text,
 unique(accounting_period_id)
);
alter table public.accounting_period_reconciliations enable row level security;
drop policy if exists accounting_period_reconciliations_read_staff on public.accounting_period_reconciliations;
create policy accounting_period_reconciliations_read_staff on public.accounting_period_reconciliations
 for select to authenticated using (
 exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.business_id=accounting_period_reconciliations.business_id and r.role_code in('owner','accountant','administrator'))
);
create or replace function public.owner_close_accounting_period(p_business_id uuid,p_period_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_uid uuid:=auth.uid();
 v_period public.accounting_periods%rowtype;
 v_unresolved integer:=0;
 v_drafts integer:=0;
 v_bad_journals integer:=0;
 v_lines integer:=0;
 v_verified integer:=0;
 v_classified integer:=0;
 v_journals integer:=0;
 v_debits numeric(18,2):=0;
 v_credits numeric(18,2):=0;
 v_balance_variances integer:=0;
 v_missing_balances integer:=0;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 if not exists(select 1 from public.user_roles where user_id=v_uid and business_id=p_business_id and role_code='owner') then
  raise exception 'Only the owner can close an accounting period' using errcode='42501';
 end if;
 select * into v_period from public.accounting_periods where id=p_period_id and business_id=p_business_id for update;
 if not found then raise exception 'Accounting period not found';end if;
 if v_period.status<>'open' then raise exception 'Only an open accounting period can be closed';end if;
 select count(*)::integer into v_unresolved
 from public.payment_statement_lines l join public.payment_statement_imports i on i.id=l.import_id
 where l.business_id=p_business_id and l.transaction_date between v_period.starts_on and v_period.ends_on
 and l.status not in('verified','classified');
 if v_unresolved>0 then raise exception 'Cannot close period: % statement entries still require review',v_unresolved;end if;
 select count(*)::integer into v_drafts from public.journal_entries
 where business_id=p_business_id and entry_date between v_period.starts_on and v_period.ends_on and status='draft';
 if v_drafts>0 then raise exception 'Cannot close period: % journal entries are still drafts',v_drafts;end if;
 select count(*)::integer,coalesce(sum(t.debits),0),coalesce(sum(t.credits),0)
 into v_journals,v_debits,v_credits
 from (
  select e.id,sum(l.debit_kes) debits,sum(l.credit_kes) credits
  from public.journal_entries e join public.journal_lines l on l.journal_entry_id=e.id
  where e.business_id=p_business_id and e.entry_date between v_period.starts_on and v_period.ends_on and e.status='posted'
  group by e.id
 ) t;
 select count(*)::integer into v_bad_journals from (
  select e.id from public.journal_entries e join public.journal_lines l on l.journal_entry_id=e.id
  where e.business_id=p_business_id and e.entry_date between v_period.starts_on and v_period.ends_on and e.status='posted'
  group by e.id having abs(sum(l.debit_kes)-sum(l.credit_kes))>0.01
 ) bad;
 if v_bad_journals>0 or abs(v_debits-v_credits)>0.01 then raise exception 'Cannot close period: posted journals are not balanced';end if;
 select count(*)::integer,count(*) filter(where status='verified')::integer,count(*) filter(where status='classified')::integer
 into v_lines,v_verified,v_classified
 from public.payment_statement_lines where business_id=p_business_id and transaction_date between v_period.starts_on and v_period.ends_on;
 select count(*)::integer into v_missing_balances
 from (select distinct l.cash_account_id from public.payment_statement_lines l where l.business_id=p_business_id and l.transaction_date between v_period.starts_on and v_period.ends_on and l.status in('verified','classified')) used_accounts
 left join public.cash_account_period_balances b on b.business_id=p_business_id and b.cash_account_id=used_accounts.cash_account_id and b.accounting_period_id=p_period_id
 where b.id is null or b.statement_closing_balance_kes is null;
 if v_missing_balances>0 then raise exception 'Cannot close period: % cash or bank accounts with statement activity are missing confirmed statement closing balances',v_missing_balances; end if;
 select count(*)::integer into v_balance_variances from public.cash_account_period_balances b
 join public.cash_accounts ca on ca.id=b.cash_account_id and ca.business_id=p_business_id
 left join (select e.accounting_period_id,jl.account_id,sum(jl.debit_kes-jl.credit_kes) movement_kes from public.journal_entries e join public.journal_lines jl on jl.journal_entry_id=e.id where e.business_id=p_business_id and e.status='posted' and e.accounting_period_id=p_period_id group by e.accounting_period_id,jl.account_id) movement
 on movement.accounting_period_id=b.accounting_period_id and movement.account_id=ca.ledger_account_id
 where b.business_id=p_business_id and b.accounting_period_id=p_period_id and b.statement_closing_balance_kes is not null and abs(b.opening_balance_kes+coalesce(movement.movement_kes,0)-b.statement_closing_balance_kes)>0.01;
 if v_balance_variances>0 then raise exception 'Cannot close period: % cash or bank account balances do not agree with posted ledger activity',v_balance_variances; end if;
 insert into public.accounting_period_reconciliations(business_id,accounting_period_id,period_name,starts_on,ends_on,statement_line_count,verified_line_count,classified_line_count,posted_journal_count,total_debits_kes,total_credits_kes,closed_by,close_note)
 values(p_business_id,p_period_id,v_period.period_name,v_period.starts_on,v_period.ends_on,v_lines,v_verified,v_classified,v_journals,v_debits,v_credits,v_uid,nullif(btrim(coalesce(p_note,'')),''));
 update public.accounting_periods set status='closed',closed_at=now(),closed_by=v_uid where id=p_period_id and business_id=p_business_id;
 return jsonb_build_object('period_id',p_period_id,'statement_lines',v_lines,'verified_lines',v_verified,'classified_lines',v_classified,'posted_journals',v_journals,'debits_kes',v_debits,'credits_kes',v_credits,'closed_at',now());
end $$;
revoke all on function public.owner_close_accounting_period(uuid,uuid,text) from public,anon;
grant execute on function public.owner_close_accounting_period(uuid,uuid,text) to authenticated;
