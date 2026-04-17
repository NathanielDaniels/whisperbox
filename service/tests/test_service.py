import asyncio
import json
import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from service import WhisperBoxService


@pytest.fixture
def service(tmp_path):
    sock_path = str(tmp_path / "test.sock")
    config = {
        "transcription": {"model": "small", "language": "en"},
        "behavior": {
            "mode": "instant",
            "max_duration": 300,
            "silence_timeout": 10,
            "sound_feedback": False,
        },
        "postprocessing": {
            "strip_fillers": True,
            "auto_capitalize": True,
            "auto_punctuate": True,
        },
    }
    return WhisperBoxService(config=config, sock_path=sock_path)


def test_handle_start_recording(service):
    """start_recording command should begin audio capture."""
    with patch.object(service, "_recorder") as mock_rec:
        service._handle_command({"cmd": "start_recording"})
        mock_rec.start.assert_called_once()
        assert service._state == "recording"


def test_handle_stop_recording(service):
    """stop_recording command should stop capture and trigger transcription."""
    import numpy as np

    service._state = "recording"
    mock_audio = np.zeros(16000, dtype=np.float32)
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
        patch.object(service, "_injector") as mock_inj,
    ):
        mock_rec.get_audio.return_value = mock_audio
        mock_trans.transcribe.return_value = "hello world"
        service._handle_command({"cmd": "stop_recording"})
        mock_rec.stop.assert_called_once()
        mock_trans.transcribe.assert_called_once()


def test_handle_cancel_recording(service):
    """cancel_recording should discard audio without transcription."""
    service._state = "recording"
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
    ):
        service._handle_command({"cmd": "cancel_recording"})
        mock_rec.cancel.assert_called_once()
        mock_trans.transcribe.assert_not_called()
        assert service._state == "idle"


def test_handle_unknown_command(service):
    """Unknown commands should be ignored."""
    service._handle_command({"cmd": "nonexistent"})
    assert service._state == "idle"
