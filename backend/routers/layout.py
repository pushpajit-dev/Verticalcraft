from __future__ import annotations
import shutil
from pathlib import Path
from fastapi import APIRouter, HTTPException
from loguru import logger
from backend.core.resolver import resolve_clip_path
from backend.modules.layout_engine import (
    build_normal_layout,
    build_streamer_layout,
    NormalLayoutConfig,
    StreamerLayoutConfig,
    RATIO_DIMENSIONS,
)
from backend.core.config import settings

router = APIRouter()

@router.post("/build")
async def build_layout(data: dict):
    try:
        clip_id = data.get("clip_id")
        clip_path_str = data.get("clip_path")
        target_clip = resolve_clip_path(clip_id=clip_id, clip_path=clip_path_str)

        face_clip_id = data.get("face_clip_id")
        face_clip = resolve_clip_path(clip_id=face_clip_id) if face_clip_id else target_clip

        layout_type = data.get("layout_type", "normal")
        aspect_ratio = data.get("aspect_ratio", "9:16")
        dim = RATIO_DIMENSIONS.get(aspect_ratio, (1080, 1920))

        output_dir = settings.PROJECTS_DIR / "renders"
        output_dir.mkdir(parents=True, exist_ok=True)
        out_filename = f"{target_clip.stem}_{layout_type}_{aspect_ratio.replace(':', 'x')}.mp4"
        out_path = output_dir / out_filename

        logo_path = data.get("logo_path", "")
        logo_opacity = float(data.get("logo_opacity", 0.8))
        logo_position = data.get("logo_position", "top-right")

        logger.info(f"Building {layout_type} layout ({aspect_ratio}) for {target_clip.name} -> {out_path.name}")

        if layout_type == "streamer":
            cfg = StreamerLayoutConfig(
                face_clip_path=str(face_clip),
                gameplay_clip_path=str(target_clip),
                aspect_ratio=aspect_ratio,
                face_ratio=float(data.get("face_ratio", 0.38)),
                duration=float(data.get("duration", 60.0)),
                output_path=str(out_path),
                logo_path=logo_path,
                logo_opacity=logo_opacity,
                logo_position=logo_position,
            )
            result = build_streamer_layout(cfg)
        else:
            cfg = NormalLayoutConfig(
                clip_path=str(target_clip),
                aspect_ratio=aspect_ratio,
                zoom_scale=float(data.get("zoom_scale", 1.0)),
                pan_x=float(data.get("pan_x", 0.0)),
                pan_y=float(data.get("pan_y", 0.0)),
                crop_mode=data.get("crop_mode", "smart"),
                duration=float(data.get("duration", 60.0)),
                output_path=str(out_path),
                logo_path=logo_path,
                logo_opacity=logo_opacity,
                logo_position=logo_position,
            )
            result = build_normal_layout(cfg)

        return {
            "status": "success",
            "output_path": str(result),
            "filename": out_filename,
            "layout_type": layout_type,
            "aspect_ratio": aspect_ratio,
            "resolution": f"{dim[0]}x{dim[1]}",
        }
    except Exception as e:
        logger.error(f"Layout build failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
