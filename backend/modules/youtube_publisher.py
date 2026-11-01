from __future__ import annotations
import os, json, datetime, urllib.parse, webbrowser, threading
from pathlib import Path
from typing import Optional, Any
from loguru import logger
from backend.core.config import settings

def get_client_secrets_path() -> Optional[Path]:
    candidates = [
        settings.BASE_DIR / "client_secrets.json",
        settings.BASE_DIR / "backend" / "client_secrets.json",
        Path.home() / "Desktop" / "client_secrets.json",
        Path.home() / "Desktop" / "VerticalCraft_Exports" / "client_secrets.json",
        Path.cwd() / "client_secrets.json",
    ]
    for p in candidates:
        if p.exists() and p.stat().st_size > 10:
            return p
    return None

def get_token_file_path() -> Path:
    return settings.BASE_DIR / "youtube_token.json"

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
]

_active_flows: dict[str, Any] = {}

def get_youtube_channel_profile() -> dict[str, Any]:
    token_file = get_token_file_path()
    secrets_file = get_client_secrets_path()

    if not token_file.exists() or token_file.stat().st_size == 0:
        return {
            "is_authenticated": False,
            "has_client_secrets": secrets_file is not None,
            "client_secrets_path": str(secrets_file) if secrets_file else None,
            "name": "Guest Creator",
            "email": "Not connected",
            "channel_title": "No Channel Linked",
            "channel_id": None,
            "avatar_url": None,
            "subscriber_count": "0",
        }

    try:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        token_data = {}
        try:
            token_data = json.loads(token_file.read_text())
        except Exception:
            pass

        client_secrets_data = {}
        if secrets_file and secrets_file.exists():
            try:
                client_secrets_data = json.loads(secrets_file.read_text())
            except Exception:
                pass
        c_info = client_secrets_data.get("installed") or client_secrets_data.get("web") or {}

        client_id = token_data.get("client_id") or c_info.get("client_id")
        client_secret = token_data.get("client_secret") or c_info.get("client_secret")
        token_uri = token_data.get("token_uri") or c_info.get("token_uri", "https://oauth2.googleapis.com/token")

        if token_data.get("token") or token_data.get("access_token"):
            creds = Credentials(
                token=token_data.get("token") or token_data.get("access_token"),
                refresh_token=token_data.get("refresh_token"),
                token_uri=token_uri,
                client_id=client_id,
                client_secret=client_secret,
                scopes=SCOPES,
            )
        else:
            creds = Credentials.from_authorized_user_file(str(token_file))

        email = token_data.get("email", "connected@gmail.com")
        name = "Creator"
        channel_title = "Connected YouTube Channel"
        channel_id = None
        avatar_url = None
        subscriber_count = "0"

        # 1. Fetch real Google Userinfo (Email, Name, Picture)
        try:
            oauth2 = build("oauth2", "v2", credentials=creds)
            user_info = oauth2.userinfo().get().execute()
            if user_info.get("email"):
                email = user_info["email"]
            if user_info.get("name"):
                name = user_info["name"]
            if user_info.get("picture"):
                avatar_url = user_info["picture"]
        except Exception as oe:
            logger.warning(f"Could not fetch Google userinfo: {oe}")

        # 2. Fetch YouTube Channel details
        try:
            youtube = build("youtube", "v3", credentials=creds)
            ch_resp = youtube.channels().list(part="snippet,statistics", mine=True).execute()
            if ch_resp.get("items"):
                item = ch_resp["items"][0]
                channel_id = item.get("id")
                channel_title = item.get("snippet", {}).get("title", channel_title)
                subscriber_count = item.get("statistics", {}).get("subscriberCount", "0")
                if not avatar_url or avatar_url.startswith("http"):
                    avatar_url = item.get("snippet", {}).get("thumbnails", {}).get("default", {}).get("url", avatar_url)
        except Exception as ce:
            logger.warning(f"Could not fetch channel metadata: {ce}")

        return {
            "is_authenticated": True,
            "has_client_secrets": True,
            "name": name,
            "email": email,
            "channel_title": channel_title,
            "channel_id": channel_id,
            "avatar_url": avatar_url,
            "subscriber_count": subscriber_count,
        }
    except Exception as e:
        logger.warning(f"Error loading YouTube profile: {e}")
        return {
            "is_authenticated": False,
            "has_client_secrets": secrets_file is not None,
            "message": str(e),
        }

