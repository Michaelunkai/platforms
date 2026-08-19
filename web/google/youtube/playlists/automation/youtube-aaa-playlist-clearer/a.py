#!/usr/bin/env python3
r"""
Force-clear YouTube playlist `aaa` safely and fast using the logged-in local Chrome Profile 2 session.

Default target:
  Playlist name: aaa
  Playlist ID:   PLtD44E7z8BkPPFsTc0pLUC2LCJh8HrgQA

What it does every run:
  1. Copies Chrome Profile 2 cookie DB to a temp file (does not modify Chrome/profile).
  2. Decrypts YouTube cookies using Windows DPAPI + Chrome AES-GCM key.
  3. Opens the live authenticated playlist through YouTube/Innertube.
  4. Collects current playlist rows using setVideoId (the safe row-removal identifier).
  5. Removes all current rows from this playlist only with ACTION_REMOVE_VIDEO.
  6. Re-reads the live playlist and exits only when zero rows remain.

Run from Windows PowerShell 5:
  py -3 F:\Downloads\a.py

Optional:
  py -3 F:\Downloads\a.py --dry-run
  py -3 F:\Downloads\a.py --playlist-id PLxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"""

import argparse
import base64
import ctypes
import ctypes.wintypes
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# PowerShell 5 consoles are often legacy code pages; keep output safe for any title.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

DEFAULT_PLAYLIST_ID = "PLtD44E7z8BkPPFsTc0pLUC2LCJh8HrgQA"
DEFAULT_PLAYLIST_NAME = "aaa"
YOUTUBE_ORIGIN = "https://www.youtube.com"
PROFILE_DIR = Path(os.environ.get("LOCALAPPDATA", r"C:\Users\micha\AppData\Local")) / "Google" / "Chrome" / "User Data" / "Profile 2"
LOCAL_STATE = PROFILE_DIR.parent / "Local State"
COOKIE_DB = PROFILE_DIR / "Network" / "Cookies"

class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

crypt32 = ctypes.windll.crypt32
kernel32 = ctypes.windll.kernel32


def _dpapi_unprotect(encrypted: bytes) -> bytes:
    in_blob = DATA_BLOB(len(encrypted), ctypes.cast(ctypes.create_string_buffer(encrypted), ctypes.POINTER(ctypes.c_char)))
    out_blob = DATA_BLOB()
    if not crypt32.CryptUnprotectData(ctypes.byref(in_blob), None, None, None, None, 0, ctypes.byref(out_blob)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out_blob.pbData, out_blob.cbData)
    finally:
        kernel32.LocalFree(out_blob.pbData)


def chrome_master_key() -> bytes:
    data = json.loads(LOCAL_STATE.read_text(encoding="utf-8"))
    enc_key = base64.b64decode(data["os_crypt"]["encrypted_key"])
    if enc_key.startswith(b"DPAPI"):
        enc_key = enc_key[5:]
    return _dpapi_unprotect(enc_key)


def decrypt_cookie_value(encrypted_value: bytes, key: bytes) -> str:
    if not encrypted_value:
        return ""
    try:
        if encrypted_value.startswith((b"v10", b"v11", b"v20")):
            nonce = encrypted_value[3:15]
            ciphertext = encrypted_value[15:]
            raw = AESGCM(key).decrypt(nonce, ciphertext, None)
            # Newer Chrome may prefix decrypted cookie value with a 32-byte host hash.
            if len(raw) >= 33 and any(b < 9 or (13 < b < 32) for b in raw[:32]):
                raw = raw[32:]
            elif len(raw) >= 32:
                maybe = raw[32:]
                try:
                    maybe.decode("utf-8")
                    if not raw[:32].decode("utf-8", "ignore").strip():
                        raw = maybe
                except Exception:
                    pass
            return raw.decode("utf-8", "replace")
        return _dpapi_unprotect(encrypted_value).decode("utf-8", "replace")
    except Exception:
        return ""


def load_youtube_cookies() -> Tuple[requests.Session, Dict[str, str]]:
    if not COOKIE_DB.exists():
        raise FileNotFoundError(f"Chrome Profile 2 cookie DB not found: {COOKIE_DB}")
    key = chrome_master_key()
    tmp = Path(tempfile.gettempdir()) / f"yt_cookies_{os.getpid()}_{int(time.time())}.sqlite"
    shutil.copy2(str(COOKIE_DB), str(tmp))
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9,he;q=0.8",
    })
    simple: Dict[str, str] = {}
    try:
        con = sqlite3.connect(str(tmp))
        cur = con.execute("SELECT host_key, name, path, encrypted_value, value, is_secure, expires_utc FROM cookies WHERE host_key LIKE '%youtube.com' OR host_key LIKE '%google.com'")
        for host, name, path, encrypted_value, value, is_secure, _expires in cur.fetchall():
            val = value or decrypt_cookie_value(encrypted_value, key)
            if not val:
                continue
            simple[name] = val
            session.cookies.set(name, val, domain=host, path=path or "/", secure=bool(is_secure))
        con.close()
    finally:
        try:
            tmp.unlink()
        except Exception:
            pass
    if "SAPISID" not in simple and "__Secure-3PAPISID" not in simple and "__Secure-1PAPISID" not in simple:
        raise RuntimeError("No SAPISID-family YouTube auth cookie found in Chrome Profile 2. Open/log into YouTube in Profile 2 first.")
    return session, simple


