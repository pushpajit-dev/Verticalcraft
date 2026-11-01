from __future__ import annotations
import os, sys, shutil
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

try:
    import static_ffmpeg
    static_ffmpeg.add_paths()
except Exception as e:
    pass

BASE_DIR = Path(__file__).resolve().parents[2]

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BASE_DIR / ".env", extra="ignore")
    BASE_DIR: Path = BASE_DIR
    PORT: int = 8765
    PROJECTS_DIR: Path = BASE_DIR / "projects"
    TEMP_DIR: Path = BASE_DIR / ".tmp"
    MODELS_DIR: Path = BASE_DIR / "backend" / "models"
    ASSETS_DIR: Path = BASE_DIR / "assets"
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.0-flash"
    OLLAMA_HOST: str = "http://localhost:11434"
    OLLAMA_MODEL: str = "llama3.2:3b"
    OLLAMA_VISION_MODEL: str = "llava:7b"
    WHISPER_MODEL: str = "base"
    WHISPER_DEVICE: str = "cpu"
    META_APP_ID: str = ""
    META_APP_SECRET: str = ""
    X_API_KEY: str = ""
    X_API_SECRET: str = ""
    DEFAULT_VIDEO_CODEC: str = "libx264"
    DEFAULT_AUDIO_CODEC: str = "aac"
    DEFAULT_EXPORT_CRF: int = 23
    DEFAULT_FPS: int = 30

settings = Settings()
