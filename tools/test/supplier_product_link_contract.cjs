// In-memory compatibility test; no connection to a deployed database.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const {PGlite} = require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root = path.resolve(__dirname, '../..');
(async () => {
  const db = new PGlite();
  try {
    await db.waitReady;
    const owner = '11111111-1111-4111-8111-111111111111';
    const listing = '22222222-2222-4222-8222-222222222222';
    const request = '33333333-3333-4333-8333-333333333333';
    await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
      create table auth.users(id uuid primary key);
      insert into auth.users values('${owner}');
      create function auth.uid() returns uuid language sql as $$select '${owner}'::uuid$$;
      create function auth.jwt() returns jsonb language sql as $$select '{"is_anonymous":false}'::jsonb$$;
      grant usage on schema auth to authenticated;
      create table public.profiles(id uuid, role text);
      create table public.kitchen_shopping_items(id uuid, owner_id uuid);`);
    for (const name of ['0052_supplier_purchase_requests.sql', '0053_shopping_supplier_directory.sql', '0060_public_supplier_listings.sql']) {
      await db.exec(fs.readFileSync(path.join(root, 'supabase/migrations', name), 'utf8'));
    }
    await db.query(`insert into public.public_supplier_listings(id,name,website,products,categories,delivery_regions,shipping_note,business_kind,source_urls,checked_on,status)
      values($1,'Test Foods','https://food.example.com','Vegetables',ARRAY['produce'],ARRAY['전국'],'Confirm delivery','store',ARRAY['https://food.example.com'],'2026-09-20','published')`, [listing]);
    await db.exec('set role authenticated');
    const supplier = (await db.query('select public.import_public_supplier_listing($1) s', [listing])).rows[0].s;
    await db.query("update public.shopping_suppliers set memo='private note', is_favorite=true where id=$1", [supplier.id]);
    const again = (await db.query('select public.import_public_supplier_listing($1) s', [listing])).rows[0].s;
    assert.equal(again.id, supplier.id);
    assert.equal(again.memo, 'private note');
    assert.equal(again.is_favorite, true);
    const productUrl = 'https://food.example.com/product?id=123';
    const data = {supplier: {id: supplier.id, name: supplier.name, contact:'', phone:'', products:''},
      buyer:'Kitchen', phone:'', address:'', delivery_date:'', delivery_window:'', notes:'', currency:'KRW',
      lines:[{id:'44444444-4444-4444-8444-444444444444', name:'Carrots', quantity:2,
        unit:'box', spec:'10 kg', price:null, source_ids:[], product_url:productUrl}]};
    const saved = (await db.query('select public.save_supplier_purchase_request($1,0,$2::jsonb) r', [request, JSON.stringify(data)])).rows[0].r;
    assert.equal(saved.data.lines[0].product_url, productUrl);
    assert.equal(saved.data.supplier.memo, undefined);
    const reload = (await db.query('select data from public.supplier_purchase_requests where id=$1', [request])).rows[0];
    assert.equal(reload.data.lines[0].product_url, productUrl);
    assert.equal((await db.query('select count(*)::int n from public.shopping_suppliers')).rows[0].n, 1);
    console.log('PASS: link JSON round-trip, existing import reuse, private notes/favorite preserved (7 assertions); production writes: 0');
  } finally { await db.close(); }
})().catch(e => {console.error(e.message); process.exitCode = 1;});
