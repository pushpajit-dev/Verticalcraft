<div align="center">

<img src="https://i.imgur.com/jdPmzcP.jpeg" alt="vertical craft-clean" width="100%" />

# 🎬 VerticalCraft AI Studio

**Autonomous AI-Powered Long-Form to Viral Vertical Shorts Engine**  
*OpenCV Motion Detection • OpenAI Whisper Kinetic Captions • AI Vocal Stem Isolation • NVIDIA NVENC 60 FPS Export*

[![Windows](https://img.shields.io/badge/Platform-Windows%2064--bit%20%7C%2032--bit-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#)
[![Flutter](https://img.shields.io/badge/Frontend-Flutter%20CanvasKit-02569B?style=for-the-badge&logo=flutter&logoColor=white)](#)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI%20%7C%20Python-009688?style=for-the-badge&logo=fastapi&logoColor=white)](#)
[![Whisper](https://img.shields.io/badge/Captions-OpenAI%20Whisper-412991?style=for-the-badge&logo=openai&logoColor=white)](#)
[![FFmpeg](https://img.shields.io/badge/Engine-FFmpeg%20%7C%20NVENC-007808?style=for-the-badge&logo=ffmpeg&logoColor=white)](#)

<br/>

[![Download Full Source & Models](https://img.shields.io/badge/%F0%9F%93%A6%20Download%20Full%20Source%20%26%20Models-Google%20Drive-34A853?style=for-the-badge&logo=googledrive&logoColor=white)](https://drive.google.com/drive/folders/1WiHVmZWMdRwsESQewoZgTAZqQo5vbZLu?usp=sharing)

</div>

---

## ⚡ Quick Start (1-Click Run)

If you downloaded the pre-built release package:

```cmd
:: For 64-bit Windows:
VerticalCraft.exe

:: For 32-bit Windows:
VerticalCraft_32bit.exe
```

---

## 🛠️ Complete GitHub Setup & Installation Commands

Follow these terminal commands step-by-step to clone, set up, and run VerticalCraft:

### Step 1: Clone Repository

```bash
git clone https://github.com/your-username/verticalcraft.git
cd verticalcraft
```

### Step 2: Set Up Python Backend Environment

```powershell
# Create Python virtual environment
python -m venv .venv

# Activate virtual environment (Windows PowerShell)
.\.venv\Scripts\Activate.ps1

# Or in Windows Command Prompt (cmd.exe):
# .venv\Scripts\activate.bat

# Upgrade pip and install all required AI dependencies
python -m pip install --upgrade pip
pip install fastapi uvicorn[standard] openai-whisper torch torchvision torchaudio opencv-python static-ffmpeg loguru pydantic-settings python-multipart httpx
```

### Step 3: Install Flutter Dependencies & Compile Web UI

```bash
# Get Flutter packages
flutter pub get

# Enable Windows desktop and web support
flutter config --enable-windows-desktop
flutter config --enable-web

# Build production CanvasKit web release
flutter build web
```

### Step 4: Compile Native Windows Executables (.exe)

```powershell
# Compile 64-bit Windows GUI Launcher
& "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x64 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft.exe" "launcher.cs"

# Compile 32-bit Windows GUI Launcher
& "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x86 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft_32bit.exe" "launcher.cs"
```

### Step 5: Run VerticalCraft

```cmd
:: Option A: Direct 1-Click Launch (Recommended)
VerticalCraft.exe

:: Option B: CLI Batch Scripts
run_backend.bat
run_ui.bat
```

Open **`http://127.0.0.1:8765/`** in any browser or let the native app window open automatically.

---

## 📤 Push Changes to Your GitHub Repository

```bash
git init
git add .
git commit -m "feat: complete VerticalCraft studio with kinetic subtitles, multi-trim & standalone executables"
git branch -M main
git remote add origin https://github.com/your-username/verticalcraft.git
git push -u origin main
```

---

## ✨ Features

- **Multi-Segment Trimming (> 2 Minutes)**: Automatically split 90s+ or multi-hour videos into viral parts with normalized start/end timestamps.
- **OpenCV Motion & Audio Peak Detection**: Discovers viral highlights using frame-difference motion tracking and RMS audio energy peaks.
- **OpenAI Whisper Kinetic Subtitles**: Millisecond word timestamps with pop-in, zoom-blur, karaoke, and stroke animations.
- **Viral Styling Presets**: MrBeast, Alex Hormozi, Iman Gadzhi, Neon Cyan, and Midnight Gold.
- **Streamer Dual-Split Layout**: Top webcam, bottom gameplay with customizable split ratios.
- **AI Vocal Stem Isolation**: Kim Vocals 2, HTDemucs, and Fast DSP voice separation.
- **Hardware Accelerated NVENC 60 FPS Export**: 3 seconds per vertical short.
- **1-Click Master ZIP Export**: Packages all rendered 1080x1920 MP4s into a single downloadable ZIP archive.

---

## 📂 Project Structure

```
verticalcraft/
├── VerticalCraft.exe           # Native Windows 64-bit Direct Executable
├── VerticalCraft_32bit.exe     # Native Windows 32-bit Direct Executable
├── launcher.cs                 # C# Windows Launcher Source Code
├── run_backend.bat             # Backend launch script
├── run_ui.bat                  # UI launch script
├── pubspec.yaml                # Flutter dependencies
│
├── backend/                    # FastAPI AI Video Engine
│   ├── main.py                 # Core server, static SPA mounter & routers
│   ├── core/
│   │   ├── config.py           # Path configuration & settings
│   │   ├── hardware.py         # NVIDIA GPU / NVENC hardware detector
│   │   └── resolver.py         # Media path resolver
│   ├── modules/
│   │   ├── caption_generator.py # Whisper transcription & normalized ASS subtitles
│   │   ├── exporter.py          # FFmpeg compositor & NVENC hardware renderer
│   │   ├── audio_mixer.py       # Audio separation & stem mixing
│   │   └── highlight_detector.py# OpenCV visual & audio energy analyzer
│   └── routers/                # REST API routers (import, captions, layout, export)
│
├── lib/                        # Flutter Frontend (Dart)
│   ├── main.dart               # Routing & theme
│   ├── screens/                # UI screens (trimmer, layout, captions, audio, export)
│   ├── services/               # API client & session state
│   └── widgets/                # CanvasKit video player & timeline controls
│
└── projects/                   # Storage directory
    ├── imports/                # Uploaded videos
    ├── renders/                # Exported 1080x1920 MP4s
    ├── stems/                  # Isolated vocals and instruments
    └── exports/                # Generated 1-Click ZIP archives
```

---

## 🤝 Credits & Acknowledgements

- **[Flutter](https://flutter.dev/)** — Google's multi-platform UI toolkit.
- **[OpenAI Whisper](https://github.com/openai/whisper)** — Speech-to-text with word-level timestamps.
- **[FFmpeg](https://ffmpeg.org/)** — Complete cross-platform audio/video composition engine.
- **[FastAPI](https://fastapi.tiangolo.com/)** — Modern high-performance Python web framework.
- **[OpenCV](https://opencv.org/)** — Computer vision for motion detection and saliency tracking.
- **[Uvicorn](https://www.uvicorn.org/)** — Lightning-fast ASGI server for Python.

---

<div align="center">

Made with ❤️ for Content Creators, Streamers & Video Editors.

[Back to Top ↑](#-verticalcraft-ai-studio)

</div>
