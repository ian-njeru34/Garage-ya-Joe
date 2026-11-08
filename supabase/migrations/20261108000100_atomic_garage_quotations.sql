-- Create a complete customer-facing garage quotation atomically.
-- The caller must hold quotations.manage for the job's location.
create or replace function public.owner_create_garage_quotation(
  p_business_id uuid,
  p_job_card_id uuid,
  p_quote_number text,
  p_valid_until date,
  p_discount_amount numeric,
  p_items jsonb,
  p_customer_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_job public.job_cards%rowtype;
  v_quote_id uuid := gen_random_uuid();
  v_subtotal numeric(18,2) := 0;
  v_discount numeric(18,2) := greatest(coalesce(p_discount_amount,0),0);
  v_tax numeric(18,2) := 0;
  v_total numeric(18,2) := 0;
  v_discount_used numeric(18,2) := 0;
  v_gross numeric(18,2);
  v_line_discount numeric(18,2);
  v_tax_rate numeric(9,4);
  v_tax_amount numeric(18,2);
  v_line_total numeric(18,2);
  v_qty numeric(18,3);
  v_price numeric(18,4);
  v_desc text;
  v_type text;
  v_uom text;
  v_product_id uuid;
  v_count integer := 0;
  v_i integer := 0;
  v_item jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_number text := nullif(btrim(p_quote_number),'');
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if v_number is null then raise exception 'Quotation number is required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Add at least one quotation line';
  end if;
  if v_discount < 0 then raise exception 'Discount cannot be negative'; end if;
  if p_valid_until is not null and p_valid_until < current_date then
    raise exception 'Quotation validity date cannot be in the past';
  end if;

  select * into v_job
  from public.job_cards
  where business_id=p_business_id and id=p_job_card_id
  for update;
  if not found then raise exception 'Job card not found'; end if;
  if not private.has_business_permission(p_business_id,'quotations.manage',v_job.location_id) then
    raise exception 'Quotation management permission required' using errcode='42501';
  end if;
  if v_job.status not in ('draft','awaiting_approval') then
    raise exception 'Only jobs awaiting customer approval can be quoted';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := nullif(v_item->>'quantity','')::numeric;
    v_price := nullif(v_item->>'unit_price','')::numeric;
    v_tax_rate := coalesce(nullif(v_item->>'tax_rate','')::numeric,0);
    v_desc := nullif(btrim(v_item->>'description'),'');
    v_type := coalesce(nullif(v_item->>'item_type',''),'part');
    v_uom := coalesce(nullif(v_item->>'unit_of_measure',''),'piece');
    if v_qty is null or v_qty <= 0 or v_qty > 1000000 then raise exception 'Each line needs a valid positive quantity'; end if;
    if v_price is null or v_price < 0 or v_price > 100000000 then raise exception 'Each line needs a valid non-negative KSh unit price'; end if;
    if v_desc is null then raise exception 'Every quotation line needs a description'; end if;
    if v_type not in ('part','labour','service','fee','freight','other') then raise exception 'Invalid quotation line type'; end if;
    if v_tax_rate < 0 or v_tax_rate > 100 then raise exception 'Tax rate must be between 0 and 100 percent'; end if;
    v_gross := round(v_qty*v_price,2);
    v_subtotal := v_subtotal + v_gross;
    v_count := v_count + 1;
  end loop;
  if v_subtotal <= 0 then raise exception 'Quotation total must be greater than zero'; end if;
  if v_discount > v_subtotal then raise exception 'Discount cannot exceed the subtotal'; end if;

  insert into public.quotations(
    id,business_id,location_id,quote_number,customer_id,vehicle_id,job_card_id,quote_type,status,
    currency_code,exchange_rate_to_kes,subtotal_amount,discount_amount,tax_amount,total_amount,
    subtotal_kes,discount_kes,tax_kes,total_kes,customer_notes,issue_date,valid_until,sent_at,created_by,updated_by
  ) values (
    v_quote_id,p_business_id,v_job.location_id,v_number,v_job.customer_id,v_job.vehicle_id,v_job.id,
    'garage','sent','KES',1,v_subtotal,v_discount,0,0,v_subtotal,v_discount,0,0,
    nullif(btrim(coalesce(p_customer_notes,'')),''),current_date,p_valid_until,now(),v_uid,v_uid
  );

  v_i := 0;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_i := v_i + 1;
    v_qty := (v_item->>'quantity')::numeric;
    v_price := (v_item->>'unit_price')::numeric;
    v_tax_rate := coalesce(nullif(v_item->>'tax_rate','')::numeric,0);
    v_desc := btrim(v_item->>'description');
    v_type := coalesce(nullif(v_item->>'item_type',''),'part');
    v_uom := coalesce(nullif(v_item->>'unit_of_measure',''),'piece');
    v_gross := round(v_qty*v_price,2);
    if v_i = v_count then
      v_line_discount := v_discount - v_discount_used;
    else
      v_line_discount := case when v_subtotal=0 then 0 else round(v_discount*v_gross/v_subtotal,2) end;
      v_discount_used := v_discount_used + v_line_discount;
    end if;
    v_tax_amount := round((v_gross-v_line_discount)*v_tax_rate/100,2);
    v_line_total := v_gross-v_line_discount+v_tax_amount;
    v_tax := v_tax + v_tax_amount;
    v_total := v_total + v_line_total;
    v_product_id := nullif(v_item->>'product_id','')::uuid;

    insert into public.quotation_items(
      business_id,quotation_id,line_number,item_type,product_id,description,quantity,unit_of_measure,
      unit_price,discount_amount,tax_rate,tax_amount,line_total,
      unit_price_kes,discount_kes,tax_kes,line_total_kes,notes
    ) values (
      p_business_id,v_quote_id,v_i,v_type,v_product_id,v_desc,v_qty,v_uom,
      v_price,v_line_discount,v_tax_rate,v_tax_amount,v_line_total,
      v_price,v_line_discount,v_tax_amount,v_line_total,nullif(btrim(coalesce(v_item->>'notes','')),'')
    );
  end loop;

  update public.quotations
  set tax_amount=v_tax,total_amount=v_total,tax_kes=v_tax,total_kes=v_total,updated_at=now()
  where business_id=p_business_id and id=v_quote_id;

  insert into public.quotation_status_history(
    business_id,quotation_id,previous_status,new_status,changed_by,change_source,reason
  ) values (
    p_business_id,v_quote_id,'draft','sent',v_uid,'staff','Sent to customer for approval'
  );

  return v_quote_id;
end;
$$;

revoke all on function public.owner_create_garage_quotation(uuid,uuid,text,date,numeric,jsonb,text) from public,anon;
grant execute on function public.owner_create_garage_quotation(uuid,uuid,text,date,numeric,jsonb,text) to authenticated;