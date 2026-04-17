import numpy as np
import pytest
from unittest.mock import patch, MagicMock
from audio import AudioRecorder


def test_recorder_initial_state():
    """Recorder should start in non-recording state."""
    recorder = AudioRecorder()
    assert not recorder.is_recording
    assert recorder.get_audio() is None


def test_recorder_start_stop():
    """Recorder should track recording state."""
    recorder = AudioRecorder()
    with patch("audio.sd") as mock_sd:
        mock_stream = MagicMock()
        mock_sd.InputStream.return_value = mock_stream
        mock_stream.__enter__ = MagicMock(return_value=mock_stream)
        mock_stream.__exit__ = MagicMock(return_value=False)

        recorder.start()
        assert recorder.is_recording

        recorder.stop()
        assert not recorder.is_recording


def test_recorder_callback_accumulates_audio():
    """Audio callback should accumulate samples into the buffer."""
    recorder = AudioRecorder()
    # Simulate audio callback with fake data
    fake_audio = np.random.randn(1600, 1).astype(np.float32)
    recorder._buffer = []
    recorder._audio_callback(fake_audio, None, None, None)
    assert len(recorder._buffer) == 1
    assert recorder._buffer[0].shape == (1600,)


def test_get_audio_returns_concatenated_float32():
    """get_audio should return a flat float32 numpy array."""
    recorder = AudioRecorder()
    chunk1 = np.ones(800, dtype=np.float32)
    chunk2 = np.ones(800, dtype=np.float32) * 0.5
    recorder._buffer = [chunk1, chunk2]
    recorder._is_recording = False
    audio = recorder.get_audio()
    assert audio.dtype == np.float32
    assert len(audio) == 1600
    assert audio[0] == 1.0
    assert audio[800] == 0.5


def test_silence_detection():
    """Silence detector should return True for near-zero audio."""
    recorder = AudioRecorder(silence_threshold=0.01)
    silent = np.zeros(1600, dtype=np.float32)
    assert recorder._is_silence(silent)
    loud = np.ones(1600, dtype=np.float32) * 0.5
    assert not recorder._is_silence(loud)
