from __future__ import annotations
import asyncio, subprocess, os, uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from loguru import logger
from backend.core.config import settings

@dataclass
class CaptionWord:
    text: str
    start: float
    end: float
    confidence: float = 1.0

@dataclass
class CaptionLine:
    words: list[CaptionWord]
    start: float
    end: float
    language: str = "auto"
    dual_script_text: Optional[str] = None

    @property
    def text(self) -> str:
        return " ".join(w.text for w in self.words)

@dataclass
class CaptionConfig:
    mode: str = "medium"
    language: str = "auto" # 'auto', 'bn', 'hi', 'ta', 'en'
    animation: str = "popup" # 'popup', 'popup-blur', 'zoom-blur', 'karaoke', 'fade', 'stroke'
    style_glow: bool = False
    style_shadow: bool = True
    style_stroke: bool = True
    style_badge: bool = False
    style_bg_color: str = "#000000"
    style_bg_opacity: float = 0.8
    text_color: str = "#FFFFFF"
    highlight_color: str = "#FFD700"
    font_family: str = "Montserrat"
    font_size: int = 24
    placement: str = "lower-third"
    placement_y: float = 0.72
    placement_x: float = 0.0
    audio_source: str = "reel" # 'reel', 'webcam', 'mixed'

WORDS_PER_LINE = {"short": 2, "medium": 3, "normal": 4}

def _hex_to_ass_color(hex_color: str) -> str:
    """
    Converts #RRGGBB to ASS BGR format &H00BBGGRR&
    """
    hex_color = hex_color.lstrip("#")
    if len(hex_color) == 6:
        r, g, b = hex_color[0:2], hex_color[2:4], hex_color[4:6]
    else:
        r, g, b = "FF", "FF", "FF"
    return f"&H00{b.upper()}{g.upper()}{r.upper()}&"

async def generate_captions(
    clip_path: Path,
    config: CaptionConfig,
    output_ass_path: Optional[Path] = None,
    audio_source_path: Optional[Path] = None,
    custom_lines: Optional[list[dict]] = None,
    start_time_sec: float = 0.0,
    duration_sec: Optional[float] = None,
) -> list[CaptionLine]:
    if custom_lines and len(custom_lines) > 0:
        logger.info(f"Using {len(custom_lines)} user-customized/edited subtitle lines for {clip_path.name}")
        lines = []
        # Check if timestamps in custom_lines are relative to the full uncut video
        min_start = min((float(l.get("start", 0.0)) for l in custom_lines if l.get("text", "").strip()), default=0.0)
        should_shift = (start_time_sec > 0.0 and min_start >= (start_time_sec - 1.0))

        for line_data in custom_lines:
            raw_text = line_data.get("text", "").strip()
            if not raw_text:
                continue
            raw_start_t = float(line_data.get("start", 0.0))
            raw_end_t = float(line_data.get("end", raw_start_t + 2.0))
            
            if should_shift:
                start_t = max(0.0, raw_start_t - start_time_sec)
                end_t = max(start_t + 0.3, raw_end_t - start_time_sec)
            else:
                start_t = max(0.0, raw_start_t)
                end_t = max(start_t + 0.3, raw_end_t)

            raw_words = raw_text.split()
            word_dur = (end_t - start_t) / max(1, len(raw_words))
            words_objs = [
                CaptionWord(text=w, start=start_t + (w_i * word_dur), end=start_t + ((w_i + 1) * word_dur))
                for w_i, w in enumerate(raw_words)
            ]
            lines.append(CaptionLine(
                words=words_objs,
                start=start_t,
                end=end_t,
                language=config.language,
            ))
    else:
        target_audio_clip = audio_source_path if (audio_source_path and audio_source_path.exists()) else clip_path
        # If target_audio_clip is an already-sliced segment (e.g. slice_part_1.mp4, temp_slice_xxx.mp4),
        # its audio starts at 0.0s, so stt_start should be 0.0!
        is_already_sliced = ("slice_" in target_audio_clip.name or "temp_slice" in target_audio_clip.name or "temp_face" in target_audio_clip.name)
        stt_start = 0.0 if is_already_sliced else start_time_sec
        stt_dur = None if is_already_sliced else duration_sec

        logger.info(f"Transcribing audio from: {target_audio_clip.name} (Language: {config.language}, stt_start={stt_start}, stt_dur={stt_dur})")
        
        words = await _transcribe_words(target_audio_clip, config.language, start_time_sec=stt_start, duration_sec=stt_dur)
        if not words:
            logger.info(f"Using viral caption template for {clip_path.name}")
            words = _get_default_viral_words(config.language)

        lines = _group_into_lines(words, WORDS_PER_LINE.get(config.mode, 3), config.language)
        logger.info(f"Generated {len(lines)} caption lines from {clip_path.name}")

    if output_ass_path:
        _write_ass_file(lines, config, output_ass_path)

    return lines

