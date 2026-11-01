from __future__ import annotations
import os, json, time, datetime, uuid
from pathlib import Path
from fastapi import APIRouter, HTTPException
from loguru import logger
from backend.core.config import settings

router = APIRouter()

PROJECTS_STORE_DIR = settings.PROJECTS_DIR / "saved_projects"
PROJECTS_STORE_DIR.mkdir(parents=True, exist_ok=True)

DRAFT_FILE = PROJECTS_STORE_DIR / "_auto_draft.json"

@router.get("")
@router.get("/")
async def list_projects():
    projects = []
    draft = None

    if DRAFT_FILE.exists():
        try:
            draft = json.loads(DRAFT_FILE.read_text(encoding="utf-8"))
        except Exception as e:
            logger.warning(f"Error reading draft: {e}")

    for p_file in sorted(PROJECTS_STORE_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        if p_file.name == "_auto_draft.json":
            continue
        try:
            p_data = json.loads(p_file.read_text(encoding="utf-8"))
            projects.append({
                "project_id": p_data.get("project_id", p_file.stem),
                "project_name": p_data.get("project_name", "Untitled Project"),
                "clip_id": p_data.get("clip_id", ""),
                "face_clip_id": p_data.get("face_clip_id"),
                "clip_name": p_data.get("clip_name", "Primary Video"),
                "segments_count": len(p_data.get("segments", [])),
                "layout_mode": p_data.get("layout_mode", "normal"),
                "preset": p_data.get("preset", "mrbeast"),
                "updated_at": p_data.get("updated_at", datetime.datetime.fromtimestamp(p_file.stat().st_mtime).strftime("%b %d, %Y %I:%M %p")),
            })
        except Exception as e:
            logger.warning(f"Skipping corrupted project file {p_file.name}: {e}")

    return {
        "status": "success",
        "projects": projects,
        "draft": draft,
    }

@router.post("/save")
async def save_project(data: dict):
    now_str = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    project_id = data.get("project_id") or str(uuid.uuid4())[:8]
    project_name = data.get("project_name") or f"Project_{now_str}"
    
    project_payload = {
        "project_id": project_id,
        "project_name": project_name,
        "clip_id": data.get("clip_id", ""),
        "face_clip_id": data.get("face_clip_id"),
        "clip_name": data.get("clip_name", "Primary Video"),
        "segments": data.get("segments", []),
        "selected_indices": data.get("selected_indices", [0]),
        "active_segment_index": data.get("active_segment_index", 0),
        "layout_mode": data.get("layout_mode", "normal"),
        "face_ratio": data.get("face_ratio", 0.38),
        "font": data.get("font", "Montserrat"),
        "font_size": data.get("font_size", 24.0),
        "animation": data.get("animation", "popup-blur"),
        "preset": data.get("preset", "mrbeast"),
        "language": data.get("language", "auto"),
        "text_color_hex": data.get("text_color_hex", "#FFFFFF"),
        "highlight_color_hex": data.get("highlight_color_hex", "#FFD700"),
        "badge_color_hex": data.get("badge_color_hex", "#000000"),
        "pos_y": data.get("pos_y", 0.72),
        "stem_model": data.get("stem_model", "kim_vocals_2"),
        "segment_captions": data.get("segment_captions", {}),
        "updated_at": datetime.datetime.now().strftime("%b %d, %Y %I:%M %p"),
    }

    target_file = PROJECTS_STORE_DIR / f"{project_id}.json"
    target_file.write_text(json.dumps(project_payload, indent=2), encoding="utf-8")
    logger.info(f"Saved project {project_name} ({project_id}) to {target_file}")

    return {
        "status": "success",
        "message": f"Project '{project_name}' saved successfully!",
        "project_id": project_id,
        "project": project_payload,
    }

@router.post("/auto-save")
async def auto_save_draft(data: dict):
    data["updated_at"] = datetime.datetime.now().strftime("%b %d, %Y %I:%M %p")
    DRAFT_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return {"status": "success", "message": "Draft auto-saved."}

@router.get("/{project_id}")
async def get_project(project_id: str):
    if project_id == "draft":
        if not DRAFT_FILE.exists():
            raise HTTPException(status_code=404, detail="No active draft found.")
        return json.loads(DRAFT_FILE.read_text(encoding="utf-8"))

    target_file = PROJECTS_STORE_DIR / f"{project_id}.json"
    if not target_file.exists():
        raise HTTPException(status_code=404, detail=f"Project {project_id} not found.")

    return json.loads(target_file.read_text(encoding="utf-8"))

@router.delete("/{project_id}")
async def delete_project(project_id: str):
    if project_id == "draft":
        if DRAFT_FILE.exists():
            os.remove(DRAFT_FILE)
        return {"status": "success", "message": "Draft deleted."}

    target_file = PROJECTS_STORE_DIR / f"{project_id}.json"
    if target_file.exists():
        os.remove(target_file)
        return {"status": "success", "message": "Project deleted successfully."}
    
    raise HTTPException(status_code=404, detail="Project not found.")
