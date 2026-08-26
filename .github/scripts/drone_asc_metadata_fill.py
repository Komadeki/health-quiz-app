import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

DESCRIPTION = """二等無人航空機の学科試験対策を、教則第5版に基づく全386問で繰り返し学習できるアプリです。

【主な機能】
・30問を無料で体験。全問解放後は全386問を利用可能
・単元別学習
・ランダム演習（20問）
・未回答／直近で間違えた問題を、残数に応じた問題数を選んで演習
・50問・30分の模擬試験
・模擬試験は提出前に前の問題へ戻って回答変更可能
・学習進捗、正答率、要復習、苦手単元を可視化
・買い切りで全386問と模擬試験を解放
・購入復元対応

問題・進捗は端末内で管理し、アカウント登録は不要です。

本アプリはKOMADEKIが提供する民間の学習支援アプリであり、国土交通省その他の公的機関が提供・公認・監修する公式アプリではありません。"""
KEYWORDS = "ドローン,無人航空機,二等,操縦士,学科試験,資格,模擬試験,教則,試験対策"
SUPPORT_URL = "https://komadeki.com/drone-second-class/support/"
PRIVACY_URL = "https://komadeki.com/drone-second-class/privacy/"
SUBTITLE = "二等学科を386問で反復学習"
IAP_NAME = "全386問を解放"
IAP_DESCRIPTION = "全386問と50問・30分の模擬試験を利用できます。"
REVIEW_NOTES = """二等無人航空機の学科試験対策アプリです。アカウント登録はありません。
無料状態では30問を利用できます。非消費型IAP「全386問を解放」で全386問と模擬試験を利用できます。
購入画面はホーム下部の「全問解放」、または「模擬試験」をタップして確認できます。
模擬試験は50問・30分で、提出前は前の問題へ戻り回答変更できます。"""

KEY_ID = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
ISSUER_ID = os.environ["APP_STORE_CONNECT_API_ISSUER_ID"]
BUNDLE_ID = os.environ["APP_BUNDLE_ID"]
APP_VERSION = os.environ["APP_VERSION"]
IAP_PRODUCT_ID = os.environ["IAP_PRODUCT_ID"]
with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as fh:
    PRIVATE_KEY = fh.read()


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def req(method, path, params=None, body=None, optional=False):
    url = "https://api.appstoreconnect.apple.com" + path
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {"Authorization": "Bearer " + token()}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return None if not raw else json.loads(raw)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        if optional:
            print(f"OPTIONAL_API_UNAVAILABLE={method} {path} HTTP {exc.code}: {raw[:500]}")
            return None
        print(f"HTTP {exc.code} {method} {path}: {raw}", file=sys.stderr)
        raise


def first_data(response):
    return (response or {}).get("data")


apps = req("GET", "/v1/apps", {"filter[bundleId]": BUNDLE_ID, "limit": 1})
if not apps.get("data"):
    raise SystemExit("App not found")
app = apps["data"][0]
app_id = app["id"]
print("APP_ID=" + app_id)

versions = req("GET", f"/v1/apps/{app_id}/appStoreVersions", {"limit": 200})
version = next(
    (item for item in versions.get("data", []) if item.get("attributes", {}).get("versionString") == APP_VERSION),
    None,
)
if version is None:
    raise SystemExit("Target version missing")
version_id = version["id"]
print("VERSION_ID=" + version_id)

# Version-level text and release settings.
req(
    "PATCH",
    f"/v1/appStoreVersions/{version_id}",
    body={
        "data": {
            "type": "appStoreVersions",
            "id": version_id,
            "attributes": {"copyright": "2026 KOMADEKI", "releaseType": "AFTER_APPROVAL"},
        }
    },
)
print("VERSION_CORE_METADATA_UPDATED=true")

locs = req("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", {"limit": 200})
ja = next((x for x in locs.get("data", []) if x.get("attributes", {}).get("locale") == "ja"), None)
attrs = {"description": DESCRIPTION, "keywords": KEYWORDS, "supportUrl": SUPPORT_URL}
if ja:
    req(
        "PATCH",
        f"/v1/appStoreVersionLocalizations/{ja['id']}",
        body={"data": {"type": "appStoreVersionLocalizations", "id": ja["id"], "attributes": attrs}},
    )
    print("VERSION_LOCALIZATION_UPDATED=true")
