import base64
import json
from urllib.request import Request, urlopen

from app.config import get_settings


def send_push(registration_ids: list[str], title: str, body: str) -> bool:
    settings = get_settings()
    if not registration_ids or not settings.jpush_app_key or not settings.jpush_master_secret:
        return False
    auth = base64.b64encode(f'{settings.jpush_app_key}:{settings.jpush_master_secret}'.encode()).decode()
    payload = {'platform': 'all', 'audience': {'registration_id': registration_ids}, 'notification': {'alert': body, 'android': {'alert': body, 'title': title}}}
    request = Request('https://api.jpush.cn/v3/push', data=json.dumps(payload).encode(), headers={'Authorization': f'Basic {auth}', 'Content-Type': 'application/json'}, method='POST')
    try:
        with urlopen(request, timeout=8) as response:
            return 200 <= response.status < 300
    except Exception:
        return False
