-- Garage ya Joe: Storage buckets and access policies.
-- Public product images are intentionally readable by URL.
-- All business documents remain in private buckets and require Storage RLS.
-- Object path conventions:
--   business/{business_uuid}/location/{location_uuid}/customer/{customer_uuid}/...
--   business/{business_uuid}/location/{location_uuid}/job/{job_card_uuid}/...
--   business/{business_uuid}/location/{location_uuid}/supplier/{supplier_uuid}/...
--   business/{business_uuid}/location/{location_uuid}/shipment/{shipment_uuid}/...

create or replace function private.storage_path_uuid(p_name text, p_segment integer)
returns uuid
language sql
immutable
security invoker
set search_path = ''
as $func$
  select case
    when split_part(p_name, '/', p_segment) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_name, '/', p_segment)::uuid
    else null
  end;
$func$;

revoke all on function private.storage_path_uuid(text,integer) from public,anon;
grant execute on function private.storage_path_uuid(text,integer) to authenticated;

-- Product catalogue images are public-read. Upload, replacement and deletion
-- are restricted to staff with catalogue management permission.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values
  ('product-images','product-images',true,10485760,array['image/jpeg','image/png','image/webp','image/avif']),
  ('customer-documents','customer-documents',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp']),
  ('job-attachments','job-attachments',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp','video/mp4']),
  ('supplier-documents','supplier-documents',false,31457280,array['application/pdf','image/jpeg','image/png','image/webp']),
  ('importation-documents','importation-documents',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update
set name=excluded.name,
    public=excluded.public,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

-- Product images: public URLs work without a Storage SELECT policy. This
-- policy permits authenticated catalogue staff to list image objects.
create policy "Product image listing for catalogue staff"
on storage.objects for select to authenticated
using (
  bucket_id='product-images'
  and (
    private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.view',null)
    or private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
  )
);

create policy "Catalogue staff upload product images"
on storage.objects for insert to authenticated
with check (
  bucket_id='product-images'
  and private.storage_path_uuid(name,2) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
);

create policy "Catalogue staff replace product images"
on storage.objects for update to authenticated
using (
  bucket_id='product-images'
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
)
with check (
  bucket_id='product-images'
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
);

create policy "Catalogue staff delete product images"
on storage.objects for delete to authenticated
using (
  bucket_id='product-images'
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
);

-- Customer documents: staff can access according to branch customer permissions;
-- a signed-in customer can read only documents stored under their own customer ID.
create policy "Customer documents read by assigned staff or owner"
on storage.objects for select to authenticated
using (
  bucket_id='customer-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and (
    private.has_business_permission(private.storage_path_uuid(name,2),'customers.view',private.storage_path_uuid(name,4))
    or private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
    or exists (
      select 1 from public.customers c
      where c.id=private.storage_path_uuid(name,6)
        and c.business_id=private.storage_path_uuid(name,2)
        and c.profile_id=(select auth.uid())
    )
  )
);

create policy "Customer managers upload customer documents"
on storage.objects for insert to authenticated
with check (
  bucket_id='customer-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
  and exists (
    select 1 from public.customers c
    where c.id=private.storage_path_uuid(name,6)
      and c.business_id=private.storage_path_uuid(name,2)
  )
);

create policy "Customer managers replace customer documents"
on storage.objects for update to authenticated
using (
  bucket_id='customer-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
)
with check (
  bucket_id='customer-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
);

create policy "Customer managers delete customer documents"
on storage.objects for delete to authenticated
using (
  bucket_id='customer-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
);

-- Job attachments: authorized garage staff can work with files. Customers can
-- read attachments belonging to their own job cards, but cannot alter them.
create policy "Job attachments read by garage staff or job customer"
on storage.objects for select to authenticated
using (
  bucket_id='job-attachments'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and (
    private.has_business_permission(private.storage_path_uuid(name,2),'garage.view',private.storage_path_uuid(name,4))
    or private.has_business_permission(private.storage_path_uuid(name,2),'garage.perform_work',private.storage_path_uuid(name,4))
    or private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
    or exists (
      select 1
      from public.job_cards j
      join public.customers c on c.id=j.customer_id and c.business_id=j.business_id
      where j.id=private.storage_path_uuid(name,6)
        and j.business_id=private.storage_path_uuid(name,2)
        and j.location_id=private.storage_path_uuid(name,4)
        and c.profile_id=(select auth.uid())
    )
  )
);

create policy "Garage staff upload job attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id='job-attachments'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and (
    private.has_business_permission(private.storage_path_uuid(name,2),'garage.perform_work',private.storage_path_uuid(name,4))
    or private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
  )
  and exists (
    select 1 from public.job_cards j
    where j.id=private.storage_path_uuid(name,6)
      and j.business_id=private.storage_path_uuid(name,2)
      and j.location_id=private.storage_path_uuid(name,4)
  )
);

create policy "Garage managers replace job attachments"
on storage.objects for update to authenticated
using (
  bucket_id='job-attachments'
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
)
with check (
  bucket_id='job-attachments'
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
);

create policy "Garage managers delete job attachments"
on storage.objects for delete to authenticated
using (
  bucket_id='job-attachments'
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
);

-- Supplier files are private to procurement staff assigned to the destination
-- branch context recorded in the object path.
create policy "Procurement staff read supplier documents"
on storage.objects for select to authenticated
using (
  bucket_id='supplier-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
);

create policy "Procurement staff upload supplier documents"
on storage.objects for insert to authenticated
with check (
  bucket_id='supplier-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (
    select 1 from public.suppliers s
    where s.id=private.storage_path_uuid(name,6)
      and s.business_id=private.storage_path_uuid(name,2)
  )
);

create policy "Procurement staff replace supplier documents"
on storage.objects for update to authenticated
using (
  bucket_id='supplier-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
)
with check (
  bucket_id='supplier-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
);

create policy "Procurement staff delete supplier documents"
on storage.objects for delete to authenticated
using (
  bucket_id='supplier-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
);

-- Importation files are private to procurement staff at the shipment's
-- destination location. The shipment ID must belong to that business/location.
create policy "Procurement staff read importation documents"
on storage.objects for select to authenticated
using (
  bucket_id='importation-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (
    select 1 from public.shipments s
    where s.id=private.storage_path_uuid(name,6)
      and s.business_id=private.storage_path_uuid(name,2)
      and s.destination_location_id=private.storage_path_uuid(name,4)
  )
);

create policy "Procurement staff upload importation documents"
on storage.objects for insert to authenticated
with check (
  bucket_id='importation-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (
    select 1 from public.shipments s
    where s.id=private.storage_path_uuid(name,6)
      and s.business_id=private.storage_path_uuid(name,2)
      and s.destination_location_id=private.storage_path_uuid(name,4)
  )
);

create policy "Procurement staff replace importation documents"
on storage.objects for update to authenticated
using (
  bucket_id='importation-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
)
with check (
  bucket_id='importation-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
);

create policy "Procurement staff delete importation documents"
on storage.objects for delete to authenticated
using (
  bucket_id='importation-documents'
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
);
