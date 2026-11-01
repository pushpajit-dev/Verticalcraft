from __future__ import annotations
import subprocess
from dataclasses import dataclass
from pathlib import Path
from loguru import logger

RATIO_DIMENSIONS = {
    "9:16": (1080, 1920),
    "1:1": (1080, 1080),
    "4:3": (1440, 1080),
    "16:9": (1920, 1080),
}

@dataclass
class StreamerLayoutConfig:
    face_clip_path: str
    gameplay_clip_path: str
    aspect_ratio: str = "9:16"
    face_ratio: float = 0.38
    output_path: str = ""
    start_time: float = 0.0
    duration: float = 60.0
    logo_path: str = ""
    logo_opacity: float = 0.8
    logo_position: str = "top-right"

@dataclass
class NormalLayoutConfig:
    clip_path: str
    aspect_ratio: str = "9:16"
    output_path: str = ""
    zoom_scale: float = 1.0
    pan_x: float = 0.0
    pan_y: float = 0.0
    crop_mode: str = "smart"
    start_time: float = 0.0
    duration: float = 60.0
    logo_path: str = ""
    logo_opacity: float = 0.8
    logo_position: str = "top-right"

def build_streamer_layout(config: StreamerLayoutConfig) -> str:
    out_w, out_h = RATIO_DIMENSIONS.get(config.aspect_ratio, (1080, 1920))
    face_height = int(out_h * config.face_ratio)
    gameplay_height = out_h - face_height
    output = config.output_path or str(Path(config.face_clip_path).parent / "streamer_output.mp4")

    filter_complex = (
        f"[0:v]scale={out_w}:{face_height}:force_original_aspect_ratio=increase,"
        f"crop={out_w}:{face_height}[face];"
        f"[1:v]scale={out_w}:{gameplay_height}:force_original_aspect_ratio=increase,"
        f"crop={out_w}:{gameplay_height}[game];"
        f"[face][game]vstack=inputs=2[stacked]"
    )
    
    inputs = [
        "-ss", str(config.start_time), "-i", config.face_clip_path,
        "-ss", str(config.start_time), "-i", config.gameplay_clip_path,
    ]
    last_v = "[stacked]"

    if config.logo_path and Path(config.logo_path).exists():
        inputs += ["-i", config.logo_path]
        logo_idx = 2
        logo_pos = _get_logo_overlay_pos(config.logo_position)
        filter_complex += f";[{logo_idx}:v]format=rgba,colorchannelmixer=aa={config.logo_opacity},scale=180:-1[logo];{last_v}[logo]overlay={logo_pos}[out]"
        last_v = "[out]"
    else:
        filter_complex += f";{last_v}copy[out]"

    cmd = [
        "ffmpeg", "-y",
        *inputs,
        "-filter_complex", filter_complex,
        "-map", "[out]", "-map", "1:a?",
        "-t", str(config.duration),
        "-c:v", "libx264", "-crf", "21", "-preset", "fast",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        output,
    ]
    logger.info(f"Building streamer layout ({config.aspect_ratio}) -> {output}")
    subprocess.run(cmd, check=True, capture_output=True)
    return output

def build_normal_layout(config: NormalLayoutConfig) -> str:
    out_w, out_h = RATIO_DIMENSIONS.get(config.aspect_ratio, (1080, 1920))
    output = config.output_path or str(Path(config.clip_path).parent / "normal_output.mp4")
    
    scale_w = int(out_w * max(1.0, config.zoom_scale))
    scale_h = int(out_h * max(1.0, config.zoom_scale))
    
    crop_x_expr = f"(iw-{out_w})/2 + ({config.pan_x}*(iw-{out_w})/2)"
    crop_y_expr = f"(ih-{out_h})/2 + ({config.pan_y}*(ih-{out_h})/2)"
    
    filter_complex = (
        f"[0:v]scale={scale_w}:{scale_h}:force_original_aspect_ratio=increase,"
        f"crop={out_w}:{out_h}:{crop_x_expr}:{crop_y_expr}[cropped]"
    )
    
    inputs = ["-ss", str(config.start_time), "-i", config.clip_path]
    last_v = "[cropped]"

    if config.logo_path and Path(config.logo_path).exists():
        inputs += ["-i", config.logo_path]
        logo_pos = _get_logo_overlay_pos(config.logo_position)
        filter_complex += f";[1:v]format=rgba,colorchannelmixer=aa={config.logo_opacity},scale=180:-1[logo];{last_v}[logo]overlay={logo_pos}[out]"
        last_v = "[out]"
    else:
        filter_complex += f";{last_v}copy[out]"

    cmd = [
        "ffmpeg", "-y",
        *inputs,
        "-filter_complex", filter_complex,
        "-map", "[out]", "-map", "0:a?",
        "-t", str(config.duration),
        "-c:v", "libx264", "-crf", "21", "-preset", "fast",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        output,
    ]
    logger.info(f"Building normal layout ({config.aspect_ratio}) -> {output}")
    subprocess.run(cmd, check=True, capture_output=True)
    return output

def _get_logo_overlay_pos(pos: str) -> str:
    if pos == "top-left": return "40:80"
    elif pos == "bottom-left": return "40:main_h-overlay_h-180"
    elif pos == "bottom-right": return "main_w-overlay_w-40:main_h-overlay_h-180"
    else: return "main_w-overlay_w-40:80"

def generate_vertical_composite(clip_path: str, output_path: str = "", aspect_ratio: str = "9:16") -> str:
    return build_normal_layout(NormalLayoutConfig(clip_path=clip_path, output_path=output_path, aspect_ratio=aspect_ratio))

