-- Garage ya Joe: garage service workflow foundation.
-- Appointments -> inspection -> job card -> tasks/parts/work logs -> service history.
-- Stock reservation is deliberately handled by the inventory RPC integration in a later step.

create table public.service_appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  customer_id uuid not null,
  vehicle_id uuid not null,
  requested_service text not null,
  customer_concern text,
  preferred_at timestamptz,
  scheduled_at timestamptz,
  status text not null default 'requested'
    check (status in ('requested','confirmed','checked_in','converted','cancelled','no_show')),
  booking_source text not null default 'staff'
    check (booking_source in ('guest','customer','staff')),
  assigned_advisor_id uuid references public.profiles(id) on delete set null,
  internal_notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_appointments_service_not_blank check (length(trim(requested_service)) > 0),
  unique (business_id, id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete restrict,
  foreign key (business_id, vehicle_id)
    references public.vehicles (business_id, id) on delete restrict
);

create index service_appointments_location_schedule_idx
  on public.service_appointments (business_id, location_id, scheduled_at);
create index service_appointments_customer_date_idx
  on public.service_appointments (business_id, customer_id, created_at desc);
create index service_appointments_status_idx
  on public.service_appointments (business_id, status, preferred_at);

create table public.vehicle_inspections (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  vehicle_id uuid not null,
  appointment_id uuid,
  inspected_by uuid references public.profiles(id) on delete set null,
  odometer_km integer check (odometer_km is null or odometer_km >= 0),
  fuel_level_percent smallint check (fuel_level_percent is null or fuel_level_percent between 0 and 100),
  exterior_condition text,
  interior_condition text,
  customer_concerns text,
  findings text,
  recommendations text,
  inspection_data jsonb not null default '{}'::jsonb,
  customer_present boolean not null default false,
  created_at timestamptz not null default now(),
  unique (business_id, id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, vehicle_id)
    references public.vehicles (business_id, id) on delete restrict,
  foreign key (business_id, appointment_id)
    references public.service_appointments (business_id, id) on delete restrict
);

create index vehicle_inspections_vehicle_date_idx
  on public.vehicle_inspections (business_id, vehicle_id, created_at desc);

create table public.job_cards (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_number text not null,
  customer_id uuid not null,
  vehicle_id uuid not null,
  appointment_id uuid,
  inspection_id uuid,
  status text not null default 'draft'
    check (status in ('draft','awaiting_approval','approved','in_progress','quality_check','completed','invoiced','closed','cancelled')),
  customer_complaint text,
  diagnosis_summary text,
  work_summary text,
  internal_notes text,
  opened_at timestamptz not null default now(),
  approved_at timestamptz,
  work_started_at timestamptz,
  completed_at timestamptz,
  closed_at timestamptz,
  odometer_in_km integer check (odometer_in_km is null or odometer_in_km >= 0),
  odometer_out_km integer check (odometer_out_km is null or odometer_out_km >= 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_cards_number_not_blank check (length(trim(job_number)) > 0),
  constraint job_cards_odometer_order_check check (
    odometer_in_km is null or odometer_out_km is null or odometer_out_km >= odometer_in_km
  ),
  unique (business_id, id),
  unique (business_id, job_number),
  unique (business_id, appointment_id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete restrict,
  foreign key (business_id, vehicle_id)
    references public.vehicles (business_id, id) on delete restrict,
  foreign key (business_id, appointment_id)
    references public.service_appointments (business_id, id) on delete restrict,
  foreign key (business_id, inspection_id)
    references public.vehicle_inspections (business_id, id) on delete restrict
);

create index job_cards_location_status_idx
  on public.job_cards (business_id, location_id, status, opened_at desc);
create index job_cards_customer_vehicle_idx
  on public.job_cards (business_id, customer_id, vehicle_id, opened_at desc);

create table public.job_tasks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_card_id uuid not null,
  task_title text not null,
  description text,
  assigned_to uuid references public.profiles(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','in_progress','blocked','completed','cancelled')),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes >= 0),
  actual_minutes integer check (actual_minutes is null or actual_minutes >= 0),
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_tasks_title_not_blank check (length(trim(task_title)) > 0),
  unique (business_id, id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, job_card_id)
    references public.job_cards (business_id, id) on delete restrict
);

create index job_tasks_assignee_status_idx
  on public.job_tasks (assigned_to, status, created_at desc);
create index job_tasks_job_idx
  on public.job_tasks (business_id, job_card_id);

create table public.job_parts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_card_id uuid not null,
  product_id uuid not null,
  requested_quantity numeric(18,3) not null check (requested_quantity > 0),
  fulfillment_status text not null default 'requested'
    check (fulfillment_status in ('requested','sourcing','available','fulfilled','cancelled')),
  requested_by uuid references public.profiles(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, job_card_id)
    references public.job_cards (business_id, id) on delete restrict,
  foreign key (business_id, product_id)
    references public.products (business_id, id) on delete restrict
);

create index job_parts_job_idx on public.job_parts (business_id, job_card_id);
create index job_parts_product_status_idx on public.job_parts (business_id, product_id, fulfillment_status);

create table public.job_work_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  job_card_id uuid not null,
  job_task_id uuid,
  staff_id uuid not null references public.profiles(id) on delete restrict,
  work_description text not null,
  minutes_spent integer check (minutes_spent is null or minutes_spent >= 0),
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint job_work_logs_description_not_blank check (length(trim(work_description)) > 0),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, job_card_id)
    references public.job_cards (business_id, id) on delete restrict,
  foreign key (business_id, job_task_id)
    references public.job_tasks (business_id, id) on delete restrict
);