async def _transcribe_words(
    clip_path: Path,
    language: str,
    start_time_sec: float = 0.0,
    duration_sec: Optional[float] = None,
) -> list[CaptionWord]:
    job_id = uuid.uuid4().hex[:8]
    temp_wav = settings.TEMP_DIR / f"stt_{job_id}.wav"
    temp_wav.parent.mkdir(parents=True, exist_ok=True)
    
    try:
        cmd = ["ffmpeg", "-y"]
        if start_time_sec > 0.0:
            cmd += ["-ss", str(start_time_sec)]
        cmd += ["-i", str(clip_path.resolve())]
        if duration_sec and duration_sec > 0.0:
            cmd += ["-t", str(duration_sec)]
        cmd += [
            "-vn", "-ar", "16000", "-ac", "1",
            "-c:a", "pcm_s16le",
            str(temp_wav.resolve()),
        ]
        subprocess.run(cmd, capture_output=True, text=True)
        
        if not temp_wav.exists() or temp_wav.stat().st_size < 1000:
            return _get_default_viral_words(language)

        import whisper
        model = await asyncio.to_thread(whisper.load_model, settings.WHISPER_MODEL, device=settings.WHISPER_DEVICE)
        
        whisper_lang = None
        if language in ["bn", "bengali"]:
            whisper_lang = "bn"
        elif language in ["hi", "hindi"]:
            whisper_lang = "hi"
        elif language in ["ta", "tamil"]:
            whisper_lang = "ta"
        elif language in ["en", "english"]:
            whisper_lang = "en"
        else:
            whisper_lang = None

        result = await asyncio.to_thread(
            model.transcribe, str(temp_wav.resolve()),
            word_timestamps=True, language=whisper_lang, task="transcribe",
        )

        words = []
        for segment in result.get("segments", []):
            for w in segment.get("words", []):
                word_str = w["word"].strip()
                if word_str:
                    words.append(CaptionWord(
                        text=word_str,
                        start=w["start"],
                        end=w["end"],
                        confidence=w.get("probability", 1.0),
                    ))

        if not words:
            return _get_default_viral_words(language)
        return words
    except Exception as e:
        logger.warning(f"Whisper transcription notice ({e}) — using multilingual template hooks")
        return _get_default_viral_words(language)
    finally:
        if temp_wav.exists():
            try: os.remove(temp_wav)
            except Exception: pass

def _get_default_viral_words(language: str = "auto") -> list[CaptionWord]:
    if "bn" in language:
        text_samples = [
            ("এই", 0.2, 0.6), ("মুহূর্তটি", 0.6, 1.2), ("অবিশ্বাস্য!", 1.2, 1.9),
            ("WATCH", 2.0, 2.5), ("TILL", 2.5, 2.9), ("THE", 2.9, 3.2), ("END! 🔥", 3.2, 4.0),
            ("লাইক", 4.2, 4.6), ("ও", 4.6, 4.8), ("সাবস্ক্রাইব", 4.8, 5.6), ("করুন!", 5.6, 6.4),
        ]
    elif "hi" in language:
        text_samples = [
            ("ये", 0.2, 0.5), ("मोमेंट", 0.5, 1.0), ("कमाल", 1.0, 1.5), ("का", 1.5, 1.8), ("है!", 1.8, 2.3),
            ("WATCH", 2.5, 2.9), ("WHAT", 2.9, 3.3), ("HAPPENS! 🔥", 3.3, 4.2),
            ("लाइक", 4.4, 4.8), ("और", 4.8, 5.1), ("सब्सक्राइब", 5.1, 5.9), ("करें!", 5.9, 6.6),
        ]
    elif "ta" in language:
        text_samples = [
            ("இந்த", 0.2, 0.6), ("வீடியோவை", 0.6, 1.3), ("கண்டிப்பா", 1.3, 2.0), ("பாருங்க!", 2.0, 2.7),
            ("DON'T", 2.9, 3.4), ("MISS", 3.4, 3.8), ("THIS! 🔥", 3.8, 4.6),
        ]
    else:
        text_samples = [
            ("THIS", 0.2, 0.6), ("MOMENT", 0.6, 1.1), ("IS", 1.1, 1.4), ("TOTALLY", 1.4, 2.0), ("INSANE!", 2.0, 2.8),
            ("WATCH", 3.0, 3.5), ("WHAT", 3.5, 3.9), ("HAPPENS", 3.9, 4.6), ("NEXT! 🔥", 4.6, 5.5),
        ]
    return [CaptionWord(text=t, start=s, end=e, confidence=1.0) for t, s, e in text_samples]

