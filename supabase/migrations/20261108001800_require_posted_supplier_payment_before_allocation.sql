-- Only allocate supplier payments whose cash/AP journal has actually posted.
create or replace function public.owner_allocate_supplier_payment(p_business_id uuid,p_payment_id uuid,p_supplier_bill_id uuid,p_amount_kes numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_pay public.supplier_payments%rowtype; v_bill public.supplier_bills%rowtype; v_alloc numeric(18,2); v_unallocated numeric(18,2); v_outstanding numeric(18,2); v_amount numeric(18,2); v_id uuid:=gen_random_uuid();
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_pay from public.supplier_payments where business_id=p_business_id and id=p_payment_id for update;
 if not found then raise exception 'Supplier payment not found'; end if;
 select * into v_bill from public.supplier_bills where business_id=p_business_id and id=p_supplier_bill_id for update;
 if not found then raise exception 'Supplier bill not found'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage',v_pay.location_id)
  or not private.has_business_permission(p_business_id,'finance.manage',v_bill.location_id) then
  raise exception 'Finance management permission is required for both payment and bill branches' using errcode='42501';
 end if;
 if v_pay.status<>'recorded' then raise exception 'Only recorded supplier payments can be allocated'; end if;
 if v_pay.journal_entry_id is null or not exists(select 1 from public.journal_entries je where je.business_id=p_business_id and je.id=v_pay.journal_entry_id and je.status='posted') then raise exception 'Supplier payment must have a posted ledger journal before it can be allocated'; end if;
 if v_pay.supplier_id<>v_bill.supplier_id then raise exception 'Payment and bill must belong to the same supplier'; end if;
 if v_bill.status not in ('approved','partially_paid') then raise exception 'Only approved unpaid bills can receive allocations'; end if;
 if p_amount_kes is null or p_amount_kes<=0 then raise exception 'Enter a positive allocation amount'; end if;
 v_amount:=round(p_amount_kes,2);
 if v_amount<=0 then raise exception 'Allocation amount must be at least one cent'; end if;
 select coalesce(sum(amount_kes),0) into v_alloc from public.supplier_bill_payment_allocations where business_id=p_business_id and supplier_payment_id=p_payment_id and allocation_status='active';
 v_unallocated:=v_pay.amount_kes-v_alloc;
 v_outstanding:=v_bill.total_kes-v_bill.amount_paid_kes;
 if v_amount>v_unallocated+0.001 then raise exception 'Allocation exceeds the unallocated payment balance (%)',v_unallocated; end if;
 if v_amount>v_outstanding+0.001 then raise exception 'Allocation exceeds the outstanding bill balance (%)',v_outstanding; end if;
 insert into public.supplier_bill_payment_allocations(id,business_id,supplier_bill_id,supplier_payment_id,amount_kes,allocated_by)
 values(v_id,p_business_id,p_supplier_bill_id,p_payment_id,v_amount,v_uid);
 update public.supplier_bills set amount_paid_kes=amount_paid_kes+v_amount,
 status=case when amount_paid_kes+v_amount>=total_kes-0.001 then 'paid' else 'partially_paid' end,updated_at=now()
 where business_id=p_business_id and id=p_supplier_bill_id;
 return v_id;
end; $$;
revoke all on function public.owner_allocate_supplier_payment(uuid,uuid,uuid,numeric) from public,anon;
grant execute on function public.owner_allocate_supplier_payment(uuid,uuid,uuid,numeric) to authenticated;

