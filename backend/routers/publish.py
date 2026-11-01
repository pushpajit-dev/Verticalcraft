from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from loguru import logger
from backend.core.resolver import resolve_clip_path
from backend.core.config import settings
from backend.modules.youtube_publisher import (
    get_youtube_channel_profile,
    generate_oauth_url,
    exchange_auth_code_for_token,
    save_raw_token,
    logout_youtube,
    upload_and_schedule_youtube_short,
)

router = APIRouter()

@router.get("/youtube-status")
async def get_status():
    return get_youtube_channel_profile()

@router.get("/youtube-login")
@router.post("/youtube-login")
async def login():
    """
    Generates a live OAuth URL directing to our built-in callback on port 8765.
    """
    return generate_oauth_url(redirect_uri="http://localhost:8765/publish/oauth2callback")

@router.get("/oauth2callback", response_class=HTMLResponse)
async def oauth2_callback(code: str = None, state: str = None, error: str = None):
    if error:
        return f"""
        <html>
        <body style="background:#0F111A; color:white; font-family:sans-serif; text-align:center; padding:60px;">
            <div style="background:#1E1418; border:2px solid #FF4C4C; border-radius:16px; display:inline-block; padding:30px 50px;">
                <h2 style="color:#FF4C4C;">❌ Google Authorization Cancelled or Failed</h2>
                <p style="color:#CCCCCC; margin-top:10px;">{error}</p>
                <p style="color:#AAAAAA; margin-top:20px; font-size:13px;">You can close this window and try again in VerticalCraft Studio.</p>
            </div>
        </body>
        </html>
        """
    if not code:
        return "Missing authorization code."

    res = exchange_auth_code_for_token(code, state=state, redirect_uri="http://localhost:8765/publish/oauth2callback")
    if res.get("status") == "success":
        return """
        <html>
        <head><title>YouTube Connected</title></head>
        <body style="background:#0F111A; color:white; font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif; text-align:center; padding:60px;">
            <div style="background:#141724; border:2px solid #00F0FF; border-radius:20px; display:inline-block; padding:40px 60px; box-shadow: 0 0 30px rgba(0,240,255,0.2);">
                <div style="font-size:48px; margin-bottom:10px;">🎉</div>
                <h1 style="color:#00F0FF; margin:0 0 10px 0; font-size:24px;">YouTube Channel Connected!</h1>
                <p style="color:#AAAAAA; font-size:14px; margin:0 0 20px 0;">Your Google account has been authorized and credentials saved securely.</p>
                <p style="color:#FFD700; font-size:13px; font-weight:bold;">You can now close this tab and return to VerticalCraft Studio.</p>
                <script>
                    try { window.opener && window.opener.postMessage('oauth_complete', '*'); } catch(e) {}
                    setTimeout(function() { window.close(); }, 2500);
                </script>
            </div>
        </body>
        </html>
        """
    else:
        return f"""
        <html>
        <body style="background:#0F111A; color:white; font-family:sans-serif; text-align:center; padding:60px;">
            <div style="background:#1E1418; border:2px solid #FF4C4C; border-radius:16px; display:inline-block; padding:30px 50px;">
                <h2 style="color:#FF4C4C;">❌ Connection Notice</h2>
                <p style="color:#CCCCCC;">{res.get('message', 'Unknown error')}</p>
                <p style="color:#AAAAAA; margin-top:16px; font-size:12px;">Make sure your email is added to Test Users in Google Cloud Console if the app is in Testing mode.</p>
            </div>
        </body>
        </html>
        """

@router.get("/youtube-auth-url")
async def get_auth_url():
    """
    Returns the Google sign-in URL for direct browser access.
    """
    return generate_oauth_url(redirect_uri="http://localhost:8765/publish/oauth2callback")

@router.post("/youtube-token")
async def submit_raw_token(data: dict = None):
    """
    Saves a raw Google OAuth token JSON or refresh token.
    """
    data = data or {}
    token = data.get("token") or data.get("token_json") or data
    return save_raw_token(token)

@router.post("/youtube-auth-code")
async def submit_auth_code(data: dict = None):
    """
    Exchanges a pasted authorization code for youtube_token.json.
    """
    data = data or {}
    code = data.get("code")
    if not code:
        raise HTTPException(status_code=400, detail="Authorization code is required")
    return exchange_auth_code_for_token(code, redirect_uri="http://localhost:8765/publish/oauth2callback")

@router.get("/youtube-logout")
@router.post("/youtube-logout")
async def logout():
    return logout_youtube()

@router.post("/youtube-schedule")
async def schedule_youtube(data: dict):
    try:
        filename = data.get("filename")
        if not filename:
            raise HTTPException(status_code=400, detail="Filename is required")

        export_dir = Path.home() / "Desktop" / "VerticalCraft_Exports"
        video_path = export_dir / filename
        if not video_path.exists():
            video_path = settings.PROJECTS_DIR / "exports" / filename

        title = data.get("title", "Viral Short")
        description = data.get("description", "#shorts #viral")
        tags = data.get("tags", ["shorts", "viral"])
        aspect_ratio = data.get("aspect_ratio", "9:16")
        category_id = data.get("category_id", "20")
        
        scheduled_iso = data.get("scheduled_time")
        scheduled_dt = None
        if scheduled_iso:
            try:
                scheduled_dt = datetime.datetime.fromisoformat(scheduled_iso)
            except Exception:
                pass

        result = await upload_and_schedule_youtube_short(
            video_path=video_path,
            title=title,
            description=description,
            tags=tags,
            scheduled_time=scheduled_dt,
            category_id=category_id,
            privacy_status=data.get("privacy_status", "private"),
            aspect_ratio=aspect_ratio,
        )
        return result
    except Exception as e:
        logger.error(f"YouTube scheduling failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
