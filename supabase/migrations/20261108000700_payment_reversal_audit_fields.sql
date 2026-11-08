alter table public.customer_payments
 add column if not exists reversal_reason text,
 add column if not exists reversed_at timestamptz,
 add column if not exists reversed_by uuid references public.profiles(id) on delete set null,
 add column if not exists reversal_journal_entry_id uuid;
alter table public.supplier_payments
 add column if not exists reversal_reason text,
 add column if not exists reversed_at timestamptz,
 add column if not exists reversed_by uuid references public.profiles(id) on delete set null,
 add column if not exists reversal_journal_entry_id uuid;

create or replace function public.owner_reverse_supplier_payment(p_business_id uuid,p_payment_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_payment public.supplier_payments%rowtype; v_reversal uuid;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_payment from public.supplier_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Supplier payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_payment.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_payment.status<>'recorded' then raise exception 'Only recorded supplier payments can be reversed'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
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

create or replace function public.owner_reverse_customer_payment(p_business_id uuid,p_payment_id uuid,p_reversal_number text,p_reversal_date date,p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_payment public.customer_payments%rowtype; v_invoice public.invoices%rowtype;
 v_reversal uuid; v_new_paid numeric(18,2); v_new_paid_kes numeric(18,2); v_status text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_payment from public.customer_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Customer payment not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_payment.location_id) then raise exception 'Finance management permission required' using errcode='42501'; end if;
 if v_payment.status<>'recorded' then raise exception 'Only recorded customer payments can be reversed'; end if;
 if nullif(btrim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 if v_payment.invoice_id is not null then
  select * into v_invoice from public.invoices where business_id=p_business_id and id=v_payment.invoice_id for update;
  if not found then raise exception 'Linked invoice not found'; end if;
  v_new_paid:=v_invoice.amount_paid-v_payment.amount; v_new_paid_kes:=v_invoice.amount_paid_kes-v_payment.amount_kes;
  if v_new_paid<0 or v_new_paid_kes<0 then raise exception 'Invoice payment totals are inconsistent; reversal stopped'; end if;
  v_status:=case when v_new_paid<=0 then case when v_invoice.due_date is not null and v_invoice.due_date<coalesce(p_reversal_date,current_date) then 'overdue' else 'issued' end
   when v_invoice.due_date is not null and v_invoice.due_date<coalesce(p_reversal_date,current_date) then 'overdue' else 'partially_paid' end;
  update public.invoices set amount_paid=v_new_paid,amount_paid_kes=v_new_paid_kes,status=v_status,
   paid_at=case when v_new_paid<=0 then null else paid_at end,updated_at=now(),updated_by=v_uid
   where business_id=p_business_id and id=v_payment.invoice_id;
 end if;
 if v_payment.journal_entry_id is not null then
  v_reversal:=private.reverse_journal_entry_impl(p_business_id,v_payment.journal_entry_id,p_reversal_number,coalesce(p_reversal_date,current_date),p_reason);
  perform private.post_journal_entry_impl(p_business_id,v_reversal);
 end if;
 update public.customer_payments set status='reversed',reversal_reason=btrim(p_reason),reversed_at=now(),reversed_by=v_uid,reversal_journal_entry_id=v_reversal
 where business_id=p_business_id and id=p_payment_id;
 return v_reversal;
end; $$;
revoke all on function public.owner_reverse_customer_payment(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.owner_reverse_customer_payment(uuid,uuid,text,date,text) to authenticated;
