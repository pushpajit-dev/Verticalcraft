from __future__ import annotations
import asyncio, subprocess, os
from pathlib import Path
from loguru import logger
from backend.core.config import settings
from backend.core.hardware import detect_system_hardware

def _build_color_filter(
    brightness: float = 0.0,
    contrast: float = 1.0,
    saturation: float = 1.0,
    preset: str = "none",
) -> str:
    if preset == "cinematic":
        return "eq=contrast=1.2:saturation=1.15:brightness=-0.02,colorbalance=rs=0.06:bs=-0.06"
    elif preset == "vibrant":
        return "eq=contrast=1.18:saturation=1.45:brightness=0.04"
    elif preset == "cyberpunk":
        return "colorbalance=rs=0.15:gs=-0.08:bs=0.22,eq=contrast=1.25:saturation=1.3"
    elif preset == "noir":
        return "hue=s=0,eq=contrast=1.35:brightness=-0.03"
    elif preset == "vintage":
        return "colorbalance=rs=0.12:gs=0.04:bs=-0.14,eq=contrast=0.95:saturation=0.85"
    
    eq_parts = []
    if brightness != 0.0:
        eq_parts.append(f"brightness={brightness:.2f}")
    if contrast != 1.0:
        eq_parts.append(f"contrast={contrast:.2f}")
    if saturation != 1.0:
        eq_parts.append(f"saturation={saturation:.2f}")
    
    return f"eq={':'.join(eq_parts)}" if eq_parts else ""

async def export_video(
    input_path: Path,
    output_path: Path,
    subtitle_path: Path | None = None,
    audio_path: Path | None = None,
    face_clip_path: Path | None = None,
    layout_mode: str = "normal",
    face_ratio: float = 0.38,
    zoom_scale: float = 1.0,
    pan_x: float = 0.0,
    pan_y: float = 0.0,
    crf: int = 20,
    fps: int = 60,
    brightness: float = 0.0,
    contrast: float = 1.0,
    saturation: float = 1.0,
    color_preset: str = "none",
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    hw = detect_system_hardware()
    # If NVIDIA GPU is available, use NVENC hardware encoder for fast export
    codec = "h264_nvenc" if hw.get("nvenc_available") else "libx264"
    preset_arg = ["-preset", "p4"] if codec == "h264_nvenc" else ["-preset", "fast"]
    
    # 1. Video Filters & Layout Compositing
    vf_filters = []
    
    # Handle ASS subtitle path safely on Windows
    working_dir = input_path.parent
    sub_arg = ""
    if subtitle_path and Path(subtitle_path).exists():
        sub_p = Path(subtitle_path).resolve()
        sub_str = str(sub_p).replace("\\", "/").replace(":", r"\:")
        sub_arg = f"ass=filename='{sub_str}'"

    # Validate audio path
    valid_audio_path = None
    if audio_path and Path(audio_path).exists() and Path(audio_path).stat().st_size > 100:
        valid_audio_path = Path(audio_path).resolve()

    if layout_mode == "streamer" and face_clip_path and Path(face_clip_path).exists():
        # Ensure dimensions are strictly even (divisible by 2) for H.264 codecs
        face_h = (int(1920 * face_ratio) // 2) * 2
        game_h = 1920 - face_h
        
        sub_filter = f",{sub_arg}" if sub_arg else ""
        color_filter = _build_color_filter(brightness, contrast, saturation, color_preset)
        color_str = f",{color_filter}" if color_filter else ""

        filter_complex = (
            f"[0:v]scale=1080:{face_h}:force_original_aspect_ratio=increase,crop=1080:{face_h}[face];"
            f"[1:v]scale=1080:{game_h}:force_original_aspect_ratio=increase,crop=1080:{game_h}[game];"
            f"[face][game]vstack=inputs=2{color_str}{sub_filter}[out]"
        )

        inputs = [
            "-i", str(face_clip_path.resolve()),
            "-i", str(input_path.resolve()),
        ]
        audio_map = "1:a?"
        if valid_audio_path:
            inputs += ["-i", str(valid_audio_path)]
            audio_map = "2:a"

        cmd = [
            "ffmpeg", "-y",
            *inputs,
            "-filter_complex", filter_complex,
            "-map", "[out]",
            "-map", audio_map,
            "-r", str(fps),
            "-c:v", codec,
            "-crf", str(crf) if codec == "libx264" else "20",
            *preset_arg,
            "-c:a", settings.DEFAULT_AUDIO_CODEC,
            "-b:a", "192k",
            "-movflags", "+faststart",
            str(output_path.resolve()),
        ]
        
        cmd_fallback = [
            "ffmpeg", "-y",
            *inputs,
            "-filter_complex", filter_complex,
            "-map", "[out]",
            "-map", audio_map,
            "-r", str(fps),
            "-c:v", "libx264",
            "-crf", str(crf),
            "-preset", "fast",
            "-c:a", settings.DEFAULT_AUDIO_CODEC,
            "-b:a", "192k",
            "-movflags", "+faststart",
            str(output_path.resolve()),
        ]
    else:
        scale_w = int(1080 * max(1.0, zoom_scale))
        scale_h = int(1920 * max(1.0, zoom_scale))
        # Ensure even dimensions
        scale_w = (scale_w // 2) * 2
        scale_h = (scale_h // 2) * 2
        
        vf_filters.append(f"scale={scale_w}:{scale_h}:force_original_aspect_ratio=increase")
        vf_filters.append("crop=1080:1920:(in_w-1080)/2:(in_h-1920)/2")
        
        color_filter = _build_color_filter(brightness, contrast, saturation, color_preset)
        if color_filter:
            vf_filters.append(color_filter)

        if sub_arg:
            vf_filters.append(sub_arg)

        video_filter = ",".join(vf_filters)
        inputs = ["-i", str(input_path.resolve())]
        audio_map = "0:a?"

        if valid_audio_path:
            inputs += ["-i", str(valid_audio_path)]
            audio_map = "1:a"

        cmd = [
            "ffmpeg", "-y",
            *inputs,
            "-vf", video_filter,
            "-map", "0:v",
            "-map", audio_map,
            "-r", str(fps),
            "-c:v", codec,
            "-crf", str(crf) if codec == "libx264" else "20",
            *preset_arg,
            "-c:a", settings.DEFAULT_AUDIO_CODEC,
            "-b:a", "192k",
            "-movflags", "+faststart",
            str(output_path.resolve()),
        ]
        
        cmd_fallback = [
            "ffmpeg", "-y",
            *inputs,
            "-vf", video_filter,
            "-map", "0:v",
            "-map", audio_map,
            "-r", str(fps),
            "-c:v", "libx264",
            "-crf", str(crf),
            "-preset", "fast",
            "-c:a", settings.DEFAULT_AUDIO_CODEC,
            "-b:a", "192k",
            "-movflags", "+faststart",
            str(output_path.resolve()),
        ]

    logger.info(f"Rendering short with {codec} to {output_path.name}")
    proc = await asyncio.to_thread(subprocess.run, cmd, capture_output=True, text=True, cwd=str(working_dir.resolve()))
    if proc.returncode != 0:
        logger.warning(f"Hardware render notice ({codec}): {proc.stderr[-300:] if proc.stderr else 'unknown'}. Retrying with CPU libx264...")
        fb_proc = await asyncio.to_thread(subprocess.run, cmd_fallback, capture_output=True, text=True, cwd=str(working_dir.resolve()))
        if fb_proc.returncode != 0:
            logger.error(f"CPU fallback render failed: {fb_proc.stderr[-300:] if fb_proc.stderr else 'unknown'}")

    return output_path
