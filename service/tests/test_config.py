# service/tests/test_config.py
import os
import tempfile
import pytest
from config import load_config, DEFAULT_CONFIG


def test_load_default_config_when_file_missing():
    """When no config file exists, return defaults."""
    config = load_config("/nonexistent/path/config.toml")
    assert config["transcription"]["model"] == "small"
    assert config["behavior"]["mode"] == "instant"
    assert config["behavior"]["max_duration"] == 300
    assert config["behavior"]["silence_timeout"] == 10
    assert config["postprocessing"]["strip_fillers"] is True


def test_load_config_from_file():
    """Load and merge config from a TOML file."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
        f.write('[transcription]\nmodel = "medium"\n')
        f.flush()
        config = load_config(f.name)
    os.unlink(f.name)
    # Overridden value
    assert config["transcription"]["model"] == "medium"
    # Default preserved
    assert config["behavior"]["mode"] == "instant"


def test_default_language_is_auto():
    """Default language should be 'auto' for auto-detection."""
    config = load_config("/nonexistent/path/config.toml")
    assert config["transcription"]["language"] == "auto"


def test_load_config_invalid_toml_returns_defaults():
    """Malformed TOML should fall back to defaults, not crash."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
        f.write("this is not valid [[[ toml")
        f.flush()
        config = load_config(f.name)
    os.unlink(f.name)
    assert config["transcription"]["model"] == "small"
