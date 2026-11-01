from __future__ import annotations
import json, subprocess
from pathlib import Path
from typing import Any
from loguru import logger

def analyze_clip(path: Path) -> dict[str, Any]:
    probe = _ffprobe(path)
    if not probe:
        return {"error": "ffprobe failed", "path": str(path)}

    fmt = probe.get("format", {})
    streams = probe.get("streams", [])
    video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
    audio_streams = [s for s in streams if s.get("codec_type") == "audio"]

    result: dict[str, Any] = {
        "path": str(path), "filename": path.name,
        "format": fmt.get("format_name", "unknown"),
        "duration": float(fmt.get("duration", 0)),
        "size_bytes": int(fmt.get("size", 0)),
        "bit_rate": int(fmt.get("bit_rate", 0)),
    }

    if video_stream:
        width = int(video_stream.get("width", 0))
        height = int(video_stream.get("height", 0))
        fps_str = video_stream.get("r_frame_rate", "30/1")
        try:
            num, den = map(int, fps_str.split("/"))
            fps = round(num / den, 3)
        except Exception:
            fps = 30.0

        rotation = 0
        for sd in video_stream.get("side_data_list", []):
            if sd.get("side_data_type") == "Display Matrix":
                rotation = abs(int(sd.get("rotation", 0)))
        if rotation in (90, 270):
            width, height = height, width

        result["video"] = {
            "codec": video_stream.get("codec_name"),
            "width": width, "height": height, "fps": fps,
            "rotation": rotation, "aspect_ratio": _classify_aspect(width, height),
            "pixel_format": video_stream.get("pix_fmt"),
        }

    result["audio_tracks"] = [
        {"index": s.get("index"), "codec": s.get("codec_name"),
         "sample_rate": s.get("sample_rate"), "channels": s.get("channels"),
         "language": s.get("tags", {}).get("language", "und")}
        for s in audio_streams
    ]
    result["audio_track_count"] = len(audio_streams)
    return result

def _ffprobe(path: Path) -> dict | None:
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json",
           "-show_format", "-show_streams", str(path)]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return json.loads(res.stdout)
    except Exception as e:
        logger.error(f"ffprobe error on {path}: {e}")
        return None

def _classify_aspect(width: int, height: int) -> str:
    if width == 0 or height == 0: return "unknown"
    ratio = width / height
    if ratio < 0.65:  return "9:16"
    elif ratio < 1.1: return "square"
    elif ratio < 1.9: return "4:3"
    else:             return "16:9"