else:
    created = req(
        "POST",
        "/v1/appStoreVersionLocalizations",
        body={
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": "ja", **attrs},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
            }
        },
    )
    ja = created["data"]
    print("VERSION_LOCALIZATION_CREATED=true")

infos = req("GET", f"/v1/apps/{app_id}/appInfos", {"limit": 50})
editable = next(
    (x for x in infos.get("data", []) if (x.get("attributes", {}).get("state") or x.get("attributes", {}).get("appStoreState")) == "PREPARE_FOR_SUBMISSION"),
    (infos.get("data") or [None])[0],
)
if editable:
    ilocs = req("GET", f"/v1/appInfos/{editable['id']}/appInfoLocalizations", {"limit": 200})
    ja_info = next((x for x in ilocs.get("data", []) if x.get("attributes", {}).get("locale") == "ja"), None)
    if ja_info:
        req(
            "PATCH",
            f"/v1/appInfoLocalizations/{ja_info['id']}",
            body={
                "data": {
                    "type": "appInfoLocalizations",
                    "id": ja_info["id"],
                    "attributes": {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL},
                }
            },
        )
        print("APP_INFO_LOCALIZATION_UPDATED=true")

# Use contact details already stored with Apple for TestFlight if present.
beta = req("GET", f"/v1/apps/{app_id}/betaAppReviewDetail", optional=True)
beta_data = first_data(beta)
beta_attrs = beta_data.get("attributes", {}) if beta_data else {}
contact = {key: beta_attrs.get(key) for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")}
contact_complete = all((value or "").strip() for value in contact.values())
print("BETA_REVIEW_CONTACT_COMPLETE=" + str(contact_complete).lower())
review = req("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail", optional=True)
review_data = first_data(review)
if review_data:
    review_attrs = {"demoAccountRequired": False, "notes": REVIEW_NOTES}
    if contact_complete:
        review_attrs.update(contact)
    req(
        "PATCH",
        f"/v1/appStoreReviewDetails/{review_data['id']}",
        body={"data": {"type": "appStoreReviewDetails", "id": review_data["id"], "attributes": review_attrs}},
    )
    print("APP_REVIEW_DETAIL_UPDATED=true")
elif contact_complete:
    req(
        "POST",
        "/v1/appStoreReviewDetails",
        body={
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": {**contact, "demoAccountRequired": False, "notes": REVIEW_NOTES},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
            }
        },
    )
    print("APP_REVIEW_DETAIL_CREATED=true")
else:
    print("APP_REVIEW_DETAIL_BLOCKED_BY_CONTACT=true")

# IAP state and safe metadata completion.
iaps = req("GET", f"/v1/apps/{app_id}/inAppPurchasesV2", {"filter[productId]": IAP_PRODUCT_ID, "limit": 10})
if not iaps.get("data"):
    raise SystemExit("IAP missing")
iap = iaps["data"][0]
iap_id = iap["id"]
print("IAP_ID=" + iap_id)
print("IAP_STATE_BEFORE=" + str(iap.get("attributes", {}).get("state")))

detail = req(
    "GET",
    f"/v2/inAppPurchases/{iap_id}",
    {
        "include": "inAppPurchaseLocalizations,iapPriceSchedule,appStoreReviewScreenshot,inAppPurchaseAvailability,versions",
        "limit[inAppPurchaseLocalizations]": 50,
        "limit[versions]": 50,
    },
    optional=True,
)
included = (detail or {}).get("included", [])
old_locs = [x for x in included if x.get("type") == "inAppPurchaseLocalizations"]
iap_versions = [x for x in included if x.get("type") == "inAppPurchaseVersions"]
print("IAP_OLD_LOCALIZATION_COUNT=" + str(len(old_locs)))
print("IAP_VERSION_COUNT=" + str(len(iap_versions)))