def _group_into_lines(words: list[CaptionWord], words_per_line: int, language: str = "auto") -> list[CaptionLine]:
    lines = []
    for i in range(0, len(words), words_per_line):
        chunk = words[i:i + words_per_line]
        if chunk:
            lines.append(CaptionLine(
                words=chunk,
                start=chunk[0].start,
                end=chunk[-1].end,
                language=language,
            ))
    return lines

def _write_ass_file(lines: list[CaptionLine], config: CaptionConfig, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    
    # Scale font size from UI (e.g. 24px) to 1080x1920 canvas (e.g. 76px)
    ass_font_size = max(48, int(config.font_size * 2.8))
    
    # High-contrast ASS colors
    primary_color = _hex_to_ass_color(config.text_color)
    highlight_color = _hex_to_ass_color(config.highlight_color)
    outline_color = "&H00000000&" # Pure Pitch Black outline to prevent background blending
    shadow_color = "&H80000000&"  # 50% opacity shadow

    # Vertical placement margin
    margin_v = max(40, int((1.0 - config.placement_y) * 1920))

    header = f"""[Script Info]
Title: VerticalCraft Viral Subtitles
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,{config.font_family},{ass_font_size},{primary_color},{highlight_color},{outline_color},{shadow_color},-1,0,0,0,100,100,1,0,1,5,3,2,30,30,{margin_v},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events = []
    for line in lines:
        start_str = _sec_to_ass_time(line.start)
        end_str = _sec_to_ass_time(line.end)
        
        # Build text with explicit color tags per word to prevent any style/color collision
        dialogue_text = _format_line_text(line, config, primary_color, highlight_color, outline_color)
        events.append(f"Dialogue: 0,{start_str},{end_str},Default,,0,0,0,,{dialogue_text}")

    path.write_text(header + "\n".join(events), encoding="utf-8")
    logger.info(f"Wrote ASS subtitle file ({len(events)} events) -> {path}")

def _format_line_text(line: CaptionLine, config: CaptionConfig, primary_ass: str, highlight_ass: str, outline_ass: str) -> str:
    if config.animation == "karaoke":
        # Karaoke mode: highlight each word progressively
        words_k = []
        for w in line.words:
            k_dur = max(10, int((w.end - w.start) * 100))
            words_k.append(f"{{\\k{k_dur}}}{w.text.upper()}")
        return f"{{\\1c{primary_ass}\\2c{highlight_ass}\\3c{outline_ass}\\bord5}}" + " ".join(words_k)

    anim_prefix = ""
    if config.animation == "popup-blur":
        anim_prefix = "{\\blur6\\t(\\blur0\\fscx0\\fscy0,\\fscx100\\fscy100)}"
    elif config.animation == "popup":
        anim_prefix = "{\\t(\\fscx0\\fscy0,\\fscx100\\fscy100)}"
    elif config.animation == "zoom-blur":
        anim_prefix = "{\\blur5\\fscx125\\fscy125\\t(\\blur0\\fscx100\\fscy100)}"
    elif config.animation == "fade":
        anim_prefix = "{\\fad(120,120)}"
    elif config.animation == "stroke":
        anim_prefix = "{\\bord7\\blur1}"

    words_formatted = []
    for idx, w in enumerate(line.words):
        word_text = w.text.upper()
        if idx == len(line.words) - 1:
            # Climax highlight word: Highlight color + bold outline + slight pulse scale
            words_formatted.append(f"{{\\1c{highlight_ass}\\3c{outline_ass}\\bord5\\fscx108\\fscy108}}{word_text}{{\\1c{primary_ass}\\3c{outline_ass}\\bord5\\fscx100\\fscy100}}")
        else:
            words_formatted.append(f"{{\\1c{primary_ass}\\3c{outline_ass}\\bord5}}{word_text}")

    return anim_prefix + " ".join(words_formatted)

def _sec_to_ass_time(sec: float) -> str:
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h}:{m:02d}:{s:05.2f}"
