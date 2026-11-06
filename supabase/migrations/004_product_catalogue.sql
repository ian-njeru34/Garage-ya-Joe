-- Garage ya Joe: product catalogue, part numbers, images and vehicle fitment.
-- Public users can browse active catalogue entries; only database-authorized staff can manage them.

create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  parent_id uuid,
  name text not null,
  slug text not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_categories_name_not_blank check (length(trim(name)) > 0),
  constraint product_categories_slug_not_blank check (length(trim(slug)) > 0),
  unique (business_id, id),
  unique (business_id, slug),
  constraint product_categories_parent_fk
    foreign key (business_id, parent_id)
    references public.product_categories (business_id, id) on delete restrict
);

alter table public.products
  add column category_id uuid,
  add column brand_part_number text,
  add column retail_price numeric(18,2),
  add column price_currency char(3) not null default 'KES'
    references public.currencies(code),
  add column product_status text not null default 'active'
    check (product_status in ('active','discontinued','archived')),
  add column is_special_order boolean not null default false,
  add column track_inventory boolean not null default true,
  add column unit_of_measure text not null default 'piece',
  add column search_keywords text,
  add constraint products_business_id_id_unique unique (business_id, id),
  add constraint products_category_fk
    foreign key (business_id, category_id)
    references public.product_categories (business_id, id) on delete restrict,
  add constraint products_retail_price_check
    check (retail_price is null or retail_price >= 0),
  add constraint products_unit_not_blank check (length(trim(unit_of_measure)) > 0);

create index products_business_name_search_idx
  on public.products (business_id, lower(name));
create index products_business_brand_idx
  on public.products (business_id, lower(brand))
  where brand is not null;
create index products_business_oem_idx
  on public.products (business_id, upper(oem_number))
  where oem_number is not null;
create index products_business_category_idx
  on public.products (business_id, category_id);
create index products_public_catalogue_idx
  on public.products (business_id, product_status, name)
  where is_active = true;

create table public.product_part_numbers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  product_id uuid not null,
  part_number text not null,
  normalized_part_number text generated always as (
    upper(regexp_replace(part_number, '[^A-Za-z0-9]', '', 'g'))
  ) stored,
  number_type text not null default 'oem'
    check (number_type in ('oem','manufacturer','aftermarket','interchange','supplier')),
  brand text,
  is_primary boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  constraint product_part_numbers_not_blank check (length(trim(part_number)) > 0),
  constraint product_part_numbers_product_fk
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create unique index product_part_numbers_unique_idx
  on public.product_part_numbers (business_id, normalized_part_number, coalesce(brand, ''))
;
create unique index product_part_numbers_one_primary_idx
  on public.product_part_numbers (product_id)
  where is_primary = true;
create index product_part_numbers_product_idx
  on public.product_part_numbers (business_id, product_id);

-- Vehicle fitment is deliberately descriptive rather than tied to a single vehicle database provider.
create table public.product_vehicle_compatibility (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  product_id uuid not null,
  vehicle_make text not null,
  vehicle_model text not null,
  model_variant text,
  year_from smallint,
  year_to smallint,
  engine_code text,
  engine_capacity_cc integer,
  fuel_type text,
  notes text,
  created_at timestamptz not null default now(),
  constraint product_fitment_make_not_blank check (length(trim(vehicle_make)) > 0),
  constraint product_fitment_model_not_blank check (length(trim(vehicle_model)) > 0),
  constraint product_fitment_year_check check (
    (year_from is null or year_from between 1900 and 2100)
    and (year_to is null or year_to between 1900 and 2100)
    and (year_from is null or year_to is null or year_to >= year_from)
  ),
  constraint product_fitment_engine_capacity_check
    check (engine_capacity_cc is null or engine_capacity_cc > 0),
  constraint product_fitment_product_fk
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create index product_fitment_vehicle_lookup_idx
  on public.product_vehicle_compatibility
    (business_id, lower(vehicle_make), lower(vehicle_model), year_from, year_to);
create index product_fitment_product_idx
  on public.product_vehicle_compatibility (business_id, product_id);

-- Image metadata only. Actual files are stored in Supabase Storage with policies configured separately.
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  product_id uuid not null,
  storage_path text not null,
  alt_text text,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint product_images_path_not_blank check (length(trim(storage_path)) > 0),
  constraint product_images_product_fk
    foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create unique index product_images_one_primary_idx
  on public.product_images (product_id)
  where is_primary = true;
create index product_images_product_order_idx
  on public.product_images (business_id, product_id, sort_order);

-- Retain the legacy products.oem_number field for compatibility with the initial scaffold.
-- New multi-number searches should use product_part_numbers.

alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.product_part_numbers enable row level security;
alter table public.product_vehicle_compatibility enable row level security;
alter table public.product_images enable row level security;

-- Public catalogue: active products/categories and their public descriptive metadata.
create policy "Public can browse active products"
  on public.products for select to anon, authenticated
  using (is_active = true and product_status = 'active');

create policy "Catalogue staff can view all products"
  on public.products for select to authenticated
  using (private.has_business_permission(business_id, 'catalogue.view'));

create policy "Catalogue staff can create products"
  on public.products for insert to authenticated
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Catalogue staff can update products"
  on public.products for update to authenticated
  using (private.has_business_permission(business_id, 'catalogue.manage'))
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Public can browse active categories"
  on public.product_categories for select to anon, authenticated
  using (
    is_active = true and exists (
      select 1 from public.products p
      where p.business_id = product_categories.business_id
        and p.category_id = product_categories.id
        and p.is_active = true
        and p.product_status = 'active'
    )
  );

create policy "Catalogue staff can view categories"
  on public.product_categories for select to authenticated
  using (private.has_business_permission(business_id, 'catalogue.view'));

create policy "Catalogue staff can create categories"
  on public.product_categories for insert to authenticated
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Catalogue staff can update categories"
  on public.product_categories for update to authenticated
  using (private.has_business_permission(business_id, 'catalogue.manage'))
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Public can browse part numbers for active products"
  on public.product_part_numbers for select to anon, authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_part_numbers.product_id
      and p.business_id = product_part_numbers.business_id
      and p.is_active = true and p.product_status = 'active'
  ));

create policy "Catalogue staff can manage part numbers"
  on public.product_part_numbers for all to authenticated
  using (private.has_business_permission(business_id, 'catalogue.manage'))
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Public can browse fitment for active products"
  on public.product_vehicle_compatibility for select to anon, authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_vehicle_compatibility.product_id
      and p.business_id = product_vehicle_compatibility.business_id
      and p.is_active = true and p.product_status = 'active'
  ));

create policy "Catalogue staff can manage fitment"
  on public.product_vehicle_compatibility for all to authenticated
  using (private.has_business_permission(business_id, 'catalogue.manage'))
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

create policy "Public can browse images for active products"
  on public.product_images for select to anon, authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_images.product_id
      and p.business_id = product_images.business_id
      and p.is_active = true and p.product_status = 'active'
  ));

create policy "Catalogue staff can manage product images"
  on public.product_images for all to authenticated
  using (private.has_business_permission(business_id, 'catalogue.manage'))
  with check (private.has_business_permission(business_id, 'catalogue.manage'));

-- Grant only the operations that have corresponding RLS policies.
grant select on public.products, public.product_categories,
  public.product_part_numbers, public.product_vehicle_compatibility, public.product_images
  to anon, authenticated;
grant insert, update on public.products, public.product_categories to authenticated;
grant insert, update, delete on public.product_part_numbers,
  public.product_vehicle_compatibility, public.product_images to authenticated;