def extract_balanced_object(text: str, start: int) -> str:
    open_pos = text.find("{", start)
    if open_pos < 0:
        raise ValueError("No object start found")
    depth = 0
    in_str = False
    esc = False
    quote = ""
    for i in range(open_pos, len(text)):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                in_str = False
        else:
            if ch in ('"', "'"):
                in_str = True
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[open_pos:i+1]
    raise ValueError("Object was not balanced")


def extract_ytcfg(html: str) -> Dict[str, Any]:
    # YouTube may call ytcfg.set('KEY','VALUE') before the full config object.
    # We need the later ytcfg.set({...}) object that contains INNERTUBE_* fields.
    idx = html.find("ytcfg.set({")
    if idx < 0:
        idx = html.find('"INNERTUBE_API_KEY"')
        if idx >= 0:
            idx = html.rfind("ytcfg.set(", 0, idx)
    if idx < 0:
        raise RuntimeError("Could not find ytcfg object in authenticated YouTube page")
    raw = extract_balanced_object(html, idx)
    return json.loads(raw)


def auth_headers(cookies: Dict[str, str], client_name: str, client_version: str, referer: str) -> Dict[str, str]:
    sapisid = cookies.get("SAPISID") or cookies.get("__Secure-3PAPISID") or cookies.get("__Secure-1PAPISID")
    if not sapisid:
        raise RuntimeError("Missing SAPISID cookie for YouTube authorization")
    ts = str(int(time.time()))
    digest = hashlib.sha1(f"{ts} {sapisid} {YOUTUBE_ORIGIN}".encode("utf-8")).hexdigest()
    return {
        "Content-Type": "application/json",
        "Origin": YOUTUBE_ORIGIN,
        "X-Origin": YOUTUBE_ORIGIN,
        "Referer": referer,
        "Authorization": f"SAPISIDHASH {ts}_{digest}",
        "X-Goog-AuthUser": "0",
        "X-YouTube-Client-Name": str(client_name),
        "X-YouTube-Client-Version": client_version,
    }


def walk(obj: Any) -> Iterable[Any]:
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk(v)


def text_from_runs(obj: Any) -> str:
    if isinstance(obj, dict):
        if "simpleText" in obj:
            return str(obj["simpleText"])
        if "runs" in obj and isinstance(obj["runs"], list):
            return "".join(str(r.get("text", "")) for r in obj["runs"] if isinstance(r, dict))
    return ""


def collect_playlist_rows(data: Any) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    seen = set()
    for node in walk(data):
        r = node.get("playlistVideoRenderer") if isinstance(node, dict) else None
        if not isinstance(r, dict):
            continue
        vid = r.get("videoId") or ""
        set_id = r.get("setVideoId") or ""
        if not vid or not set_id or set_id in seen:
            continue
        seen.add(set_id)
        rows.append({
            "videoId": vid,
            "setVideoId": set_id,
            "title": text_from_runs(r.get("title")) or vid,
        })
    return rows


def collect_continuation_tokens(data: Any) -> List[str]:
    tokens = []
    for node in walk(data):
        if not isinstance(node, dict):
            continue
        token = node.get("token")
        if token and ("continuationCommand" in node or "reloadContinuationData" in node or "nextContinuationData" in node):
            tokens.append(token)
    return list(dict.fromkeys(tokens))


def innertube_post(session: requests.Session, url: str, headers: Dict[str, str], body: Dict[str, Any]) -> Dict[str, Any]:
    r = session.post(url, headers=headers, json=body, timeout=45)
    if r.status_code != 200:
        raise RuntimeError(f"YouTube API HTTP {r.status_code}: {r.text[:500]}")
    return r.json()


