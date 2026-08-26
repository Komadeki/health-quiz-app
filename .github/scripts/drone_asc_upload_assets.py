import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

KEY_ID = os.environ['APP_STORE_CONNECT_API_KEY_ID']
ISSUER_ID = os.environ['APP_STORE_CONNECT_API_ISSUER_ID']
BUNDLE_ID = os.environ['APP_BUNDLE_ID']
APP_VERSION = os.environ['APP_VERSION']
IAP_PRODUCT_ID = os.environ['IAP_PRODUCT_ID']
ASSET_DIR = Path(os.environ['DRONE_CAPTURE_DIR'])
with open(os.environ['ASC_KEY_PATH'], encoding='utf-8') as fh:
    PRIVATE_KEY = fh.read()


def token():
    now = int(time.time())
    return jwt.encode(
        {'iss': ISSUER_ID, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
        PRIVATE_KEY,
        algorithm='ES256',
        headers={'kid': KEY_ID, 'typ': 'JWT'},
    )


def req(method, path, params=None, body=None, optional=False):
    url = 'https://api.appstoreconnect.apple.com' + path
    if params:
        url += '?' + urllib.parse.urlencode(params, doseq=True)
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode('utf-8')
    headers = {'Authorization': 'Bearer ' + token()}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            return None if not raw else json.loads(raw)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode('utf-8', errors='replace')
        if optional:
            print(f'OPTIONAL_API_UNAVAILABLE={method} {path} HTTP {exc.code}: {raw[:500]}')
            return None
        print(f'HTTP {exc.code} {method} {path}: {raw}', file=sys.stderr)
        raise


def upload_operation(operation, payload):
    offset = int(operation['offset'])
    length = int(operation['length'])
    part = payload[offset:offset + length]
    headers = {
        item['name']: item['value']
        for item in operation.get('requestHeaders', [])
    }
    request = urllib.request.Request(
        operation['url'],
        data=part,
        headers=headers,
        method=operation.get('method', 'PUT'),
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        response.read()


def reserve_and_upload(*, create_path, resource_type, relationship_name,
                       relationship_type, relationship_id, file_path,
                       update_path_prefix):
    payload = file_path.read_bytes()
    md5 = hashlib.md5(payload).hexdigest()
    body = {
        'data': {
            'type': resource_type,
            'attributes': {
                'fileName': file_path.name,
                'fileSize': len(payload),
            },
            'relationships': {
                relationship_name: {
                    'data': {
                        'type': relationship_type,
                        'id': relationship_id,
                    }
                }
            },
        }
    }
    reserved = req('POST', create_path, body=body)
    resource = reserved['data']
    resource_id = resource['id']
    attrs = resource.get('attributes', {})
    operations = attrs.get('uploadOperations') or []
    if not operations:
        raise RuntimeError(f'No upload operations for {resource_type} {resource_id}')
    for operation in operations:
        upload_operation(operation, payload)
    req(
        'PATCH',
        f'{update_path_prefix}/{resource_id}',
        body={
            'data': {
                'type': resource_type,
                'id': resource_id,
                'attributes': {
                    'uploaded': True,
                    'sourceFileChecksum': md5,
                },
            }
        },
    )
    state = None
    for _ in range(36):
        current = req('GET', f'{update_path_prefix}/{resource_id}')
        state = current['data'].get('attributes', {}).get('assetDeliveryState', {}).get('state')
        print(f'ASSET_STATE={resource_type}:{resource_id}:{state}')
        if state == 'COMPLETE':
            return resource_id
        if state == 'FAILED':
            errors = current['data'].get('attributes', {}).get('assetDeliveryState', {}).get('errors')
            raise RuntimeError(f'Asset processing failed: {errors}')
        time.sleep(5)
    raise RuntimeError(f'Asset did not reach COMPLETE, last state={state}')


def ensure_screenshot_set(localization_id, display_type):
    sets = req(
        'GET',
        f'/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets',
        {'limit': 200},
    )
    for item in sets.get('data', []):
        if item.get('attributes', {}).get('screenshotDisplayType') == display_type:
            return item['id']
    created = req(
        'POST',
        '/v1/appScreenshotSets',
        body={
            'data': {
                'type': 'appScreenshotSets',
                'attributes': {'screenshotDisplayType': display_type},
                'relationships': {
                    'appStoreVersionLocalization': {
                        'data': {
                            'type': 'appStoreVersionLocalizations',
                            'id': localization_id,
                        }
                    }
                },
            }
        },
    )
    return created['data']['id']


def ensure_app_screenshot(localization_id, display_type, file_path):
    set_id = ensure_screenshot_set(localization_id, display_type)
    existing = req('GET', f'/v1/appScreenshotSets/{set_id}/appScreenshots', {'limit': 200})
    complete = []
    stale = []
    for item in existing.get('data', []):
        state = item.get('attributes', {}).get('assetDeliveryState', {}).get('state')
        if state == 'COMPLETE':
            complete.append(item['id'])
        else:
            stale.append(item['id'])
    if complete:
        print(f'APP_SCREENSHOT_ALREADY_COMPLETE={display_type}:{len(complete)}')
        return complete[0]
    for screenshot_id in stale:
        req('DELETE', f'/v1/appScreenshots/{screenshot_id}', optional=True)
    screenshot_id = reserve_and_upload(
        create_path='/v1/appScreenshots',
        resource_type='appScreenshots',
        relationship_name='appScreenshotSet',
        relationship_type='appScreenshotSets',
        relationship_id=set_id,
        file_path=file_path,
        update_path_prefix='/v1/appScreenshots',
    )
    print(f'APP_SCREENSHOT_UPLOADED={display_type}:{screenshot_id}')
    return screenshot_id


def find_complete_review_contact(exclude_app_id):
    apps = req('GET', '/v1/apps', {'limit': 200}, optional=True)
    if not apps:
        return None
    for app in apps.get('data', []):
        app_id = app['id']
        if app_id == exclude_app_id:
            continue
        versions = req('GET', f'/v1/apps/{app_id}/appStoreVersions', {'limit': 50}, optional=True)
        if not versions:
            continue
        for version in versions.get('data', []):
            detail = req(
                'GET',
                f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail",
                optional=True,
            )
            data = (detail or {}).get('data')
            if not data:
                continue
            attrs = data.get('attributes', {})
            contact = {
                key: attrs.get(key)
                for key in (
                    'contactFirstName',
                    'contactLastName',
                    'contactPhone',
                    'contactEmail',
                )
            }
            if all((value or '').strip() for value in contact.values()):
                print('REVIEW_CONTACT_REUSED_FROM_EXISTING_APP=true')
                return contact
    print('REVIEW_CONTACT_REUSED_FROM_EXISTING_APP=false')
    return None


for required in ('iphone_69_home.png', 'ipad_13_home.png', 'iap_review.png'):
    path = ASSET_DIR / required
    if not path.exists() or path.stat().st_size <= 0:
        raise SystemExit(f'Missing generated asset: {path}')
    print(f'GENERATED_ASSET={required}:{path.stat().st_size}')

apps = req('GET', '/v1/apps', {'filter[bundleId]': BUNDLE_ID, 'limit': 1})
if not apps.get('data'):
    raise SystemExit('App not found')
app = apps['data'][0]
app_id = app['id']

versions = req('GET', f'/v1/apps/{app_id}/appStoreVersions', {'limit': 200})
version = next(
    (item for item in versions.get('data', [])
     if item.get('attributes', {}).get('versionString') == APP_VERSION),
    None,
)
if version is None:
    raise SystemExit('Target App Store version not found')
version_id = version['id']
locs = req(
    'GET',
    f'/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations',
    {'limit': 200},
)
ja = next(
    (item for item in locs.get('data', [])
     if item.get('attributes', {}).get('locale') == 'ja'),
    None,
)
if ja is None:
    raise SystemExit('Japanese localization not found')
localization_id = ja['id']

ensure_app_screenshot(
    localization_id,
    'APP_IPHONE_67',
    ASSET_DIR / 'iphone_69_home.png',
)
ensure_app_screenshot(
    localization_id,
    'APP_IPAD_PRO_3GEN_129',
    ASSET_DIR / 'ipad_13_home.png',
)

# Add reviewer contact from another existing app if Drone lacks it.
review = req('GET', f'/v1/appStoreVersions/{version_id}/appStoreReviewDetail', optional=True)
review_data = (review or {}).get('data')
contact_complete = False
if review_data:
    attrs = review_data.get('attributes', {})
    contact_complete = all(
        (attrs.get(key) or '').strip()
        for key in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail')
    )
if not contact_complete:
    contact = find_complete_review_contact(app_id)
    if contact:
        notes = (
            '二等無人航空機の学科試験対策アプリです。アカウント登録はありません。\n'
            '無料状態では30問を利用できます。非消費型IAP「全386問を解放」で全386問と模擬試験を利用できます。\n'
            '購入画面はホーム下部の「全問解放」、または「模擬試験」をタップして確認できます。'
        )
        if review_data:
            req(
                'PATCH',
                f"/v1/appStoreReviewDetails/{review_data['id']}",
                body={
                    'data': {
                        'type': 'appStoreReviewDetails',
                        'id': review_data['id'],
                        'attributes': {**contact, 'demoAccountRequired': False, 'notes': notes},
                    }
                },
            )
        else:
            created = req(
                'POST',
                '/v1/appStoreReviewDetails',
                body={
                    'data': {
                        'type': 'appStoreReviewDetails',
                        'attributes': {**contact, 'demoAccountRequired': False, 'notes': notes},
                        'relationships': {
                            'appStoreVersion': {
                                'data': {'type': 'appStoreVersions', 'id': version_id}
                            }
                        },
                    }
                },
            )
            review_data = created['data']
        contact_complete = True
        print('APP_REVIEW_CONTACT_FILLED=true')
else:
    print('APP_REVIEW_CONTACT_ALREADY_COMPLETE=true')

# IAP review screenshot.
iaps = req(
    'GET',
    f'/v1/apps/{app_id}/inAppPurchasesV2',
    {'filter[productId]': IAP_PRODUCT_ID, 'limit': 10},
)
if not iaps.get('data'):
    raise SystemExit('IAP not found')
iap = iaps['data'][0]
iap_id = iap['id']
existing_iap_shot = req(
    'GET',
    f'/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot',
    optional=True,
)
iap_shot_data = (existing_iap_shot or {}).get('data')
if iap_shot_data:
    state = iap_shot_data.get('attributes', {}).get('assetDeliveryState', {}).get('state')
    if state == 'COMPLETE':
        print('IAP_REVIEW_SCREENSHOT_ALREADY_COMPLETE=true')
    else:
        req('DELETE', f"/v1/inAppPurchaseAppStoreReviewScreenshots/{iap_shot_data['id']}", optional=True)
        iap_shot_data = None
if not iap_shot_data:
    shot_id = reserve_and_upload(
        create_path='/v1/inAppPurchaseAppStoreReviewScreenshots',
        resource_type='inAppPurchaseAppStoreReviewScreenshots',
        relationship_name='inAppPurchaseV2',
        relationship_type='inAppPurchases',
        relationship_id=iap_id,
        file_path=ASSET_DIR / 'iap_review.png',
        update_path_prefix='/v1/inAppPurchaseAppStoreReviewScreenshots',
    )
    print('IAP_REVIEW_SCREENSHOT_UPLOADED=' + shot_id)

# Final release readiness evidence.
sets = req(
    'GET',
    f'/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets',
    {'limit': 200},
)
for item in sets.get('data', []):
    display = item.get('attributes', {}).get('screenshotDisplayType')
    shots = req('GET', f"/v1/appScreenshotSets/{item['id']}/appScreenshots", {'limit': 200})
    complete_count = sum(
        1 for shot in shots.get('data', [])
        if shot.get('attributes', {}).get('assetDeliveryState', {}).get('state') == 'COMPLETE'
    )
    print(f'FINAL_SCREENSHOT_SET={display}:COMPLETE={complete_count}')

review = req('GET', f'/v1/appStoreVersions/{version_id}/appStoreReviewDetail', optional=True)
review_data = (review or {}).get('data')
if review_data:
    attrs = review_data.get('attributes', {})
    contact_complete = all(
        (attrs.get(key) or '').strip()
        for key in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail')
    )
print('FINAL_REVIEW_CONTACT_COMPLETE=' + str(contact_complete).lower())

iaps_after = req(
    'GET',
    f'/v1/apps/{app_id}/inAppPurchasesV2',
    {'filter[productId]': IAP_PRODUCT_ID, 'limit': 10},
)
print('FINAL_IAP_STATE=' + str(iaps_after['data'][0].get('attributes', {}).get('state')))
print('ASSET_PREPARATION_COMPLETE=true')
