<div align="center">

<img src="https://i.imgur.com/YUERzJ7.jpeg" alt="vertical craft-clean" width="100%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.5);" />

# 🎬 VerticalCraft AI Studio

**Autonomous AI-Powered Long-Form to Viral Vertical Shorts Engine**  
*Precision OpenCV Highlight Slicing • OpenAI Whisper Kinetic Subtitles • AI Stem Isolation • NVIDIA NVENC 60 FPS Export*

[![Windows](https://img.shields.io/badge/Platform-Windows%2064--bit%20%7C%2032--bit-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#)
[![Flutter](https://img.shields.io/badge/Frontend-Flutter%20CanvasKit-02569B?style=for-the-badge&logo=flutter&logoColor=white)](#)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI%20%7C%20Python-009688?style=for-the-badge&logo=fastapi&logoColor=white)](#)
[![Whisper](https://img.shields.io/badge/Captions-OpenAI%20Whisper-412991?style=for-the-badge&logo=openai&logoColor=white)](#)
[![FFmpeg](https://img.shields.io/badge/Engine-FFmpeg%20%7C%20NVENC-007808?style=for-the-badge&logo=ffmpeg&logoColor=white)](#)

<br/>

[![Download Full Source & Models](https://img.shields.io/badge/%F0%9F%93%A6%20Download%20Full%20Source%20%26%20Models-Google%20Drive-34A853?style=for-the-badge&logo=googledrive&logoColor=white)](https://drive.google.com/drive/folders/1WiHVmZWMdRwsESQewoZgTAZqQo5vbZLu?usp=sharing)

</div>

---

## 🚀 Overview

**VerticalCraft Studio** is a high-performance desktop application engineered to transform long horizontal videos (podcasts, gaming streams, reaction videos, speeches) into publication-ready, 9:16 vertical shorts (YouTube Shorts, Instagram Reels, TikTok) in seconds.

Equipped with **OpenCV motion analysis**, **Audio RMS energy peak detection**, **OpenAI Whisper word-level kinetic subtitle styling**, **AI vocal stem separation**, and **NVIDIA NVENC GPU acceleration**, VerticalCraft handles the complete viral shorts pipeline with zero manual timeline scrubbing required.

---

## ✨ Core Features

### ⚡ 1. Smart Multi-Segment Highlight Trimmer (> 2 Minutes)
- **Automatic Viral Detection**: Scans video frames and audio spectrum to locate the highest-energy moments, punchlines, and action climaxes.
- **Multi-Part Slicing**: Effortlessly slice long 90s+ or multi-hour videos into distinct viral parts (e.g. Part 1, Part 2, Part 3) with customized start and end duration timestamps.
- **Precision In/Out Range Fine-Tuner**: Interactive scrubbing sliders allow microsecond-accurate trim adjustments.

### 🔤 2. Kinetic ASS Animated Subtitles
- **Whisper Word-Level Timestamps**: Transcribes speech with millisecond precision and automatically normalizes segment start times to prevent subtitle delay.
- **Viral Creator Presets**: Switch instantly between **MrBeast**, **Alex Hormozi**, **Iman Gadzhi**, **Neon Cyan**, and **Midnight Gold** subtitle templates.
- **Word-Pop & Glow Animations**: High-contrast black outlines, active word pop-in scaling, dynamic karaoke highlighting, and customizable words-per-line (2, 3, or 4 words).
- **Line-by-Line Subtitle Editor**: Live in-app editing of transcript text, font size, placement margins, and colors.

### 🎙️ 3. AI Vocal & Audio Stems
- **High-Fidelity Vocal Isolation**: Extract crystal-clear streamer voice tracks using **Kim Vocals 2**, **HTDemucs**, or **Fast DSP**.
- **Streamer Reaction Sync**: Match gameplay audio with dedicated webcam microphone audio tracks.
- **Smart Audio Ducking & Balancing**: Automatically balances background game audio beneath voice commentary.

### 🪟 4. Streamer Dual-Split & Vertical 9:16 Compositing
- **Adaptive 9:16 Centering**: Intelligent focal tracking that crops 16:9 widescreen footage into 9:16 vertical format.
- **Streamer Split Mode**: Stacks facecam / reaction webcam on top and gameplay on bottom with customizable split ratios (30/70, 38/62, 50/50).

### ⚡ 5. Hardware Accelerated 60 FPS Export & Master ZIP
- **NVIDIA NVENC GPU Acceleration**: Renders full 1080x1920 60 FPS vertical video in approximately **3 seconds per part**.
- **1-Click Master ZIP Archive**: Batch processes all selected segments and automatically zips them into a single downloadable package ready for upload.
- **Unicode & Drive Path Resilience**: Hardened FFmpeg filtergraph escaping prevents Windows colon path bugs and Latin-1 header encoding issues.

### 🖥️ 6. Standalone 1-Click Windows Executables
- Built-in native **64-bit (`VerticalCraft.exe`)** and **32-bit (`VerticalCraft_32bit.exe`)** launchers.
- Launches the AI engine and dedicated frameless CanvasKit desktop studio window with zero command prompt clutter.

---

## 📥 Download Source & Pre-Trained Models

Get the full complete project package, pre-trained AI models, and assets from Google Drive:

🔗 **[Download Full Source & Models (Google Drive)](https://drive.google.com/drive/folders/1WiHVmZWMdRwsESQewoZgTAZqQo5vbZLu?usp=sharing)**

---

## 🛠️ Installation & Setup

### Method 1: Instant 1-Click Run (Recommended)

1. Clone or download the repository directly into your local disk (e.g. `K:\Webapps Projects\verticalcraft`):
   ```bash
   git clone https://github.com/your-username/verticalcraft.git
   ```
2. Double-click the direct executable for your architecture:
   - **Windows 64-bit**: Double-click `VerticalCraft.exe`
   - **Windows 32-bit**: Double-click `VerticalCraft_32bit.exe`
3. The engine automatically boots the background FastAPI backend and opens the dedicated VerticalCraft Studio window!

---

### Method 2: Developer CLI Setup

#### Prerequisites
- **Python 3.10+** (64-bit recommended)
- **Flutter SDK 3.24+** (Channel stable)
- **FFmpeg** (Included via `static-ffmpeg` or system PATH)
- **NVIDIA GPU** (Optional for NVENC acceleration; libx264 CPU fallback included)

#### Step 1: Backend Setup
```bash
# Navigate to the project directory
cd verticalcraft

# Create and activate Python virtual environment
python -m venv .venv
.venv\Scripts\activate

# Install dependencies
pip install -r backend/requirements.txt
```

#### Step 2: Build Flutter CanvasKit Web Assets
```bash
# Install Flutter packages
flutter pub get

# Compile release web assets
flutter build web
```

#### Step 3: Launch
```bash
# Run the complete application
run_backend.bat
run_ui.bat
```
Open **`http://127.0.0.1:8765/`** in your browser to access the studio.

---

## 📂 Project Architecture
verticalcraft/ ├── VerticalCraft.exe # Native Windows 64-bit Direct Launcher ├── VerticalCraft_32bit.exe # Native Windows 32-bit Direct Launcher ├── launcher.cs # C# Windows Launcher Source ├── run_backend.bat # Fast CLI backend runner ├── run_ui.bat # Fast CLI UI runner ├── pubspec.yaml # Flutter project specifications │ ├── backend/ # FastAPI AI Video & Audio Engine │ ├── main.py # Core server, static SPA mounter & routers │ ├── core/ │ │ ├── config.py # Dynamic directory resolver & settings │ │ ├── hardware.py # NVIDIA NVENC / CUDA GPU detector │ │ └── resolver.py # Clip path & project file resolver │ ├── modules/ │ │ ├── caption_generator.py # Whisper transcription & ASS subtitle builder │ │ ├── exporter.py # FFmpeg compositor & NVENC hardware renderer │ │ ├── audio_mixer.py # Audio separation & stem mixing │ │ └── highlight_detector.py# OpenCV motion & audio energy analyzer │ └── routers/ # REST endpoints (import, analyze, layout, captions, export) │ ├── lib/ # Flutter Desktop UI (Dart) │ ├── main.dart # App entrypoint & GoRouter configuration │ ├── screens/ │ │ ├── home_screen.dart # Project selector & recent workspaces │ │ ├── import_screen.dart # Video file & YouTube downloader │ │ ├── highlight_picker_screen.dart # Multi-segment trimmer & viral moments │ │ ├── layout_editor_screen.dart # 9:16 centering & streamer webcam split │ │ ├── caption_editor_screen.dart # Kinetic subtitle styling & animation studio │ │ ├── audio_mixer_screen.dart # AI stem isolator & vocal volume balancing │ │ └── export_screen.dart # Single MP4 & Master ZIP Batch export hub │ ├── services/ │ │ ├── api_client.dart # REST API client │ │ └── segment_session.dart# Multi-segment state & auto-save manager │ └── widgets/ │ └── web_video_player.dart# CanvasKit GPU video player & timeline scrubber │ └── projects/ # Local storage for imports, renders, stems & ZIPs ├── imports/ # Raw uploaded video files ├── renders/ # Rendered vertical shorts (1080x1920) ├── stems/ # Isolated vocals and instruments ├── thumbnails/ # Snapshot frames & visual previews └── exports/ # Packaged 1-Click Master ZIP archives

---

## 🤝 Credits & Acknowledgements

- **[Flutter](https://flutter.dev/)** — Google's multi-platform UI toolkit.
- **[OpenAI Whisper](https://github.com/openai/whisper)** — Speech-to-text with word-level timestamps.
- **[FFmpeg](https://ffmpeg.org/)** — Cross-platform audio/video composition engine.
- **[FastAPI](https://fastapi.tiangolo.com/)** — Modern high-performance Python web framework.
- **[OpenCV](https://opencv.org/)** — Computer vision for motion detection and saliency tracking.
- **[Uvicorn](https://www.uvicorn.org/)** — ASGI server for Python.

---

<div align="center">

Made with ❤️ for Content Creators, Streamers & Video Editors.

[Back to Top ↑](#-verticalcraft-ai-studio)

</div>
