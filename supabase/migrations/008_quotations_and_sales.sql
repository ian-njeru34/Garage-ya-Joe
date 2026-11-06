-- Garage ya Joe: quotations, sales orders and invoices.
-- Prices and tax are immutable snapshots in the transaction currency and KES reporting currency.
-- Payment collection and double-entry accounting are implemented in migration 009.

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  quote_number text not null,
  customer_id uuid not null,
  vehicle_id uuid,
  job_card_id uuid,
  quote_type text not null default 'general'
    check (quote_type in ('garage','spare_parts','general','import')),
  status text not null default 'draft'
    check (status in ('draft','sent','accepted','rejected','expired','converted','cancelled')),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  subtotal_amount numeric(18,2) not null default 0 check (subtotal_amount >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  subtotal_kes numeric(18,2) not null default 0 check (subtotal_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  total_kes numeric(18,2) not null default 0 check (total_kes >= 0),
  customer_notes text,
  internal_notes text,
  issue_date date,
  valid_until date,
  sent_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  converted_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotations_number_not_blank check (length(trim(quote_number)) > 0),
  constraint quotations_discount_limit check (discount_amount <= subtotal_amount),
  constraint quotations_discount_kes_limit check (discount_kes <= subtotal_kes),
  constraint quotations_validity_check check (valid_until is null or issue_date is null or valid_until >= issue_date),
  unique (business_id, id),
  unique (business_id, quote_number),
  foreign key (business_id, location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id, customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id, vehicle_id) references public.vehicles(business_id,id) on delete restrict,
  foreign key (business_id, job_card_id) references public.job_cards(business_id,id) on delete restrict
);

create index quotations_location_status_idx on public.quotations(business_id,location_id,status,created_at desc);
create index quotations_customer_date_idx on public.quotations(business_id,customer_id,created_at desc);
create index quotations_job_card_idx on public.quotations(business_id,job_card_id) where job_card_id is not null;

create table public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quotation_id uuid not null,
  line_number integer not null check (line_number > 0),
  item_type text not null default 'part'
    check (item_type in ('part','labour','service','fee','freight','other')),
  product_id uuid,
  description text not null,
  sku_snapshot text,
  product_name_snapshot text,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_of_measure text not null default 'piece',
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(9,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  unit_price_kes numeric(18,4) not null check (unit_price_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  line_total_kes numeric(18,2) not null check (line_total_kes >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,quotation_id,line_number),
  foreign key (business_id,quotation_id) references public.quotations(business_id,id) on delete restrict,
  foreign key (business_id,product_id) references public.products(business_id,id) on delete restrict,
  check (length(trim(description)) > 0),
  check (discount_amount <= quantity * unit_price),
  check (discount_kes <= quantity * unit_price_kes)
);

create index quotation_items_quote_idx on public.quotation_items(business_id,quotation_id,line_number);
create index quotation_items_product_idx on public.quotation_items(business_id,product_id) where product_id is not null;

create table public.quotation_status_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quotation_id uuid not null,
  previous_status text,
  new_status text not null
    check (new_status in ('draft','sent','accepted','rejected','expired','converted','cancelled')),
  changed_by uuid references public.profiles(id) on delete set null,
  change_source text not null default 'staff'
    check (change_source in ('staff','customer','system')),
  reason text,
  changed_at timestamptz not null default now(),
  foreign key (business_id,quotation_id) references public.quotations(business_id,id) on delete restrict
);

create index quotation_status_history_quote_idx on public.quotation_status_history(business_id,quotation_id,changed_at desc);

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  order_number text not null,
  customer_id uuid not null,
  quotation_id uuid,
  job_card_id uuid,
  order_source text not null default 'counter'
    check (order_source in ('counter','garage','online','import','other')),
  status text not null default 'draft'
    check (status in ('draft','confirmed','processing','partially_fulfilled','fulfilled','cancelled')),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  subtotal_amount numeric(18,2) not null default 0 check (subtotal_amount >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  subtotal_kes numeric(18,2) not null default 0 check (subtotal_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  total_kes numeric(18,2) not null default 0 check (total_kes >= 0),
  customer_notes text,
  internal_notes text,
  ordered_at timestamptz not null default now(),
  confirmed_at timestamptz,
  fulfilled_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_orders_number_not_blank check (length(trim(order_number)) > 0),
  constraint sales_orders_discount_limit check (discount_amount <= subtotal_amount),
  constraint sales_orders_discount_kes_limit check (discount_kes <= subtotal_kes),
  unique (business_id,id),
  unique (business_id,order_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id,quotation_id) references public.quotations(business_id,id) on delete restrict,
  foreign key (business_id,job_card_id) references public.job_cards(business_id,id) on delete restrict
);

create index sales_orders_location_status_idx on public.sales_orders(business_id,location_id,status,ordered_at desc);
create index sales_orders_customer_date_idx on public.sales_orders(business_id,customer_id,ordered_at desc);

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  sales_order_id uuid not null,
  line_number integer not null check (line_number > 0),
  item_type text not null default 'part'
    check (item_type in ('part','labour','service','fee','freight','other')),
  product_id uuid,
  description text not null,
  sku_snapshot text,
  product_name_snapshot text,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_of_measure text not null default 'piece',
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(9,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  unit_price_kes numeric(18,4) not null check (unit_price_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  line_total_kes numeric(18,2) not null check (line_total_kes >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,sales_order_id,line_number),
  foreign key (business_id,sales_order_id) references public.sales_orders(business_id,id) on delete restrict,
  foreign key (business_id,product_id) references public.products(business_id,id) on delete restrict,
  check (length(trim(description)) > 0),
  check (discount_amount <= quantity * unit_price),
  check (discount_kes <= quantity * unit_price_kes)
);

create index sales_order_items_order_idx on public.sales_order_items(business_id,sales_order_id,line_number);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  invoice_number text not null,
  customer_id uuid not null,
  sales_order_id uuid,
  quotation_id uuid,
  job_card_id uuid,
  status text not null default 'draft'
    check (status in ('draft','issued','partially_paid','paid','overdue','void')),
  currency_code char(3) not null references public.currencies(code),
  exchange_rate_to_kes numeric(18,8) not null check (exchange_rate_to_kes > 0),
  subtotal_amount numeric(18,2) not null default 0 check (subtotal_amount >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  subtotal_kes numeric(18,2) not null default 0 check (subtotal_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  total_kes numeric(18,2) not null default 0 check (total_kes >= 0),
  amount_paid numeric(18,2) not null default 0 check (amount_paid >= 0),
  amount_paid_kes numeric(18,2) not null default 0 check (amount_paid_kes >= 0),
  due_date date,
  issued_at timestamptz,
  paid_at timestamptz,
  customer_notes text,
  internal_notes text,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoices_number_not_blank check (length(trim(invoice_number)) > 0),
  constraint invoices_discount_limit check (discount_amount <= subtotal_amount),
  constraint invoices_discount_kes_limit check (discount_kes <= subtotal_kes),
  constraint invoices_paid_limit check (amount_paid <= total_amount),
  constraint invoices_paid_kes_limit check (amount_paid_kes <= total_kes),
  unique (business_id,id),
  unique (business_id,invoice_number),
  foreign key (business_id,location_id) references public.locations(business_id,id) on delete restrict,
  foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
  foreign key (business_id,sales_order_id) references public.sales_orders(business_id,id) on delete restrict,
  foreign key (business_id,quotation_id) references public.quotations(business_id,id) on delete restrict,
  foreign key (business_id,job_card_id) references public.job_cards(business_id,id) on delete restrict
);

create index invoices_location_status_idx on public.invoices(business_id,location_id,status,created_at desc);
create index invoices_customer_date_idx on public.invoices(business_id,customer_id,created_at desc);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  invoice_id uuid not null,
  line_number integer not null check (line_number > 0),
  item_type text not null default 'part'
    check (item_type in ('part','labour','service','fee','freight','other')),
  product_id uuid,
  description text not null,
  sku_snapshot text,
  product_name_snapshot text,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_of_measure text not null default 'piece',
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(9,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  unit_price_kes numeric(18,4) not null check (unit_price_kes >= 0),
  discount_kes numeric(18,2) not null default 0 check (discount_kes >= 0),
  tax_kes numeric(18,2) not null default 0 check (tax_kes >= 0),
  line_total_kes numeric(18,2) not null check (line_total_kes >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (business_id,id),
  unique (business_id,invoice_id,line_number),
  foreign key (business_id,invoice_id) references public.invoices(business_id,id) on delete restrict,
  foreign key (business_id,product_id) references public.products(business_id,id) on delete restrict,
  check (length(trim(description)) > 0),
  check (discount_amount <= quantity * unit_price),
  check (discount_kes <= quantity * unit_price_kes)
);

create index invoice_items_invoice_idx on public.invoice_items(business_id,invoice_id,line_number);

-- Status events are append-only audit records; customer-facing rows are scoped to verified profile links.
alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
alter table public.quotation_status_history enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;

create policy "Quotation staff can view quotations"
  on public.quotations for select to authenticated
  using (private.has_business_permission(business_id,'quotations.view',location_id));
create policy "Customers can view their own quotations"
  on public.quotations for select to authenticated
  using (exists (
    select 1 from public.customers c where c.id=quotations.customer_id
      and c.business_id=quotations.business_id and c.profile_id=(select auth.uid())
  ));
create policy "Quotation staff can create quotations"
  on public.quotations for insert to authenticated
  with check (private.has_business_permission(business_id,'quotations.manage',location_id));
create policy "Quotation staff can update draft quotations"
  on public.quotations for update to authenticated
  using (status in ('draft','sent') and private.has_business_permission(business_id,'quotations.manage',location_id))
  with check (private.has_business_permission(business_id,'quotations.manage',location_id));

create policy "Quotation staff can view quotation items"
  on public.quotation_items for select to authenticated
  using (exists (
    select 1 from public.quotations q where q.id=quotation_items.quotation_id
      and q.business_id=quotation_items.business_id
      and private.has_business_permission(q.business_id,'quotations.view',q.location_id)
  ));
create policy "Customers can view their own quotation items"
  on public.quotation_items for select to authenticated
  using (exists (
    select 1 from public.quotations q join public.customers c
      on c.id=q.customer_id and c.business_id=q.business_id
    where q.id=quotation_items.quotation_id and q.business_id=quotation_items.business_id
      and c.profile_id=(select auth.uid())
  ));
create policy "Quotation staff can manage draft quotation items"
  on public.quotation_items for all to authenticated
  using (exists (
    select 1 from public.quotations q where q.id=quotation_items.quotation_id
      and q.business_id=quotation_items.business_id and q.status in ('draft','sent')
      and private.has_business_permission(q.business_id,'quotations.manage',q.location_id)
  ))
  with check (exists (
    select 1 from public.quotations q where q.id=quotation_items.quotation_id
      and q.business_id=quotation_items.business_id and q.status in ('draft','sent')
      and private.has_business_permission(q.business_id,'quotations.manage',q.location_id)
  ));

create policy "Quotation staff can view status history"
  on public.quotation_status_history for select to authenticated
  using (private.has_business_permission(business_id,'quotations.view'));
create policy "Customers can view their own quotation status history"
  on public.quotation_status_history for select to authenticated
  using (exists (
    select 1 from public.quotations q join public.customers c
      on c.id=q.customer_id and c.business_id=q.business_id
    where q.id=quotation_status_history.quotation_id and q.business_id=quotation_status_history.business_id
      and c.profile_id=(select auth.uid())
  ));
create policy "Quotation staff can append status history"
  on public.quotation_status_history for insert to authenticated
  with check (private.has_business_permission(business_id,'quotations.manage'));

create policy "Sales staff can view sales orders"
  on public.sales_orders for select to authenticated
  using (private.has_business_permission(business_id,'sales.view',location_id));
create policy "Customers can view their own sales orders"
  on public.sales_orders for select to authenticated
  using (exists (
    select 1 from public.customers c where c.id=sales_orders.customer_id
      and c.business_id=sales_orders.business_id and c.profile_id=(select auth.uid())
  ));
create policy "Sales staff can create sales orders"
  on public.sales_orders for insert to authenticated
  with check (private.has_business_permission(business_id,'sales.manage',location_id));
create policy "Sales staff can update draft sales orders"
  on public.sales_orders for update to authenticated
  using (status in ('draft','confirmed','processing') and private.has_business_permission(business_id,'sales.manage',location_id))
  with check (private.has_business_permission(business_id,'sales.manage',location_id));

create policy "Sales staff can view sales order items"
  on public.sales_order_items for select to authenticated
  using (exists (
    select 1 from public.sales_orders so where so.id=sales_order_items.sales_order_id
      and so.business_id=sales_order_items.business_id
      and private.has_business_permission(so.business_id,'sales.view',so.location_id)
  ));
create policy "Customers can view their own sales order items"
  on public.sales_order_items for select to authenticated
  using (exists (
    select 1 from public.sales_orders so join public.customers c
      on c.id=so.customer_id and c.business_id=so.business_id
    where so.id=sales_order_items.sales_order_id and so.business_id=sales_order_items.business_id
      and c.profile_id=(select auth.uid())
  ));
create policy "Sales staff can manage sales order items"
  on public.sales_order_items for all to authenticated
  using (exists (
    select 1 from public.sales_orders so where so.id=sales_order_items.sales_order_id
      and so.business_id=sales_order_items.business_id and so.status in ('draft','confirmed','processing')
      and private.has_business_permission(so.business_id,'sales.manage',so.location_id)
  ))
  with check (exists (
    select 1 from public.sales_orders so where so.id=sales_order_items.sales_order_id
      and so.business_id=sales_order_items.business_id and so.status in ('draft','confirmed','processing')
      and private.has_business_permission(so.business_id,'sales.manage',so.location_id)
  ));

create policy "Sales staff can view invoices"
  on public.invoices for select to authenticated
  using (private.has_business_permission(business_id,'sales.view',location_id)
    or private.has_business_permission(business_id,'finance.view',location_id));
create policy "Customers can view their own invoices"
  on public.invoices for select to authenticated
  using (exists (
    select 1 from public.customers c where c.id=invoices.customer_id
      and c.business_id=invoices.business_id and c.profile_id=(select auth.uid())
  ));
create policy "Sales staff can create draft invoices"
  on public.invoices for insert to authenticated
  with check (status='draft' and private.has_business_permission(business_id,'sales.manage',location_id));
create policy "Authorized staff can update draft invoices"
  on public.invoices for update to authenticated
  using (status='draft' and private.has_business_permission(business_id,'sales.manage',location_id))
  with check (private.has_business_permission(business_id,'sales.manage',location_id));

create policy "Sales staff can view invoice items"
  on public.invoice_items for select to authenticated
  using (exists (
    select 1 from public.invoices i where i.id=invoice_items.invoice_id
      and i.business_id=invoice_items.business_id
      and (private.has_business_permission(i.business_id,'sales.view',i.location_id)
        or private.has_business_permission(i.business_id,'finance.view',i.location_id))
  ));
create policy "Customers can view their own invoice items"
  on public.invoice_items for select to authenticated
  using (exists (
    select 1 from public.invoices i join public.customers c
      on c.id=i.customer_id and c.business_id=i.business_id
    where i.id=invoice_items.invoice_id and i.business_id=invoice_items.business_id
      and c.profile_id=(select auth.uid())
  ));
create policy "Sales staff can manage draft invoice items"
  on public.invoice_items for all to authenticated
  using (exists (
    select 1 from public.invoices i where i.id=invoice_items.invoice_id
      and i.business_id=invoice_items.business_id and i.status='draft'
      and private.has_business_permission(i.business_id,'sales.manage',i.location_id)
  ))
  with check (exists (
    select 1 from public.invoices i where i.id=invoice_items.invoice_id
      and i.business_id=invoice_items.business_id and i.status='draft'
      and private.has_business_permission(i.business_id,'sales.manage',i.location_id)
  ));

-- Status history is intentionally insert-only. No browser-side deletion of commercial records.
revoke all on public.quotations, public.quotation_items, public.quotation_status_history,
  public.sales_orders, public.sales_order_items, public.invoices, public.invoice_items
  from anon, authenticated;

grant select, insert, update on public.quotations, public.sales_orders, public.invoices to authenticated;
grant select, insert, update on public.quotation_items, public.sales_order_items, public.invoice_items to authenticated;
grant select, insert on public.quotation_status_history to authenticated;
