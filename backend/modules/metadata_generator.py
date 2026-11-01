from __future__ import annotations
import asyncio, json
from pathlib import Path
from loguru import logger

PLATFORM_PROMPTS = {
    "youtube": "YouTube Shorts (max 100 char title, 5000 char description, 15 hashtags)",
    "instagram": "Instagram Reels (max 2200 char caption, 30 hashtags)",
    "facebook": "Facebook Reels (max 500 char caption, 10 hashtags)",
    "x": "X (Twitter) video (max 280 char text, 5 hashtags)",
    "tiktok": "TikTok video (max 150 char caption, 20 hashtags)",
}

async def generate_metadata(
    clip_path: Path,
    transcript: str,
    niche: str,
    platform: str = "youtube",
    language: str = "en",
    use_gemini: bool = False,
) -> dict:
    platform_guide = PLATFORM_PROMPTS.get(platform, PLATFORM_PROMPTS["youtube"])
    prompt = (
        f"You are a social media content strategist.\n"
        f"Niche: {niche}. Platform: {platform_guide}.\n"
        f"Language: {language} (if Bengali, use both Bangla and English tags).\n"
        f"Transcript excerpt: {transcript[:1500]}\n\n"
        f"Generate metadata as JSON with fields: title, description, hashtags (list), tags (list).\n"
        f"Make it engaging, SEO-optimized, and viral-friendly for {niche} content."
    )
    if use_gemini:
        return await _generate_with_gemini(prompt, platform)
    else:
        return await _generate_with_ollama(prompt, platform)

async def _generate_with_ollama(prompt: str, platform: str) -> dict:
    try:
        import ollama
        from backend.core.config import settings
        response = await asyncio.to_thread(
            ollama.generate,
            model=settings.OLLAMA_MODEL,
            prompt=prompt,
            format="json",
        )
        data = json.loads(response["response"])
        return _normalize_metadata(data, platform)
    except Exception as e:
        logger.error(f"Ollama metadata generation failed: {e}")
        return {"title": "", "description": "", "hashtags": [], "tags": [], "platform": platform}

async def _generate_with_gemini(prompt: str, platform: str) -> dict:
    try:
        from google import genai
        from backend.core.config import settings
        client = genai.Client(api_key=settings.GEMINI_API_KEY)
        response = await asyncio.to_thread(
            client.models.generate_content,
            model=settings.GEMINI_MODEL,
            contents=prompt,
        )
        data = json.loads(response.text)
        return _normalize_metadata(data, platform)
    except Exception as e:
        logger.error(f"Gemini metadata generation failed: {e}")
        return {"title": "", "description": "", "hashtags": [], "tags": [], "platform": platform}

def _normalize_metadata(data: dict, platform: str) -> dict:
    return {
        "title": data.get("title", ""),
        "description": data.get("description", ""),
        "hashtags": data.get("hashtags", [])[:30],
        "tags": data.get("tags", [])[:50],
        "platform": platform,
    }
