from __future__ import annotations
import subprocess
from pathlib import Path
from fastapi import APIRouter, HTTPException, Response
from backend.modules.clip_analyzer import analyze_clip
from backend.core.resolver import resolve_clip_path
from backend.core.config import settings

router = APIRouter()

@router.get("/clip")
async def analyze(clip_id: str = "", path: str = ""):
    target_clip = resolve_clip_path(clip_id=clip_id, clip_path=path)
    return analyze_clip(target_clip)

@router.get("/frame/{clip_id}")
async def get_preview_frame(clip_id: str):
    """
    Extracts a representative JPEG snapshot frame of the video with FFmpeg and returns the image.
    """
    try:
        target_clip = resolve_clip_path(clip_id=clip_id)
        frame_dir = settings.PROJECTS_DIR / "thumbnails"
        frame_dir.mkdir(parents=True, exist_ok=True)
        frame_path = frame_dir / f"{target_clip.stem}_preview.jpg"

        if not frame_path.exists():
            cmd = [
                "ffmpeg", "-y",
                "-ss", "00:00:02",
                "-i", str(target_clip),
                "-vframes", "1",
                "-q:v", "2",
                str(frame_path),
            ]
            subprocess.run(cmd, capture_output=True, text=True)

        if frame_path.exists():
            return Response(content=frame_path.read_bytes(), media_type="image/jpeg")
        
        raise HTTPException(status_code=404, detail="Frame could not be generated")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
