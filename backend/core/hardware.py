from __future__ import annotations
import os, subprocess, platform, json
from typing import Any
from loguru import logger

_cached_hardware_info: dict[str, Any] | None = None

def detect_system_hardware() -> dict[str, Any]:
    global _cached_hardware_info
    if _cached_hardware_info is not None:
        return _cached_hardware_info

    info = {
        "os": platform.platform(),
        "cpu_name": "Intel/AMD Processor",
        "cpu_cores": os.cpu_count() or 4,
        "gpu_name": None,
        "gpu_vendor": "CPU", # 'NVIDIA', 'Intel', 'AMD', 'CPU'
        "has_nvidia": False,
        "has_intel": False,
        "has_amd": False,
        "vram_gb": 0.0,
        "recommended_video_codec": "libx264",
        "recommended_whisper_device": "cpu",
        "recommended_whisper_compute_type": "int8",
        "nvenc_available": False,
        "qsv_available": False,
        "acceleration_label": "CPU Multi-Core Acceleration",
    }

    # 1. Check NVIDIA via nvidia-smi
    try:
        res = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            lines = res.stdout.strip().split("\n")
            if lines:
                parts = lines[0].split(",")
                gpu_name = parts[0].strip()
                vram_mb = float(parts[1].strip()) if len(parts) > 1 else 0.0
                info["gpu_name"] = gpu_name
                info["gpu_vendor"] = "NVIDIA"
                info["has_nvidia"] = True
                info["vram_gb"] = round(vram_mb / 1024.0, 1)
                info["recommended_whisper_device"] = "cuda"
                info["recommended_whisper_compute_type"] = "float16"
                info["acceleration_label"] = f"⚡ NVIDIA {gpu_name} (NVENC & CUDA 12GB Accelerated)"
    except Exception:
        pass

    # 2. Check Windows WMIC/CIM for CPU & GPU
    try:
        cmd_cpu = ["powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_Processor).Name"]
        p_cpu = subprocess.run(cmd_cpu, capture_output=True, text=True)
        if p_cpu.returncode == 0 and p_cpu.stdout.strip():
            cpu_str = p_cpu.stdout.strip().split("\n")[0].strip()
            info["cpu_name"] = cpu_str
            if "intel" in cpu_str.lower():
                info["has_intel"] = True
    except Exception:
        pass

    # 3. Check FFmpeg Hardware Encoders
    try:
        enc_res = subprocess.run(["ffmpeg", "-encoders"], capture_output=True, text=True)
        out = enc_res.stdout
        if "h264_nvenc" in out and info["has_nvidia"]:
            info["nvenc_available"] = True
            info["recommended_video_codec"] = "h264_nvenc"
        elif "h264_qsv" in out and info["has_intel"]:
            info["qsv_available"] = True
            info["recommended_video_codec"] = "h264_qsv"
    except Exception:
        pass

    # Fallback to libx264 if hardware encoder not tested
    if not info["nvenc_available"]:
        info["recommended_video_codec"] = "libx264"

    _cached_hardware_info = info
    logger.info(f"Detected System Hardware: {info['gpu_name'] or info['cpu_name']} | Codec: {info['recommended_video_codec']} | Label: {info['acceleration_label']}")
    return info