localized = False
ja_old = next((x for x in old_locs if x.get("attributes", {}).get("locale") == "ja"), None)
if ja_old:
    result = req(
        "PATCH",
        f"/v1/inAppPurchaseLocalizations/{ja_old['id']}",
        body={
            "data": {
                "type": "inAppPurchaseLocalizations",
                "id": ja_old["id"],
                "attributes": {"name": IAP_NAME, "description": IAP_DESCRIPTION},
            }
        },
        optional=True,
    )
    localized = result is not None
    if localized:
        print("IAP_LOCALIZATION_UPDATED_V1=true")

if not localized and not old_locs and not iap_versions:
    result = req(
        "POST",
        "/v1/inAppPurchaseLocalizations",
        body={
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": "ja", "name": IAP_NAME, "description": IAP_DESCRIPTION},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
            }
        },
        optional=True,
    )
    localized = result is not None
    if localized:
        print("IAP_LOCALIZATION_CREATED_V1=true")

if not localized:
    draft = next((x for x in iap_versions if x.get("attributes", {}).get("state") == "PREPARE_FOR_SUBMISSION"), None)
    if not draft:
        created = req(
            "POST",
            "/v1/inAppPurchaseVersions",
            body={
                "data": {
                    "type": "inAppPurchaseVersions",
                    "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}}},
                }
            },
            optional=True,
        )
        draft = first_data(created)
        if draft:
            print("IAP_VERSION_CREATED=true")
    if draft:
        version_locs = req("GET", f"/v1/inAppPurchaseVersions/{draft['id']}/localizations", {"limit": 50}, optional=True)
        ja_v2 = next((x for x in (version_locs or {}).get("data", []) if x.get("attributes", {}).get("locale") == "ja"), None)
        if ja_v2:
            result = req(
                "PATCH",
                f"/v2/inAppPurchaseLocalizations/{ja_v2['id']}",
                body={
                    "data": {
                        "type": "inAppPurchaseLocalizations",
                        "id": ja_v2["id"],
                        "attributes": {"name": IAP_NAME, "description": IAP_DESCRIPTION},
                    }
                },
                optional=True,
            )
            localized = result is not None
            if localized:
                print("IAP_LOCALIZATION_UPDATED_V2=true")
        else:
            result = req(
                "POST",
                "/v2/inAppPurchaseLocalizations",
                body={
                    "data": {
                        "type": "inAppPurchaseLocalizations",
                        "attributes": {"locale": "ja", "name": IAP_NAME, "description": IAP_DESCRIPTION},
                        "relationships": {"version": {"data": {"type": "inAppPurchaseVersions", "id": draft["id"]}}},
                    }
                },
                optional=True,
            )
            localized = result is not None
            if localized:
                print("IAP_LOCALIZATION_CREATED_V2=true")

price = req("GET", f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule", {"include": "baseTerritory,manualPrices,automaticPrices"}, optional=True)
price_data = first_data(price)
print("IAP_PRICE_SCHEDULE_PRESENT=" + str(price_data is not None).lower())
if price:
    included_price = price.get("included", [])
    manual_prices = [x for x in included_price if x.get("type") == "inAppPurchasePrices" and x.get("attributes", {}).get("manual")]
    print("IAP_MANUAL_PRICE_COUNT=" + str(len(manual_prices)))

shot = req("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot", optional=True)
shot_data = first_data(shot)
shot_state = shot_data.get("attributes", {}).get("assetDeliveryState", {}) if shot_data else {}
print("IAP_REVIEW_SCREENSHOT_PRESENT=" + str(shot_data is not None).lower())
if shot_data:
    print("IAP_REVIEW_SCREENSHOT_STATE=" + str(shot_state))

availability = req("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability", optional=True)
print("IAP_AVAILABILITY_PRESENT=" + str(first_data(availability) is not None).lower())

iaps_after = req("GET", f"/v1/apps/{app_id}/inAppPurchasesV2", {"filter[productId]": IAP_PRODUCT_ID, "limit": 10})
print("IAP_STATE_AFTER=" + str(iaps_after["data"][0].get("attributes", {}).get("state")))
print("IAP_LOCALIZATION_COMPLETED=" + str(localized).lower())
print("VERSION_METADATA_FILLED=true")
