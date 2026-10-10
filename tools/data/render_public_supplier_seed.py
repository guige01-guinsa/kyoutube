"""Validate the reviewed seed and render a bounded, insert-only SQL artifact."""
import argparse
import datetime
import json
import pathlib
import uuid
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATEGORIES = {'produce', 'seafood', 'meat', 'dairy', 'processed', 'pantry'}
NAMESPACE = uuid.UUID('f7b9ca37-af04-4c71-ad72-5ea273b86960')

def url(value):
    u = urlsplit(value)
    assert u.scheme == 'https' and u.hostname and '.' in u.hostname
    assert not u.username and not u.password and u.port in (None, 443)
    assert not any(c.isspace() for c in value) and len(value) <= 2048
    return u.hostname.removeprefix('www.').lower()

def render(published=False):
    rows = json.loads((ROOT / 'tools/data/public_supplier_sources.json').read_text(encoding='utf-8'))
    assert len(rows) == 20
    seen = set()
    for r in rows:
        host = url(r['website'])
        assert host not in seen
        seen.add(host)
        assert 1 <= len(r['name']) <= 120 and 1 <= len(r['products']) <= 500
        assert 1 <= len(r['shipping_note']) <= 700 and len(r['phone']) <= 60
        assert r['categories'] and set(r['categories']) <= CATEGORIES
        assert r['delivery_regions'] == ['전국']
        assert 1 <= len(r['source_urls']) <= 5
        for s in r['source_urls']: url(s)
        checked = datetime.date.fromisoformat(r['checked_on'])
        assert 0 <= (datetime.date.today()-checked).days <= 90
        r['id'] = str(uuid.uuid5(NAMESPACE, host))
        r['status'] = 'published' if published else 'candidate'
    # JSON is data inside a SQL dollar literal, never interpolated as identifiers.
    payload = json.dumps(rows, ensure_ascii=False)
    assert '$supplier_seed$' not in payload
    sql = """-- Reviewed official-source seed. Does not overwrite existing operator edits.
with inserted as (
 insert into public.public_supplier_listings(id,name,website,phone,products,categories,delivery_regions,shipping_note,business_kind,source_urls,checked_on,status)
 select id,name,website,phone,products,categories,delivery_regions,shipping_note,business_kind,source_urls,checked_on,status
 from jsonb_populate_recordset(null::public.public_supplier_listings,$supplier_seed$""" + payload + """$supplier_seed$::jsonb)
 on conflict(website_host) do nothing returning *
) insert into public.public_supplier_audit(listing_id,before_data,after_data)
 select id,null,to_jsonb(inserted) from inserted;
"""
    output = ROOT / '.artifacts/public-supplier-seed.sql'
    output.parent.mkdir(exist_ok=True)
    output.write_text(sql, encoding='utf-8')
    report = ['# 전국 배송 공개 정보 업체 20곳', '',
        '공식 자료 확인: 2026-09-15~16. 아래 전국 배송은 상품·주소·계약 조건에 따른 제한을 포함합니다.',
        '전화가 비어 있는 업체는 확인되지 않은 연락처를 추정하지 않았습니다. 사진·가격·평점은 수집하지 않았습니다.', '',
        '| 업체 | 취급 품목 | 배송 조건 | 공식 확인 자료 |', '|---|---|---|---|']
    for r in rows:
        sources = ' · '.join(f'[자료 {i+1}]({s})' for i,s in enumerate(r['source_urls']))
        report.append(f"| {r['name']} | {r['products']} | {r['shipping_note']} | {sources} |")
    (ROOT / 'docs/public-supplier-seed-review.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
    print(f'Validated {len(rows)} unique businesses; state={rows[0]["status"]}; SQL prepared, no database modified.')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--published',action='store_true')
    render(p.parse_args().published)
