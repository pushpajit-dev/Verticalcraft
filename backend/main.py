from __future__ import annotations
import os, subprocess
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from loguru import logger
from backend.core.config import settings
from backend.core.resolver import resolve_clip_path
from backend.modules.audio_mixer import split_audio_tracks_sync
from backend.routers import importer, analyzer, layout, captions, audio, highlights, export, publish, projects

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"VerticalCraft Backend running on port {settings.PORT}")
    settings.PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    settings.TEMP_DIR.mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "imports").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "renders").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "exports").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "thumbnails").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "audio").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "stems").mkdir(parents=True, exist_ok=True)
    (settings.PROJECTS_DIR / "saved_projects").mkdir(parents=True, exist_ok=True)
    yield
    logger.info("VerticalCraft Backend shutting down")

app = FastAPI(title="VerticalCraft AI Video Studio API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

app.include_router(importer.router,   prefix="/import",     tags=["Import"])
app.include_router(analyzer.router,   prefix="/analyze",    tags=["Analyze"])
app.include_router(layout.router,     prefix="/layout",     tags=["Layout"])
app.include_router(captions.router,   prefix="/captions",   tags=["Captions"])
app.include_router(audio.router,      prefix="/audio",      tags=["Audio"])
app.include_router(highlights.router, prefix="/highlights", tags=["Highlights"])
app.include_router(export.router,     prefix="/export",     tags=["Export"])
app.include_router(publish.router,    prefix="/publish",    tags=["Publish"])
app.include_router(projects.router,   prefix="/projects",   tags=["Projects"])

@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}

@app.get("/system/hardware")
async def get_hardware():
    from backend.core.hardware import detect_system_hardware
    return detect_system_hardware()

@app.get("/media/video/{clip_id}")
async def stream_video(clip_id: str, request: Request):
    """
    Streams the imported video with HTTP range support for in-app video playback.
    """
    try:
        video_path = resolve_clip_path(clip_id=clip_id)
        if not video_path.exists():
            raise HTTPException(status_code=404, detail="Video file not found")
        
        file_size = video_path.stat().st_size
        range_header = request.headers.get("Range")
        
        if range_header:
            byte1, byte2 = 0, None
            m = range_header.replace("bytes=", "").split("-")
            byte1 = int(m[0])
            if len(m) > 1 and m[1]:
                byte2 = int(m[1])
            else:
                byte2 = file_size - 1
            length = byte2 - byte1 + 1
            
            def iter_file():
                with open(video_path, "rb") as f:
                    f.seek(byte1)
                    left = length
                    while left > 0:
                        chunk = f.read(min(left, 1024 * 1024))
                        if not chunk:
                            break
                        left -= len(chunk)
                        yield chunk

            headers = {
                "Content-Range": f"bytes {byte1}-{byte2}/{file_size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(length),
                "Content-Type": "video/mp4",
            }
            return StreamingResponse(iter_file(), status_code=206, headers=headers)
        
        return FileResponse(video_path, media_type="video/mp4", filename=video_path.name)
    except Exception as e:
        logger.error(f"Error streaming video: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/media/audio/{clip_id}")
async def stream_audio(clip_id: str, stem: str = "master"):
    """
    Extracts and streams clean MP3/WAV audio tracks, multi-speaker stems, or BGM.
    Auto-generates stems on-the-fly if not already split.
    """
    try:
        target_clip = resolve_clip_path(clip_id=clip_id)
        stems_dir = settings.PROJECTS_DIR / "stems" / target_clip.stem
        
        # Check if specific stem requested
        if stem in ["vocals", "bgm", "drums", "bass", "other", "speaker_1", "speaker_2", "speaker_3"]:
            stem_path = stems_dir / f"{stem}.wav"
            if not stem_path.exists() or stem_path.stat().st_size == 0:
                logger.info(f"Stem {stem} requested on-the-fly -> generating stems for {target_clip.name}")
                split_audio_tracks_sync(target_clip, stems_dir)

            if stem_path.exists() and stem_path.stat().st_size > 0:
                return FileResponse(stem_path, media_type="audio/wav", filename=f"{target_clip.stem}_{stem}.wav")

        audio_dir = settings.PROJECTS_DIR / "audio"
        audio_dir.mkdir(parents=True, exist_ok=True)
        audio_path = audio_dir / f"{target_clip.stem}_audio.mp3"

        if not audio_path.exists() or audio_path.stat().st_size == 0:
            cmd = [
                "ffmpeg", "-y",
                "-i", str(target_clip),
                "-vn", "-ar", "44100", "-ac", "2",
                "-c:a", "libmp3lame", "-b:a", "192k",
                str(audio_path),
            ]
            subprocess.run(cmd, capture_output=True, text=True)

        if audio_path.exists() and audio_path.stat().st_size > 0:
            return FileResponse(audio_path, media_type="audio/mpeg", filename=audio_path.name)
        
        raise HTTPException(status_code=404, detail="Audio track not found in video")
    except Exception as e:
        logger.error(f"Error extracting audio track: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/media/frame/{clip_id}")
async def get_preview_frame(clip_id: str, timestamp_sec: float = 2.0):
    """
    Extracts a representative JPEG snapshot frame using FFmpeg at a specific timestamp.
    """
    try:
        target_clip = resolve_clip_path(clip_id=clip_id)
        frame_dir = settings.PROJECTS_DIR / "thumbnails"
        frame_dir.mkdir(parents=True, exist_ok=True)
        
        t_int = int(max(0.0, timestamp_sec))
        frame_path = frame_dir / f"{target_clip.stem}_f{t_int}.jpg"

        if not frame_path.exists() or frame_path.stat().st_size == 0:
            cmd = [
                "ffmpeg", "-y",
                "-ss", str(t_int),
                "-i", str(target_clip),
                "-vframes", "1",
                "-q:v", "2",
                str(frame_path),
            ]
            subprocess.run(cmd, capture_output=True, text=True)

        if frame_path.exists() and frame_path.stat().st_size > 0:
            return Response(content=frame_path.read_bytes(), media_type="image/jpeg")
        
        fallback_path = frame_dir / f"{target_clip.stem}_f0.jpg"
        if fallback_path.exists():
            return Response(content=fallback_path.read_bytes(), media_type="image/jpeg")

        raise HTTPException(status_code=404, detail="Frame could not be generated")
    except Exception as e:
        logger.error(f"Error extracting frame: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Mount Flutter Web Release Frontend (Serves UI directly from port 8765)
web_dir = settings.BASE_DIR / "build" / "web"
if web_dir.exists():
    if (web_dir / "assets").exists():
        app.mount("/assets", StaticFiles(directory=str(web_dir / "assets")), name="web_assets")
    if (web_dir / "canvaskit").exists():
        app.mount("/canvaskit", StaticFiles(directory=str(web_dir / "canvaskit")), name="web_canvaskit")
    if (web_dir / "icons").exists():
        app.mount("/icons", StaticFiles(directory=str(web_dir / "icons")), name="web_icons")

    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        if full_path:
            target_file = web_dir / full_path
            if target_file.is_file():
                return FileResponse(target_file)
        index_file = web_dir / "index.html"
        if index_file.exists():
            return FileResponse(index_file)
        raise HTTPException(status_code=404, detail="Not Found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="127.0.0.1", port=settings.PORT, reload=True, reload_dirs=["backend"])
