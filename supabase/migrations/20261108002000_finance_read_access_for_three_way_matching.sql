-- Allow finance staff to inspect procurement and receipt records needed for supplier invoice matching.
drop policy if exists "Finance staff can view purchase orders" on public.purchase_orders;
create policy "Finance staff can view purchase orders" on public.purchase_orders
 for select to authenticated using(private.has_business_permission(business_id,'finance.manage',location_id));

drop policy if exists "Finance staff can view purchase order items" on public.purchase_order_items;
create policy "Finance staff can view purchase order items" on public.purchase_order_items
 for select to authenticated using(
  private.has_business_permission(business_id,'procurement.manage')
  or exists(select 1 from public.purchase_orders po where po.business_id=purchase_order_items.business_id and po.id=purchase_order_items.purchase_order_id and private.has_business_permission(po.business_id,'finance.manage',po.location_id))
 );

drop policy if exists "Finance staff can view goods receipts" on public.goods_receipts;
create policy "Finance staff can view goods receipts" on public.goods_receipts
 for select to authenticated using(
  private.has_business_permission(business_id,'inventory.view',location_id)
  or private.has_business_permission(business_id,'finance.manage',location_id)
 );

drop policy if exists "Finance staff can view goods receipt items" on public.goods_receipt_items;
create policy "Finance staff can view goods receipt items" on public.goods_receipt_items
 for select to authenticated using(
  private.has_business_permission(business_id,'inventory.view')
  or exists(select 1 from public.goods_receipts gr where gr.business_id=goods_receipt_items.business_id and gr.id=goods_receipt_items.goods_receipt_id and private.has_business_permission(gr.business_id,'finance.manage',gr.location_id))
 );
