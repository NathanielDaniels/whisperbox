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


@pytest.mark.asyncio
async def test_handle_start_recording(service):
    """start_recording command should begin audio capture."""
    with patch.object(service, "_recorder") as mock_rec, \
         patch.object(service._server, "send_event", new_callable=AsyncMock):
        await service._handle_command({"cmd": "start_recording"})
        mock_rec.start.assert_called_once()
        assert service._state == "recording"


@pytest.mark.asyncio
async def test_handle_stop_recording(service):
    """stop_recording command should stop capture and trigger transcription."""
    import numpy as np

    service._state = "recording"
    mock_audio = np.zeros(16000, dtype=np.float32)
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
        patch.object(service, "_injector") as mock_inj,
        patch.object(service._server, "send_event", new_callable=AsyncMock),
    ):
        mock_rec.get_audio.return_value = mock_audio
        mock_trans.transcribe.return_value = "hello world"
        await service._handle_command({"cmd": "stop_recording"})
        mock_rec.stop.assert_called_once()
        mock_trans.transcribe.assert_called_once()


@pytest.mark.asyncio
async def test_handle_cancel_recording(service):
    """cancel_recording should discard audio without transcription."""
    service._state = "recording"
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
        patch.object(service._server, "send_event", new_callable=AsyncMock),
    ):
        await service._handle_command({"cmd": "cancel_recording"})
        mock_rec.cancel.assert_called_once()
        mock_trans.transcribe.assert_not_called()
        assert service._state == "idle"


@pytest.mark.asyncio
async def test_handle_unknown_command(service):
    """Unknown commands should be ignored."""
    await service._handle_command({"cmd": "nonexistent"})
    assert service._state == "idle"


# -- Append buffer fixtures and helpers --

@pytest.fixture
def append_service(tmp_path):
    """Service with append_mode enabled."""
    sock_path = str(tmp_path / "test.sock")
    config = {
        "transcription": {"model": "small", "language": "en"},
        "behavior": {
            "mode": "instant",
            "max_duration": 300,
            "silence_timeout": 10,
            "sound_feedback": False,
            "append_mode": True,
        },
        "postprocessing": {
            "strip_fillers": True,
            "auto_capitalize": True,
            "auto_punctuate": True,
        },
    }
    return WhisperBoxService(config=config, sock_path=sock_path)


async def _do_transcription(svc, text: str) -> dict:
    """Put the service through a record-stop cycle and return the sent event."""
    import numpy as np

    svc._state = "recording"
    mock_audio = np.zeros(16000, dtype=np.float32)

    captured = {}

    async def capture_event(evt):
        if evt.get("event") == "transcription_complete":
            captured.update(evt)

    with (
        patch.object(svc, "_recorder") as mock_rec,
        patch.object(svc, "_transcriber") as mock_trans,
        patch.object(svc, "_injector"),
        patch.object(svc._server, "send_event", new_callable=AsyncMock, side_effect=capture_event),
    ):
        mock_rec.get_audio.return_value = mock_audio
        mock_trans.transcribe.return_value = text
        await svc._stop_and_transcribe()

    return captured


# -- Append buffer tests --

@pytest.mark.asyncio
async def test_append_buffer_accumulates(append_service):
    """Buffer accumulates across multiple transcriptions when append_mode is True."""
    await _do_transcription(append_service, "hello")
    await _do_transcription(append_service, "world")

    # postprocessing capitalizes and punctuates
    assert append_service._append_buffer == ["Hello.", "World."]


@pytest.mark.asyncio
async def test_clear_buffer_command(append_service):
    """clear_buffer command clears the append buffer."""
    await _do_transcription(append_service, "hello")
    assert len(append_service._append_buffer) == 1

    await append_service._handle_command({"cmd": "clear_buffer"})
    assert append_service._append_buffer == []


@pytest.mark.asyncio
async def test_cancel_clears_buffer(append_service):
    """Cancelling a recording clears the append buffer."""
    await _do_transcription(append_service, "hello")
    assert len(append_service._append_buffer) == 1

    append_service._state = "recording"
    with (
        patch.object(append_service, "_recorder") as mock_rec,
        patch.object(append_service._server, "send_event", new_callable=AsyncMock),
    ):
        await append_service._handle_command({"cmd": "cancel_recording"})

    assert append_service._append_buffer == []


@pytest.mark.asyncio
async def test_full_text_joins_segments(append_service):
    """full_text is the join of all segments with spaces."""
    await _do_transcription(append_service, "hello")
    evt = await _do_transcription(append_service, "world")

    assert evt["full_text"] == "Hello. World."


@pytest.mark.asyncio
async def test_append_flag_first_and_subsequent(append_service):
    """append flag is False on first dictation and True on subsequent ones."""
    evt1 = await _do_transcription(append_service, "first")
    assert evt1["append"] is False

    evt2 = await _do_transcription(append_service, "second")
    assert evt2["append"] is True


@pytest.mark.asyncio
async def test_no_append_fields_when_mode_off(service):
    """When append_mode is False, no full_text or append in events."""
    evt = await _do_transcription(service, "hello")

    assert "full_text" not in evt
    assert "append" not in evt
