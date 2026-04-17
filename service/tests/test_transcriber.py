import numpy as np
import pytest
from unittest.mock import patch, MagicMock
from transcriber import Transcriber

MODEL_DIR = "/tmp/whisperbox-test-models"


@patch("transcriber.Model")
def test_transcriber_loads_model(mock_model_cls):
    """Transcriber should load the specified model on init."""
    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    mock_model_cls.assert_called_once()
    call_args = mock_model_cls.call_args
    assert "small" in str(call_args)


@patch("transcriber.Model")
def test_transcribe_returns_text(mock_model_cls):
    """Transcribe should return the text from whisper segments."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = [
        MagicMock(text=" Hello world. "),
        MagicMock(text=" How are you? "),
    ]
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(16000, dtype=np.float32)
    result = t.transcribe(audio)
    assert result == "Hello world. How are you?"


@patch("transcriber.Model")
def test_transcribe_empty_audio(mock_model_cls):
    """Transcribe with empty audio should return empty string."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = []
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(100, dtype=np.float32)
    result = t.transcribe(audio)
    assert result == ""


@patch("transcriber.Model")
def test_transcribe_auto_language(mock_model_cls):
    """When language is 'auto', pass empty string to whisper for auto-detection."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = [MagicMock(text="Bonjour")]
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(16000, dtype=np.float32)
    t.transcribe(audio, language="auto")

    call_args = mock_model.transcribe.call_args
    assert call_args[1]["language"] == ""


@patch("transcriber.Model")
def test_switch_model(mock_model_cls):
    """Switching models should reload with the new model name."""
    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    assert mock_model_cls.call_count == 1

    t.switch_model("medium")
    assert mock_model_cls.call_count == 2
    assert t.model_name == "medium"
