-- Manual matching of an unmatched statement line to an existing manual payment.
-- Strict account/amount/currency/date checks; reference overrides require owner authority and an audit reason.
create or replace function public.owner_manual_match_statement_line(
 p_business_id uuid,p_statement_line_id uuid,p_payment_table text,p_payment_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_uid uuid:=auth.uid();v_line public.payment_statement_lines%rowtype;v_import public.payment_statement_imports%rowtype;
 v_role text;v_ref text;v_norm text;v_payment_ref text;v_payment_norm text;
 v_amount numeric(18,2);v_currency text;v_date date;v_cash uuid;v_location uuid;v_status text;v_verified uuid;
 v_flow text;v_payment_exists boolean:=false;v_now timestamptz:=now();
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 if not private.has_business_permission(p_business_id,'finance.manage',null) then raise exception 'Finance management permission required' using errcode='42501';end if;
 select * into v_line from public.payment_statement_lines where id=p_statement_line_id and business_id=p_business_id for update;
 if not found then raise exception 'Statement line not found';end if;
 if v_line.status not in('unmatched','invalid_reference') then raise exception 'Only unmatched statement lines can be manually matched';end if;
 select * into v_import from public.payment_statement_imports where id=v_line.import_id and business_id=p_business_id;
 if not found then raise exception 'Statement import not found';end if;
 v_flow:=v_import.flow;
 if (v_flow='incoming' and p_payment_table<>'customer_payments') or (v_flow='outgoing' and p_payment_table<>'supplier_payments') then raise exception 'Payment type does not match the statement direction';end if;
 if p_payment_table='customer_payments' then
  select external_reference,amount,currency_code,payment_date,cash_account_id,location_id,status,verification_status into v_payment_ref,v_amount,v_currency,v_date,v_cash,v_location,v_status,v_verified from public.customer_payments where id=p_payment_id and business_id=p_business_id for update;
 elsif p_payment_table='supplier_payments' then
  select external_reference,amount,currency_code,payment_date,cash_account_id,location_id,status,verification_status into v_payment_ref,v_amount,v_currency,v_date,v_cash,v_location,v_status,v_verified from public.supplier_payments where id=p_payment_id and business_id=p_business_id for update;
 else raise exception 'Unsupported payment table';end if;
 if not found then raise exception 'Selected payment not found';end if;
 if v_status<>'recorded' or coalesce(v_verified,'pending')='verified' then raise exception 'Selected payment is not eligible for verification';end if;
 if v_cash<>v_line.cash_account_id or v_location<>v_line.location_id then raise exception 'Payment belongs to a different receiving account or branch';end if;
 if upper(v_currency)<>upper(v_line.currency_code) or round(v_amount,2)<>round(v_line.amount,2) then raise exception 'Amount or currency must match exactly';end if;
 if abs(v_date-v_line.transaction_date)>3 then raise exception 'Payment date must be within three calendar days of the statement date';end if;
 v_ref:=v_line.transaction_reference;v_norm:=v_line.normalized_reference;
 v_payment_norm:=upper(regexp_replace(coalesce(v_payment_ref,''),'[^A-Za-z0-9]','','g'));
 if length(coalesce(v_norm,''))<3 then raise exception 'Statement transaction reference is not usable for verification';end if;
 if v_norm is distinct from v_payment_norm then
  select role_code into v_role from public.user_roles where user_id=v_uid and business_id=p_business_id and role_code='owner' limit 1;
  if v_role is null then raise exception 'Only the owner can approve a manual match where transaction references differ';end if;
  if length(btrim(coalesce(p_reason,'')))<10 then raise exception 'Owner must provide an explanation of at least ten characters';end if;
 end if;
 if exists(select 1 from public.payment_verifications where business_id=p_business_id and normalized_reference=v_norm) then raise exception 'This statement reference has already been verified';end if;
 insert into public.payment_verifications(business_id,location_id,cash_account_id,normalized_reference,transaction_reference,payment_table,payment_id,statement_line_id,verified_by)
 values(p_business_id,v_line.location_id,v_line.cash_account_id,v_norm,v_ref,p_payment_table,p_payment_id,v_line.id,v_uid);
 if p_payment_table='customer_payments' then
  update public.customer_payments set verification_status='verified',verified_at=v_now,verified_by=v_uid,verification_statement_line_id=v_line.id where id=p_payment_id;
 else
  update public.supplier_payments set verification_status='verified',verified_at=v_now,verified_by=v_uid,verification_statement_line_id=v_line.id where id=p_payment_id;
 end if;
 update public.payment_statement_lines set status='verified',matched_payment_table=p_payment_table,matched_payment_id=p_payment_id,verified_at=v_now,verified_by=v_uid,review_reason=case when v_norm is distinct from v_payment_norm then 'Owner-approved manual match: '||left(btrim(p_reason),900) else 'Manually matched by finance staff after confirming amount, date and account.' end,reviewed_by=v_uid,reviewed_at=v_now where id=v_line.id;
 update public.payment_statement_imports i set
  verified_count=(select count(*) from public.payment_statement_lines l where l.import_id=i.id and l.status='verified'),
  unmatched_count=(select count(*) from public.payment_statement_lines l where l.import_id=i.id and l.status in('unmatched','invalid_reference','already_verified')),
  review_count=(select count(*) from public.payment_statement_lines l where l.import_id=i.id and l.status not in('verified','unmatched','invalid_reference','already_verified','classified')),
  status=case when exists(select 1 from public.payment_statement_lines l where l.import_id=i.id and l.status not in('verified','classified')) then 'partial' else 'processed' end
 where i.id=v_line.import_id;
 return jsonb_build_object('verified',true,'payment_table',p_payment_table,'payment_id',p_payment_id);
end $$;
revoke all on function public.owner_manual_match_statement_line(uuid,uuid,text,uuid,text) from public,anon;
grant execute on function public.owner_manual_match_statement_line(uuid,uuid,text,uuid,text) to authenticated;
