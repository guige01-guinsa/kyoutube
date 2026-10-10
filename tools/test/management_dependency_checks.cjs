// Read-only dependency audit in the isolated fixture database. No production connection.
module.exports = async ({q,scalar,ok}) => {
 const fks = await q(`select c.conrelid::regclass::text child,c.confrelid::regclass::text parent,c.confdeltype action
 from pg_constraint c where c.contype='f' and c.confrelid in
 ('public.supplier_purchase_requests'::regclass,'public.chef_sales'::regclass,
 'public.business_records'::regclass,'public.business_stock_items'::regclass)`);
 const personal = fks.filter(x=>x.parent==='supplier_purchase_requests');
 ok(personal.length===2 && personal.every(x=>['supplier_request_events','supplier_buyer_reviews'].includes(x.child)&&x.action==='c'),
 'personal request dependencies are only cascading status history and reviews, not stock');
 ok(!fks.some(x=>x.parent==='chef_sales'),'personal sales have no operational inventory foreign keys');
 const physical = fks.filter(x=>x.parent==='business_records'&&x.child==='business_stock_events');
 ok(physical.length===1&&physical[0].action==='n','shared request deletion retains physical receipts via SET NULL');
 ok(fks.filter(x=>x.parent==='business_records'&&x.child!=='business_stock_events').every(x=>x.action==='c'),
 'other shared request foreign keys are cascading document snapshots/history');
 const items=fks.filter(x=>x.parent==='business_stock_items');
 ok(items.length===3&&items.some(x=>x.child==='business_ingredient_defaults'&&x.action==='a')&&
 items.filter(x=>x.child!=='business_ingredient_defaults').every(x=>x.action==='c'),
 'stock deletion requires detaching recipe defaults and explicitly accounting for reservations and events');
 ok(await scalar(`select count(*)::int from business_stock_events where
 kind in ('receive','return') and delta <> (case when kind='return' then -1 else 1 end)*purchase_quantity*factor`)===0,
 'receipt quantity times conversion factor agrees with physical movement in all fixtures');
 for(const factor of [0.001,1000,0.5,2]) {
  ok(await scalar(`select count(*)::int from business_stock_events where kind in ('receive','return') and
  delta*$1 <> (case when kind='return' then -1 else 1 end)*purchase_quantity*(factor*$1)`,[factor])===0,
  `unit conversion ${factor} preserves receipt/return quantities without changing ordered packs`);
 }
};
