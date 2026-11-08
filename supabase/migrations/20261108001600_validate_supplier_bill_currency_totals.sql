-- Keep line totals in both source currency and KES equal to the bill header.
create or replace function public.owner_create_supplier_bill(
 p_business_id uuid,p_location_id uuid,p_supplier_id uuid,p_purchase_order_id uuid,
 p_supplier_invoice_number text,p_bill_date date,p_due_date date,p_currency_code char(3),
 p_exchange_rate_to_kes numeric,p_total_amount numeric,p_total_kes numeric,p_notes text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_line jsonb; v_no integer:=0; v_sum numeric(18,2):=0; v_original_sum numeric(18,2):=0;
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
  v_original_sum:=v_original_sum+(v_line->>'amount')::numeric;
 end loop;
 if abs(v_sum-p_total_kes)>0.01 then raise exception 'Bill line KES total (%) does not equal bill total (%)',v_sum,p_total_kes; end if;
 if abs(v_original_sum-p_total_amount)>0.01 then raise exception 'Bill line currency total (%) does not equal invoice total (%)',v_original_sum,p_total_amount; end if;
 return v_id;
end; $$;
revoke all on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.owner_create_supplier_bill(uuid,uuid,uuid,uuid,text,date,date,char,numeric,numeric,numeric,text,jsonb) to authenticated;

