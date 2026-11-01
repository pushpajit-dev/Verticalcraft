from __future__ import annotations
import shutil, uuid, os
from pathlib import Path
from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel
from loguru import logger
from backend.modules.importer import download_from_url, validate_media_file, SUPPORTED_VIDEO_EXTS
from backend.modules.clip_analyzer import analyze_clip
from backend.core.config import settings

router = APIRouter()

class UrlImportRequest(BaseModel):
    url: str
    quality: str = "best"
    output_format: str = "mp4"

class BatchUrlImportRequest(BaseModel):
    urls: list[str]
    quality: str = "best"
    output_format: str = "mp4"

@router.get("/library")
async def get_library():
    imports_dir = settings.PROJECTS_DIR / "imports"
    if not imports_dir.exists():
        return {"clips": []}
    
    clips = []
    for item in sorted(imports_dir.iterdir(), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True):
        if item.is_dir():
            files = [f for f in item.iterdir() if f.suffix.lower() in SUPPORTED_VIDEO_EXTS]
            if files:
                target_file = files[0]
                try:
                    metadata = analyze_clip(target_file)
                    clips.append({
                        "clip_id": item.name,
                        "filename": target_file.name,
                        "path": str(target_file),
                        "metadata": metadata,
                        "size_mb": round(target_file.stat().st_size / (1024 * 1024), 2),
                    })
                except Exception as e:
                    logger.warning(f"Could not analyze {target_file}: {e}")
                    clips.append({
                        "clip_id": item.name,
                        "filename": target_file.name,
                        "path": str(target_file),
                        "metadata": {"filename": target_file.name, "duration": 0, "video": {"width": 1920, "height": 1080, "aspect_ratio": "16:9", "fps": 30}},
                        "size_mb": round(target_file.stat().st_size / (1024 * 1024), 2),
                    })
    return {"clips": clips}

@router.delete("/clip/{clip_id}")
async def delete_clip(clip_id: str):
    clip_dir = settings.PROJECTS_DIR / "imports" / clip_id
    if clip_dir.exists():
        shutil.rmtree(clip_dir, ignore_errors=True)
        return {"status": "success", "message": f"Deleted clip {clip_id}"}
    raise HTTPException(status_code=404, detail="Clip not found")

@router.delete("/library/clear")
async def clear_library():
    imports_dir = settings.PROJECTS_DIR / "imports"
    if imports_dir.exists():
        for item in imports_dir.iterdir():
            if item.is_dir():
                shutil.rmtree(item, ignore_errors=True)
    return {"status": "success", "message": "Library cleared"}

@router.post("/url")
async def import_from_url(request: UrlImportRequest):
    try:
        clip_id = str(uuid.uuid4())
        output_dir = settings.PROJECTS_DIR / "imports" / clip_id
        output_dir.mkdir(parents=True, exist_ok=True)
        file_path = await download_from_url(
            url=request.url, output_dir=output_dir,
            quality=request.quality, output_format=request.output_format,
        )
        metadata = analyze_clip(file_path)
        return {"clip_id": clip_id, "path": str(file_path), "metadata": metadata}
    except Exception as e:
        logger.error(f"URL import failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/batch-urls")
async def import_batch_urls(request: BatchUrlImportRequest):
    results = []
    for url in request.urls:
        url = url.strip()
        if not url: continue
        try:
            clip_id = str(uuid.uuid4())
            output_dir = settings.PROJECTS_DIR / "imports" / clip_id
            output_dir.mkdir(parents=True, exist_ok=True)
            file_path = await download_from_url(
                url=url, output_dir=output_dir,
                quality=request.quality, output_format=request.output_format,
            )
            metadata = analyze_clip(file_path)
            results.append({"url": url, "status": "success", "clip_id": clip_id, "path": str(file_path), "metadata": metadata})
        except Exception as e:
            logger.error(f"Batch URL import error for {url}: {e}")
            results.append({"url": url, "status": "error", "error": str(e)})
    return {"results": results}

@router.post("/file")
async def import_file(file: UploadFile = File(...)):
    try:
        clip_id = str(uuid.uuid4())
        output_dir = settings.PROJECTS_DIR / "imports" / clip_id
        output_dir.mkdir(parents=True, exist_ok=True)
        file_path = output_dir / file.filename
        with open(file_path, "wb") as f:
            shutil.copyfileobj(file.file, f)
        if not validate_media_file(file_path):
            raise HTTPException(status_code=400, detail="Invalid or unsupported media file")
        metadata = analyze_clip(file_path)
        return {"clip_id": clip_id, "path": str(file_path), "metadata": metadata}
    except Exception as e:
        logger.error(f"File import failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
