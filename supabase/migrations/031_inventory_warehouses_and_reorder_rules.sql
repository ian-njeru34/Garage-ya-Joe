-- Owner-managed warehouses and per-warehouse reorder points.
create table public.inventory_reorder_rules (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  warehouse_id uuid not null,
  product_id uuid not null,
  reorder_point numeric(18,3) not null default 0 check (reorder_point >= 0),
  reorder_quantity numeric(18,3) not null default 0 check (reorder_quantity >= 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint inventory_reorder_rules_business_warehouse_product_key unique (business_id,warehouse_id,product_id),
  constraint inventory_reorder_rules_warehouse_fk foreign key (business_id,warehouse_id)
    references public.warehouses(business_id,id) on delete cascade,
  constraint inventory_reorder_rules_product_fk foreign key (business_id,product_id)
    references public.products(business_id,id) on delete cascade
);

create index inventory_reorder_rules_active_idx
  on public.inventory_reorder_rules(business_id,warehouse_id,product_id)
  where is_active;

alter table public.inventory_reorder_rules enable row level security;
create policy "Inventory staff can view reorder rules"
  on public.inventory_reorder_rules for select to authenticated
  using (
    private.has_business_permission(
      business_id,'inventory.view',
      (select w.location_id from public.warehouses w where w.id=inventory_reorder_rules.warehouse_id)
    )
  );
revoke all on public.inventory_reorder_rules from anon,authenticated;
grant select on public.inventory_reorder_rules to authenticated;

create or replace function public.create_inventory_warehouse(
  p_business_id uuid,
  p_location_id uuid,
  p_code text,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if nullif(trim(p_code),'') is null or nullif(trim(p_name),'') is null then
    raise exception 'Warehouse code and name are required';
  end if;
  if not exists (
    select 1 from public.locations l
    where l.id=p_location_id and l.business_id=p_business_id and l.is_active
  ) then raise exception 'Choose an active branch belonging to this business'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',p_location_id) then
    raise exception 'Not authorized to manage inventory at this branch' using errcode='42501';
  end if;
  insert into public.warehouses(business_id,location_id,code,name,is_active)
  values(p_business_id,p_location_id,upper(trim(p_code)),trim(p_name),true)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.set_inventory_reorder_rule(
  p_business_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid,
  p_reorder_point numeric,
  p_reorder_quantity numeric,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_location uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_reorder_point is null or p_reorder_point<0 or p_reorder_quantity is null or p_reorder_quantity<0 then
    raise exception 'Reorder point and reorder quantity must be zero or greater';
  end if;
  select location_id into v_location
  from public.warehouses
  where id=p_warehouse_id and business_id=p_business_id and is_active
  for share;
  if not found then raise exception 'Active warehouse not found'; end if;
  if not private.has_business_permission(p_business_id,'inventory.manage',v_location) then
    raise exception 'Not authorized to manage inventory at this warehouse' using errcode='42501';
  end if;
  if not exists(select 1 from public.products p where p.id=p_product_id and p.business_id=p_business_id and p.track_inventory and p.is_active) then
    raise exception 'Active inventory-tracked product not found';
  end if;
  insert into public.inventory_reorder_rules(
    business_id,warehouse_id,product_id,reorder_point,reorder_quantity,is_active,updated_by,updated_at
  ) values(
    p_business_id,p_warehouse_id,p_product_id,p_reorder_point,p_reorder_quantity,coalesce(p_is_active,true),v_uid,now()
  )
  on conflict(business_id,warehouse_id,product_id) do update set
    reorder_point=excluded.reorder_point,
    reorder_quantity=excluded.reorder_quantity,
    is_active=excluded.is_active,
    updated_by=v_uid,
    updated_at=now()
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_inventory_warehouse(uuid,uuid,text,text) from public,anon;
revoke all on function public.set_inventory_reorder_rule(uuid,uuid,uuid,numeric,numeric,boolean) from public,anon;
grant execute on function public.create_inventory_warehouse(uuid,uuid,text,text) to authenticated;
grant execute on function public.set_inventory_reorder_rule(uuid,uuid,uuid,numeric,numeric,boolean) to authenticated;