create index job_work_logs_job_date_idx
  on public.job_work_logs (business_id, job_card_id, logged_at desc);
create index job_work_logs_staff_date_idx
  on public.job_work_logs (staff_id, logged_at desc);

create table public.service_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  location_id uuid not null,
  customer_id uuid not null,
  vehicle_id uuid not null,
  job_card_id uuid not null,
  service_date date not null default current_date,
  odometer_km integer check (odometer_km is null or odometer_km >= 0),
  customer_summary text not null,
  next_service_due_date date,
  next_service_due_odometer_km integer check (next_service_due_odometer_km is null or next_service_due_odometer_km >= 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, id),
  unique (business_id, job_card_id),
  foreign key (business_id, location_id)
    references public.locations (business_id, id) on delete restrict,
  foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete restrict,
  foreign key (business_id, vehicle_id)
    references public.vehicles (business_id, id) on delete restrict,
  foreign key (business_id, job_card_id)
    references public.job_cards (business_id, id) on delete restrict
);

create index service_history_vehicle_date_idx
  on public.service_history (business_id, vehicle_id, service_date desc);
create index service_history_customer_date_idx
  on public.service_history (business_id, customer_id, service_date desc);

-- All garage workflow tables are protected by RLS.
alter table public.service_appointments enable row level security;
alter table public.vehicle_inspections enable row level security;
alter table public.job_cards enable row level security;
alter table public.job_tasks enable row level security;
alter table public.job_parts enable row level security;
alter table public.job_work_logs enable row level security;
alter table public.service_history enable row level security;

-- Appointment visibility: scoped garage staff, or the customer linked to the record.
create policy "Garage staff can view appointments"
  on public.service_appointments for select to authenticated
  using (private.has_business_permission(business_id, 'garage.view', location_id));

create policy "Customers can view their own appointments"
  on public.service_appointments for select to authenticated
  using (exists (
    select 1 from public.customers c
    where c.id = service_appointments.customer_id
      and c.business_id = service_appointments.business_id
      and c.profile_id = (select auth.uid())
  ));

create policy "Customers can request their own appointments"
  on public.service_appointments for insert to authenticated
  with check (
    booking_source = 'customer'
    and status = 'requested'
    and exists (
      select 1 from public.customers c
      where c.id = service_appointments.customer_id
        and c.business_id = service_appointments.business_id
        and c.profile_id = (select auth.uid())
    )
    and exists (
      select 1 from public.locations l
      where l.id = service_appointments.location_id
        and l.business_id = service_appointments.business_id
        and l.is_active = true
    )
  );

create policy "Garage staff can manage appointments"
  on public.service_appointments for all to authenticated
  using (private.has_business_permission(business_id, 'garage.manage', location_id))
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));

-- Inspection records are staff-only and append-only.
create policy "Garage staff can view inspections"
  on public.vehicle_inspections for select to authenticated
  using (private.has_business_permission(business_id, 'garage.view', location_id));
create policy "Garage staff can create inspections"
  on public.vehicle_inspections for insert to authenticated
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));