def generate_oauth_url(redirect_uri: str = "http://localhost:8765/publish/oauth2callback") -> dict:
    """
    Generates a valid Google OAuth 2.0 loopback URL for in-browser sign-in.
    """
    secrets_file = get_client_secrets_path()
    if not secrets_file:
        return {"status": "error", "message": "client_secrets.json not found on disk."}

    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
        flow = InstalledAppFlow.from_client_secrets_file(
            str(secrets_file),
            SCOPES,
            redirect_uri=redirect_uri,
        )
        auth_url, state = flow.authorization_url(prompt="consent", access_type="offline")
        _active_flows[state] = flow
        return {"status": "success", "auth_url": auth_url, "state": state, "redirect_uri": redirect_uri}
    except Exception as e:
        return {"status": "error", "message": str(e)}

def save_raw_token(token_data: dict | str) -> dict:
    """
    Saves a raw Google OAuth token or refresh token JSON directly.
    """
    token_path = get_token_file_path()
    try:
        if isinstance(token_data, str):
            token_dict = json.loads(token_data)
        else:
            token_dict = token_data

        with open(token_path, "w") as f:
            json.dump(token_dict, f, indent=2)
        logger.info(f"Saved custom YouTube credentials to {token_path}")
        return {"status": "success", "message": "YouTube credentials saved successfully!"}
    except Exception as e:
        return {"status": "error", "message": f"Failed to save token: {e}"}

def exchange_auth_code_for_token(code: str, state: str = None, redirect_uri: str = "http://localhost:8765/publish/oauth2callback") -> dict:
    """
    Exchanges the authorization code for a token and saves youtube_token.json.
    """
    secrets_file = get_client_secrets_path()
    if not secrets_file:
        return {"status": "error", "message": "client_secrets.json not found."}

    # 1. Try matching active Flow with PKCE code_verifier
    global _active_flows
    flow = _active_flows.get(state) if state else None
    if flow:
        try:
            flow.fetch_token(code=code.strip())
            creds = flow.credentials
            token_path = get_token_file_path()
            with open(token_path, "w") as f:
                f.write(creds.to_json())
            logger.info(f"Successfully saved YouTube OAuth credentials to {token_path}")
            return {"status": "success", "message": "Channel connected successfully!"}
        except Exception as fe:
            logger.warning(f"Flow fetch_token attempt failed: {fe}")

    # 2. Try standard InstalledAppFlow variations
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
        uris_to_try = [redirect_uri, "http://localhost:8765/publish/oauth2callback", "http://127.0.0.1:8765/publish/oauth2callback"]
        for r_uri in uris_to_try:
            try:
                test_flow = InstalledAppFlow.from_client_secrets_file(str(secrets_file), SCOPES, redirect_uri=r_uri)
                test_flow.fetch_token(code=code.strip())
                creds = test_flow.credentials
                token_path = get_token_file_path()
                with open(token_path, "w") as f:
                    f.write(creds.to_json())
                logger.info(f"Successfully saved YouTube OAuth credentials to {token_path}")
                return {"status": "success", "message": "Channel connected successfully!"}
            except Exception:
                continue
    except Exception:
        pass

    # 3. Direct HTTP token exchange fallback
    try:
        import urllib.request, urllib.parse
        client_data = json.loads(secrets_file.read_text())
        c_info = client_data.get("installed") or client_data.get("web") or {}
        client_id = c_info.get("client_id")
        client_secret = c_info.get("client_secret")
        token_uri = c_info.get("token_uri", "https://oauth2.googleapis.com/token")

        post_data = urllib.parse.urlencode({
            "code": code.strip(),
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        }).encode("utf-8")

        req = urllib.request.Request(token_uri, data=post_data, headers={"Content-Type": "application/x-www-form-urlencoded"})
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read().decode("utf-8"))
            token_resp["client_id"] = client_id
            token_resp["client_secret"] = client_secret
            token_path = get_token_file_path()
            with open(token_path, "w") as f:
                json.dump(token_resp, f, indent=2)
            logger.info(f"Saved direct exchanged token to {token_path}")
            return {"status": "success", "message": "Channel connected successfully!"}
    except Exception as de:
        logger.error(f"Direct token exchange error: {de}")

    return {"status": "error", "message": "Failed to exchange authorization code. Please verify the code or add your email to Google Cloud Test Users."}

