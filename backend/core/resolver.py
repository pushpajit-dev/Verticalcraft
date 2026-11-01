from __future__ import annotations
import glob
from pathlib import Path
from typing import Optional
from backend.core.config import settings

def resolve_clip_path(clip_id: Optional[str] = None, clip_path: Optional[str] = None) -> Path:
    """
    Finds the actual video file on disk using clip_path or clip_id.
    """
    if clip_path:
        p = Path(clip_path)
        if p.exists() and p.is_file():
            return p

    if clip_id:
        # Check imports directory
        import_dir = settings.PROJECTS_DIR / "imports" / clip_id
        if import_dir.exists():
            for ext in [".mp4", ".mov", ".mkv", ".webm", ".avi", ".ts"]:
                candidates = list(import_dir.glob(f"*{ext}"))
                if candidates:
                    return candidates[0]
            # Any file
            files = [f for f in import_dir.iterdir() if f.is_file()]
            if files:
                return files[0]

        # Scan any subfolder with that clip_id
        search = list(settings.PROJECTS_DIR.glob(f"**/*{clip_id}*"))
        for item in search:
            if item.is_file() and item.suffix.lower() in [".mp4", ".mov", ".mkv", ".webm"]:
                return item

    # Global fallback: find most recent video in projects/imports
    all_imports = sorted(
        (settings.PROJECTS_DIR / "imports").glob("**/*.mp4"),
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    if all_imports:
        return all_imports[0]

    raise FileNotFoundError(f"Could not resolve video file for clip_id={clip_id}, path={clip_path}")
