-- Tighten object UPDATE and DELETE paths so an authorized staff member
-- cannot rename an object into an unrelated business record path.

drop policy if exists "Catalogue staff replace product images" on storage.objects;
create policy "Catalogue staff replace product images"
on storage.objects for update to authenticated
using (
  bucket_id='product-images'
  and private.storage_path_uuid(name,2) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
)
with check (
  bucket_id='product-images'
  and private.storage_path_uuid(name,2) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'catalogue.manage',null)
);

drop policy if exists "Customer managers replace customer documents" on storage.objects;
create policy "Customer managers replace customer documents"
on storage.objects for update to authenticated
using (
  bucket_id='customer-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.customers c where c.id=private.storage_path_uuid(name,6) and c.business_id=private.storage_path_uuid(name,2))
)
with check (
  bucket_id='customer-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.customers c where c.id=private.storage_path_uuid(name,6) and c.business_id=private.storage_path_uuid(name,2))
);

drop policy if exists "Customer managers delete customer documents" on storage.objects;
create policy "Customer managers delete customer documents"
on storage.objects for delete to authenticated
using (
  bucket_id='customer-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'customers.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.customers c where c.id=private.storage_path_uuid(name,6) and c.business_id=private.storage_path_uuid(name,2))
);

drop policy if exists "Garage managers replace job attachments" on storage.objects;
create policy "Garage managers replace job attachments"
on storage.objects for update to authenticated
using (
  bucket_id='job-attachments'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.job_cards j where j.id=private.storage_path_uuid(name,6) and j.business_id=private.storage_path_uuid(name,2) and j.location_id=private.storage_path_uuid(name,4))
)
with check (
  bucket_id='job-attachments'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.job_cards j where j.id=private.storage_path_uuid(name,6) and j.business_id=private.storage_path_uuid(name,2) and j.location_id=private.storage_path_uuid(name,4))
);

drop policy if exists "Garage managers delete job attachments" on storage.objects;
create policy "Garage managers delete job attachments"
on storage.objects for delete to authenticated
using (
  bucket_id='job-attachments'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'garage.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.job_cards j where j.id=private.storage_path_uuid(name,6) and j.business_id=private.storage_path_uuid(name,2) and j.location_id=private.storage_path_uuid(name,4))
);

drop policy if exists "Procurement staff replace supplier documents" on storage.objects;
create policy "Procurement staff replace supplier documents"
on storage.objects for update to authenticated
using (
  bucket_id='supplier-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.suppliers s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2))
)
with check (
  bucket_id='supplier-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.suppliers s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2))
);

drop policy if exists "Procurement staff delete supplier documents" on storage.objects;
create policy "Procurement staff delete supplier documents"
on storage.objects for delete to authenticated
using (
  bucket_id='supplier-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.suppliers s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2))
);

drop policy if exists "Procurement staff replace importation documents" on storage.objects;
create policy "Procurement staff replace importation documents"
on storage.objects for update to authenticated
using (
  bucket_id='importation-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.shipments s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2) and s.destination_location_id=private.storage_path_uuid(name,4))
)
with check (
  bucket_id='importation-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.shipments s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2) and s.destination_location_id=private.storage_path_uuid(name,4))
);

drop policy if exists "Procurement staff delete importation documents" on storage.objects;
create policy "Procurement staff delete importation documents"
on storage.objects for delete to authenticated
using (
  bucket_id='importation-documents'
  and private.storage_path_uuid(name,2) is not null
  and private.storage_path_uuid(name,4) is not null
  and private.storage_path_uuid(name,6) is not null
  and private.has_business_permission(private.storage_path_uuid(name,2),'procurement.manage',private.storage_path_uuid(name,4))
  and exists (select 1 from public.shipments s where s.id=private.storage_path_uuid(name,6) and s.business_id=private.storage_path_uuid(name,2) and s.destination_location_id=private.storage_path_uuid(name,4))
);
