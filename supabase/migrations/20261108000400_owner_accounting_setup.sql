create or replace function public.owner_initialize_accounting(p_business_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_year integer := extract(year from current_date)::integer;
  v_period_id uuid;
  v_accounts integer;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not private.has_business_permission(p_business_id,'finance.manage') then
    raise exception 'Finance management permission required' using errcode='42501';
  end if;

  insert into public.chart_of_accounts(business_id,account_code,account_name,account_type,is_control_account,is_system_account)
  values
    (p_business_id,'1000','Cash on hand','asset',false,true),
    (p_business_id,'1010','Bank accounts','asset',false,true),
    (p_business_id,'1020','Mobile money wallets','asset',false,true),
    (p_business_id,'1030','Card clearing','asset',false,true),
    (p_business_id,'1100','Accounts receivable','asset',true,true),
    (p_business_id,'1200','Inventory','asset',true,true),
    (p_business_id,'2000','Accounts payable','liability',true,true),
    (p_business_id,'2100','Tax payable','liability',false,true),
    (p_business_id,'3000','Owner capital','equity',false,true),
    (p_business_id,'3100','Retained earnings','equity',false,true),
    (p_business_id,'4000','Workshop labour income','income',false,true),
    (p_business_id,'4100','Parts sales income','income',false,true),
    (p_business_id,'4200','Vehicle sales income','income',false,true),
    (p_business_id,'5000','Cost of goods sold','expense',false,true),
    (p_business_id,'5100','Direct labour expense','expense',false,true),
    (p_business_id,'6000','Operating expenses','expense',false,true)
  on conflict (business_id,account_code) do nothing;

  insert into public.accounting_periods(business_id,period_name,starts_on,ends_on,status)
  values(p_business_id,'FY'||v_year,make_date(v_year,1,1),make_date(v_year,12,31),'open')
  on conflict (business_id,period_name) do nothing;

  select id into v_period_id from public.accounting_periods
  where business_id=p_business_id and period_name='FY'||v_year;

  select count(*)::integer into v_accounts from public.chart_of_accounts
  where business_id=p_business_id;

  return jsonb_build_object('accounting_period_id',v_period_id,'period_name','FY'||v_year,'chart_account_count',v_accounts);
end;
$$;
revoke all on function public.owner_initialize_accounting(uuid) from public,anon;
grant execute on function public.owner_initialize_accounting(uuid) to authenticated;
