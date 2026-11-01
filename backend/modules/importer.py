from __future__ import annotations
import asyncio, shutil, glob, os
from pathlib import Path
from typing import Optional
import yt_dlp
from loguru import logger

SUPPORTED_VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v", ".ts"}
SUPPORTED_AUDIO_EXTS = {".mp3", ".wav", ".aac", ".flac", ".ogg", ".m4a"}
SUPPORTED_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}

def get_ffmpeg_dir() -> Optional[str]:
    ff = shutil.which("ffmpeg")
    if ff:
        return str(Path(ff).parent)
    try:
        import static_ffmpeg
        static_ffmpeg.add_paths()
        ff = shutil.which("ffmpeg")
        if ff:
            return str(Path(ff).parent)
    except Exception:
        pass
    candidates = glob.glob(r"C:\Users\pushp\AppData\Local\Microsoft\WinGet\Packages\**\ffmpeg.exe", recursive=True)
    if candidates:
        return str(Path(candidates[0]).parent)
    return None

def validate_media_file(path: Path) -> bool:
    return path.suffix.lower() in (SUPPORTED_VIDEO_EXTS | SUPPORTED_AUDIO_EXTS | SUPPORTED_IMAGE_EXTS)

async def download_from_url(
    url: str, output_dir: Path, quality: str = "best", output_format: str = "mp4"
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    ff_dir = get_ffmpeg_dir()

    # Formats designed to always succeed regardless of platform codec availability
    format_candidates = [
        "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/bestvideo+bestaudio/best",
        "bestvideo+bestaudio/best",
        "best",
    ]

    last_err = None
    for fmt in format_candidates:
        try:
            downloaded_path = await _attempt_download(url, output_dir, fmt, output_format, ff_dir)
            if downloaded_path and downloaded_path.exists():
                return downloaded_path
        except Exception as e:
            last_err = e
            logger.warning(f"yt-dlp format {fmt} failed: {e}, trying next fallback...")

    # Final check: see if any media was downloaded into directory
    files = sorted(output_dir.iterdir(), key=lambda f: f.stat().st_mtime, reverse=True)
    media_files = [f for f in files if f.suffix.lower() in SUPPORTED_VIDEO_EXTS]
    if media_files:
        return media_files[0]

    raise RuntimeError(f"Could not download video from URL: {last_err or 'Unknown download error'}")

async def _attempt_download(url: str, output_dir: Path, fmt: str, output_format: str, ff_dir: Optional[str]) -> Path:
    downloaded_path: Optional[Path] = None

    def progress_hook(d):
        nonlocal downloaded_path
        if d.get("status") == "finished":
            downloaded_path = Path(d.get("filename", ""))

    ydl_opts = {
        "format": fmt,
        "outtmpl": str(output_dir / "%(title).90s_%(id)s.%(ext)s"),
        "merge_output_format": output_format,
        "noplaylist": True,
        "windowsfilenames": True,
        "nocheckcertificate": True,
        "ignoreerrors": False,
        "quiet": True,
        "no_warnings": True,
        "progress_hooks": [progress_hook],
    }

    if ff_dir:
        ydl_opts["ffmpeg_location"] = ff_dir

    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _run_ytdlp, ydl_opts, url)

    if downloaded_path and downloaded_path.exists() and downloaded_path.is_file():
        return downloaded_path

    files = sorted(output_dir.iterdir(), key=lambda f: f.stat().st_mtime, reverse=True)
    media_files = [f for f in files if f.suffix.lower() in SUPPORTED_VIDEO_EXTS]
    if media_files:
        return media_files[0]

    raise FileNotFoundError(f"No file produced for {url}")

def _run_ytdlp(opts: dict, url: str) -> None:
    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])
