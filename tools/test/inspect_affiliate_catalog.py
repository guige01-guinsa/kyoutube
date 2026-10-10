import json
import sys

sys.path.insert(0, '.artifacts')
from security_management import request

query = """
select count(*) total,
 count(*) filter (where program='coupang' and image_url<>'') with_image,
 count(*) filter (where program='coupang' and mobile_allowed) app_allowed,
 count(*) filter (where program='coupang' and published and product_verified
   and mobile_allowed and expires_at>now() and deleted_at is null) visible,
 count(*) filter (where program='coupang' and ingredients is not null
   and cardinality(ingredients)>0) with_ingredients
from public.shopping_affiliate_offers
"""
status, data = request('/database/query', 'POST', {'query': query, 'read_only': True})
reason_query = """
select
 count(*) filter (where program='coupang' and not published) hidden,
 count(*) filter (where program='coupang' and not product_verified) unverified,
 count(*) filter (where program='coupang' and expires_at<=now()) expired,
 count(*) filter (where program='coupang' and deleted_at is not null) deleted,
 count(*) filter (where program='coupang' and cardinality(ingredients)=0) no_alias
from public.shopping_affiliate_offers
"""
reason_status, reasons = request('/database/query', 'POST', {'query': reason_query, 'read_only': True})
print(json.dumps({'status': status, 'rows': data, 'reason_status': reason_status, 'reasons': reasons}, ensure_ascii=False))
