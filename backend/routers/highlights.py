from __future__ import annotations
from pathlib import Path
from fastapi import APIRouter, HTTPException
from loguru import logger
from backend.core.resolver import resolve_clip_path
from backend.modules.highlight_detector import detect_highlights
from backend.core.config import settings

router = APIRouter()

@router.post("/detect")
async def detect(data: dict):
    try:
        clip_id = data.get("clip_id")
        clip_path_str = data.get("clip_path")
        target_clip = resolve_clip_path(clip_id=clip_id, clip_path=clip_path_str)

        niche = data.get("niche", "general")
        top_n = int(data.get("top_n", 15))
        target_dur = float(data.get("target_duration", 30.0))
        language = data.get("language", "auto")

        logger.info(f"Detecting multi-segment highlights for {target_clip.name} | niche={niche}, top_n={top_n}")

        moments = await detect_highlights(
            clip_path=target_clip,
            niche=niche,
            top_n=top_n,
            transcript=data.get("transcript"),
            use_gemini=data.get("use_gemini", False),
            target_duration=target_dur,
        )

        return {
            "status": "success",
            "clip_id": clip_id,
            "filename": target_clip.name,
            "segment_count": len(moments),
            "highlights": moments,
        }
    except Exception as e:
        logger.error(f"Highlight detection failed: {e}")
        return {
            "status": "error",
            "message": str(e),
            "highlights": [],
        }