def start_in_app_oauth_server():
    global _auth_thread
    secrets_file = get_client_secrets_path()
    if not secrets_file:
        return {"status": "error", "message": "client_secrets.json not found on disk."}

    def _run_flow():
        try:
            from google_auth_oauthlib.flow import InstalledAppFlow
            flow = InstalledAppFlow.from_client_secrets_file(str(secrets_file), SCOPES)
            # Use specific bind address 127.0.0.1 to avoid Windows socket issues
            creds = flow.run_local_server(host="127.0.0.1", port=8766, prompt="consent", open_browser=True)
            token_path = get_token_file_path()
            with open(token_path, "w") as f:
                f.write(creds.to_json())
            logger.info(f"Successfully saved YouTube OAuth credentials to {token_path}")
        except Exception as e:
            logger.warning(f"Local server notice ({e}) — falling back to browser flow")

    _auth_thread = threading.Thread(target=_run_flow, daemon=True)
    _auth_thread.start()
    return {"status": "started", "message": "Authorization started! If browser doesn't open automatically, use manual code entry."}

def logout_youtube() -> dict:
    token_file = get_token_file_path()
    if token_file.exists():
        try: os.remove(token_file)
        except Exception: pass
    return {"status": "success", "message": "Disconnected YouTube channel."}

async def upload_and_schedule_youtube_short(
    video_path: Path,
    title: str,
    description: str,
    tags: list[str],
    scheduled_time: Optional[datetime.datetime] = None,
    category_id: str = "20",
    privacy_status: str = "private",
    aspect_ratio: str = "9:16",
) -> dict:
    logger.info(f"Uploading to YouTube: {video_path.name} | Ratio={aspect_ratio}")
    if not video_path.exists():
        raise FileNotFoundError(f"Video file {video_path} not found")

    is_shorts = (aspect_ratio == "9:16" or "vertical" in video_path.name.lower())
    if is_shorts and "#shorts" not in title.lower() and "#shorts" not in description.lower():
        title = f"{title} #shorts"

    body = {
        "snippet": {
            "title": title[:100],
            "description": description,
            "tags": tags,
            "categoryId": category_id,
        },
        "status": {
            "privacyStatus": "private" if scheduled_time else privacy_status,
            "selfDeclaredMadeForKids": False,
        }
    }

    if scheduled_time:
        utc_iso = scheduled_time.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        body["status"]["publishAt"] = utc_iso
        body["status"]["privacyStatus"] = "private"

    token_file = get_token_file_path()
    if not token_file.exists():
        return {
            "status": "pending_auth",
            "message": "YouTube account not connected. Tap 'Connect Channel' in the app to sign in with Google.",
            "video_title": title,
            "scheduled_time": scheduled_time.isoformat() if scheduled_time else "Immediate",
        }

    try:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload

        creds = Credentials.from_authorized_user_file(str(token_file))
        youtube = build("youtube", "v3", credentials=creds)

        media = MediaFileUpload(str(video_path), mimetype="video/mp4", resumable=True)
        request = youtube.videos().insert(
            part="snippet,status",
            body=body,
            media_body=media,
        )
        response = await asyncio.to_thread(request.execute)
        video_id = response.get("id")

        return {
            "status": "success",
            "video_id": video_id,
            "is_shorts": is_shorts,
            "youtube_url": f"https://youtube.com/shorts/{video_id}" if is_shorts else f"https://youtu.be/{video_id}",
            "scheduled_time": scheduled_time.isoformat() if scheduled_time else "Immediate",
            "title": title,
        }
    except Exception as e:
        logger.error(f"YouTube upload error: {e}")
        return {
            "status": "error",
            "message": f"Upload failed: {e}",
            "video_title": title,
        }