-- Job cards: managers/advisors and mechanics assigned to a task can view.
create policy "Garage staff can view job cards"
  on public.job_cards for select to authenticated
  using (
    private.has_business_permission(business_id, 'garage.view', location_id)
    or exists (
      select 1 from public.job_tasks jt
      where jt.business_id = job_cards.business_id
        and jt.job_card_id = job_cards.id
        and jt.assigned_to = (select auth.uid())
    )
  );
create policy "Garage staff can create job cards"
  on public.job_cards for insert to authenticated
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));
create policy "Garage staff can update job cards"
  on public.job_cards for update to authenticated
  using (private.has_business_permission(business_id, 'garage.manage', location_id))
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));

-- Tasks: authorized managers allocate work; assigned mechanics can update their own tasks.
create policy "Staff can view job tasks"
  on public.job_tasks for select to authenticated
  using (
    private.has_business_permission(business_id, 'garage.view', location_id)
    or assigned_to = (select auth.uid())
  );
create policy "Garage managers can create job tasks"
  on public.job_tasks for insert to authenticated
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));
create policy "Managers or assigned mechanics can update tasks"
  on public.job_tasks for update to authenticated
  using (
    private.has_business_permission(business_id, 'garage.manage', location_id)
    or (
      assigned_to = (select auth.uid())
      and private.has_business_permission(business_id, 'garage.perform_work', location_id)
    )
  )
  with check (
    private.has_business_permission(business_id, 'garage.manage', location_id)
    or (
      assigned_to = (select auth.uid())
      and private.has_business_permission(business_id, 'garage.perform_work', location_id)
    )
  );

-- Parts requirements are requests against the shared catalogue. Stock reservation is separate.
create policy "Garage or inventory staff can view job parts"
  on public.job_parts for select to authenticated
  using (
    private.has_business_permission(business_id, 'garage.view', location_id)
    or private.has_business_permission(business_id, 'inventory.view', location_id)
  );
create policy "Garage staff can request job parts"
  on public.job_parts for insert to authenticated
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));
create policy "Garage or inventory staff can update job part requests"
  on public.job_parts for update to authenticated
  using (
    private.has_business_permission(business_id, 'garage.manage', location_id)
    or private.has_business_permission(business_id, 'inventory.manage', location_id)
  )
  with check (
    private.has_business_permission(business_id, 'garage.manage', location_id)
    or private.has_business_permission(business_id, 'inventory.manage', location_id)
  );

-- Work logs are immutable. Mechanics may log against tasks assigned to them.
create policy "Staff can view job work logs"
  on public.job_work_logs for select to authenticated
  using (
    private.has_business_permission(business_id, 'garage.view', location_id)
    or staff_id = (select auth.uid())
  );
create policy "Assigned mechanics or garage managers can log work"
  on public.job_work_logs for insert to authenticated
  with check (
    staff_id = (select auth.uid())
    and (
      private.has_business_permission(business_id, 'garage.manage', location_id)
      or exists (
        select 1 from public.job_tasks jt
        where jt.business_id = job_work_logs.business_id
          and jt.job_card_id = job_work_logs.job_card_id
          and jt.id = job_work_logs.job_task_id
          and jt.assigned_to = (select auth.uid())
          and private.has_business_permission(business_id, 'garage.perform_work', location_id)
      )
    )
  );

-- Customer service history contains only customer-facing summaries.
create policy "Staff can view service history"
  on public.service_history for select to authenticated
  using (private.has_business_permission(business_id, 'garage.view', location_id));
create policy "Customers can view their own service history"
  on public.service_history for select to authenticated
  using (exists (
    select 1 from public.customers c
    where c.id = service_history.customer_id
      and c.business_id = service_history.business_id
      and c.profile_id = (select auth.uid())
  ));
create policy "Garage staff can create service history"
  on public.service_history for insert to authenticated
  with check (private.has_business_permission(business_id, 'garage.manage', location_id));

-- No client-side deletes or rewriting immutable inspection/work/service history records.
revoke all on public.service_appointments, public.vehicle_inspections, public.job_cards,
  public.job_tasks, public.job_parts, public.job_work_logs, public.service_history
  from anon, authenticated;

grant select, insert, update on public.service_appointments to authenticated;
grant select, insert on public.vehicle_inspections to authenticated;
grant select, insert, update on public.job_cards to authenticated;
grant select, insert, update on public.job_tasks to authenticated;
grant select, insert, update on public.job_parts to authenticated;
grant select, insert on public.job_work_logs to authenticated;
grant select, insert on public.service_history to authenticated;