def read_playlist_rows(session: requests.Session, api_key: str, context: Dict[str, Any], headers: Dict[str, str], playlist_id: str) -> List[Dict[str, str]]:
    browse_url = f"{YOUTUBE_ORIGIN}/youtubei/v1/browse?key={api_key}&prettyPrint=false"
    rows: List[Dict[str, str]] = []
    seen_set = set()
    first = innertube_post(session, browse_url, headers, {"context": context, "browseId": "VL" + playlist_id})
    queue = collect_continuation_tokens(first)
    for row in collect_playlist_rows(first):
        if row["setVideoId"] not in seen_set:
            rows.append(row); seen_set.add(row["setVideoId"])
    # Continue enough for large playlists, but stay bounded.
    for token in queue[:200]:
        try:
            data = innertube_post(session, browse_url, headers, {"context": context, "continuation": token})
        except Exception:
            continue
        for row in collect_playlist_rows(data):
            if row["setVideoId"] not in seen_set:
                rows.append(row); seen_set.add(row["setVideoId"])
        for t in collect_continuation_tokens(data):
            if t not in queue:
                queue.append(t)
    return rows


def remove_rows(session: requests.Session, api_key: str, context: Dict[str, Any], headers: Dict[str, str], playlist_id: str, rows: List[Dict[str, str]]) -> None:
    edit_url = f"{YOUTUBE_ORIGIN}/youtubei/v1/browse/edit_playlist?key={api_key}&prettyPrint=false"
    actions = [{"setVideoId": r["setVideoId"], "action": "ACTION_REMOVE_VIDEO"} for r in rows]
    if not actions:
        return
    # YouTube accepted 21 in one batch; chunk to keep requests safe for larger playlists.
    for i in range(0, len(actions), 50):
        chunk = actions[i:i+50]
        data = innertube_post(session, edit_url, headers, {"context": context, "playlistId": playlist_id, "actions": chunk})
        status = data.get("status") or data.get("feedbackResponses", [{}])[0].get("status")
        if status and status != "STATUS_SUCCEEDED":
            raise RuntimeError(f"Batch remove returned non-success status: {status}; response={str(data)[:700]}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Fast clear all videos from the logged-in YouTube playlist aaa using Chrome Profile 2 cookies.")
    ap.add_argument("--playlist-id", default=DEFAULT_PLAYLIST_ID)
    ap.add_argument("--playlist-name", default=DEFAULT_PLAYLIST_NAME)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    playlist_url = f"{YOUTUBE_ORIGIN}/playlist?list={args.playlist_id}"
    print(f"TARGET_PLAYLIST={args.playlist_name}")
    print(f"PLAYLIST_ID={args.playlist_id}")
    print(f"PLAYLIST_URL={playlist_url}")

    session, cookies = load_youtube_cookies()
    page = session.get(playlist_url, timeout=45, allow_redirects=True)
    if "accounts.google.com" in page.url or "Sign in" in page.text[:200000]:
        raise RuntimeError(f"Not authenticated to YouTube with Chrome Profile 2 cookies; final_url={page.url}")
    ytcfg = extract_ytcfg(page.text)
    api_key = ytcfg.get("INNERTUBE_API_KEY")
    client_name = ytcfg.get("INNERTUBE_CLIENT_NAME") or ytcfg.get("INNERTUBE_CONTEXT", {}).get("client", {}).get("clientName", "WEB")
    client_version = ytcfg.get("INNERTUBE_CLIENT_VERSION") or ytcfg.get("INNERTUBE_CONTEXT", {}).get("client", {}).get("clientVersion")
    context = ytcfg.get("INNERTUBE_CONTEXT")
    if not api_key or not client_version or not context:
        raise RuntimeError("Missing Innertube config from live YouTube page")
    headers = auth_headers(cookies, str(client_name), str(client_version), playlist_url)

    before = read_playlist_rows(session, api_key, context, headers, args.playlist_id)
    print(f"FOUND_ROWS={len(before)}")
    for idx, row in enumerate(before, 1):
        print(f"ROW[{idx}] videoId={row['videoId']} setVideoId={row['setVideoId']} title={row['title'][:120]}")

    if args.dry_run:
        print("DRY_RUN=1")
        print("RESULT=PASS")
        return 0

    remove_rows(session, api_key, context, headers, args.playlist_id, before)
    time.sleep(2)
    after = read_playlist_rows(session, api_key, context, headers, args.playlist_id)
    print(f"VERIFY_ROWS={len(after)}")
    if after:
        # Retry once for anything that survived, then verify again.
        print("RETRY_REMAINING=1")
        remove_rows(session, api_key, context, headers, args.playlist_id, after)
        time.sleep(2)
        after = read_playlist_rows(session, api_key, context, headers, args.playlist_id)
        print(f"VERIFY_ROWS_AFTER_RETRY={len(after)}")
    if after:
        for idx, row in enumerate(after, 1):
            print(f"REMAINING[{idx}] videoId={row['videoId']} setVideoId={row['setVideoId']} title={row['title'][:120]}")
        print("RESULT=FAIL")
        return 2
    print(f"REMOVED_ROWS={len(before)}")
    print("RESULT=PASS")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print("RESULT=FAIL")
        print(f"ERROR={type(e).__name__}: {e}")
        raise SystemExit(1)
