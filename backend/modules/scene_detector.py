from __future__ import annotations
from pathlib import Path
from typing import Any
from loguru import logger

def get_scene_cuts(clip_path: Path, threshold: float = 27.0) -> list[dict[str, Any]]:
    try:
        from scenedetect import open_video, SceneManager
        from scenedetect.detectors import ContentDetector
    except ImportError:
        logger.warning("scenedetect not installed — scene cut detection skipped")
        return []
    try:
        video = open_video(str(clip_path))
        manager = SceneManager()
        manager.add_detector(ContentDetector(threshold=threshold))
        manager.detect_scenes(video)
        scenes = manager.get_scene_list()
        cuts = [
            {"timestamp": scene[0].get_seconds(), "score": 0.8, "scene_index": i}
            for i, scene in enumerate(scenes)
        ]
        logger.info(f"Detected {len(cuts)} scene cuts in {clip_path.name}")
        return cuts
    except Exception as e:
        logger.error(f"Scene detection failed: {e}")
        return []
