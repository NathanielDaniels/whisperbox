"""WhisperBox configuration loader.

Reads TOML config from ~/.config/whisperbox/config.toml,
merging with defaults for any missing values.
"""

import copy
import os
import tomllib

DEFAULT_CONFIG = {
    "hotkey": {
        "combo": "ctrl+shift+space",
    },
    "transcription": {
        "model": "small",
        "language": "auto",
    },
    "behavior": {
        "mode": "instant",
        "sound_feedback": True,
        "max_duration": 300,
        "silence_timeout": 10,
        "append_mode": True,
        "pause_media": True,
    },
    "postprocessing": {
        "strip_fillers": True,
        "auto_capitalize": True,
        "auto_punctuate": True,
        "smart_line_breaks": True,
    },
    "indicator": {
        "enabled": True,
        "position": "top-center",
        "opacity": 0.85,
    },
}

CONFIG_PATH = os.path.expanduser("~/.config/whisperbox/config.toml")


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base, returning a new dict."""
    result = copy.deepcopy(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def load_config(path: str | None = None) -> dict:
    """Load config from TOML file, merged with defaults.

    Args:
        path: Path to config file. Defaults to CONFIG_PATH.

    Returns:
        Merged configuration dictionary.
    """
    path = path or CONFIG_PATH
    if not os.path.exists(path):
        return copy.deepcopy(DEFAULT_CONFIG)
    try:
        with open(path, "rb") as f:
            user_config = tomllib.load(f)
        return _deep_merge(DEFAULT_CONFIG, user_config)
    except Exception:
        return copy.deepcopy(DEFAULT_CONFIG)
