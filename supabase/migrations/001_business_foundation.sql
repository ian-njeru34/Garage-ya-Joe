-- Garage ya Joe: initial business foundation.
-- Review and apply manually in the Supabase SQL editor; this file is not auto-applied.
create extension if not exists pgcrypto;

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  base_currency char(3) not null default 'KES',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  code text not null,
  name text not null,
  location_type text not null default 'branch' check (location_type in ('branch','warehouse','garage','office')),
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, code)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  profile_id uuid references public.profiles(id) on delete set null,
  customer_type text not null default 'individual' check (customer_type in ('individual','business')),
  display_name text not null,
  email text,
  phone text,
  tax_identifier text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists customers_business_phone_idx on public.customers (business_id, phone);
create index if not exists customers_business_email_idx on public.customers (business_id, lower(email));

create table if not exists public.currencies (
  code char(3) primary key,
  name text not null,
  symbol text,
  minor_units smallint not null default 2 check (minor_units between 0 and 4),
  is_active boolean not null default true
);
insert into public.currencies (code,name,symbol) values
 ('KES','Kenyan Shilling','KSh'),('USD','US Dollar','$'),('EUR','Euro','€'),('GBP','Pound Sterling','£')
on conflict (code) do nothing;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  sku text,
  name text not null,
  description text,
  product_type text not null default 'spare_part' check (product_type in ('spare_part','consumable','service_item')),
  brand text,
  oem_number text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, sku)
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  location_id uuid references public.locations(id) on delete restrict,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, code)
);

create table if not exists public.inventory_balances (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_on_hand numeric(18,3) not null default 0 check (quantity_on_hand >= 0),
  quantity_reserved numeric(18,3) not null default 0 check (quantity_reserved >= 0),
  updated_at timestamptz not null default now(),
  unique (warehouse_id, product_id),
  check (quantity_reserved <= quantity_on_hand)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null check (movement_type in ('receipt','sale','reservation','release','transfer_in','transfer_out','adjustment','return')),
  quantity_delta numeric(18,3) not null check (quantity_delta <> 0),
  unit_cost numeric(18,4),
  currency_code char(3) references public.currencies(code),
  reference_type text,
  reference_id uuid,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_product_date_idx on public.stock_movements (product_id, created_at desc);
create index if not exists stock_movements_warehouse_date_idx on public.stock_movements (warehouse_id, created_at desc);

-- Secure by default. Add business/location-scoped policies in a reviewed later migration.
alter table public.businesses enable row level security;
alter table public.locations enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.currencies enable row level security;
alter table public.products enable row level security;
alter table public.warehouses enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.stock_movements enable row level security;
