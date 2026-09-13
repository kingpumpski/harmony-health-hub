DELETE FROM public.invoice_items ii
WHERE ii.source_type IN ('lab_order','prescription')
  AND COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0)=0
  AND EXISTS (SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=ii.source_id AND so.status<>'cancelled' AND COALESCE(so.amount,0)>0);
UPDATE public.invoices i SET total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),updated_at=now();
