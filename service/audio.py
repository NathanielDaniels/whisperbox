"""Audio capture module using sounddevice.

Records 16kHz mono float32 audio into an in-memory buffer.
Supports silence detection for auto-stop.
"""

import threading
import numpy as np
import sounddevice as sd


class AudioRecorder:
    SAMPLE_RATE = 16000  # Whisper expects 16kHz
    CHANNELS = 1

    def __init__(self, silence_threshold: float = 0.01, silence_timeout: float = 10.0):
        self._buffer: list[np.ndarray] = []
        self._is_recording = False
        self._stream: sd.InputStream | None = None
        self._silence_threshold = silence_threshold
        self._silence_timeout = silence_timeout
        self._silence_frames = 0
        self._frames_per_second = self.SAMPLE_RATE
        self.on_silence_timeout: callable = lambda: None
        self.on_audio_level: callable = lambda level: None

    @property
    def is_recording(self) -> bool:
        return self._is_recording

    def start(self):
        """Start recording audio from the default input device."""
        self._buffer = []
        self._silence_frames = 0
        self._is_recording = True
        self._stream = sd.InputStream(
            samplerate=self.SAMPLE_RATE,
            channels=self.CHANNELS,
            dtype="float32",
            callback=self._audio_callback,
            blocksize=1600,  # 100ms blocks
        )
        self._stream.start()

    def stop(self):
        """Stop recording and close the stream."""
        self._is_recording = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

    def cancel(self):
        """Stop recording and discard the buffer."""
        self.stop()
        self._buffer = []

    def get_audio(self) -> np.ndarray | None:
        """Return recorded audio as a flat float32 array, or None if empty."""
        if not self._buffer:
            return None
        return np.concatenate(self._buffer)

    def _audio_callback(self, indata, frames, time_info, status):
        """sounddevice callback — runs on audio thread."""
        mono = indata[:, 0] if indata.ndim > 1 else indata.flatten()
        self._buffer.append(mono.copy())

        # Compute RMS level (0.0 to 1.0, clamped)
        rms = float(np.sqrt(np.mean(mono ** 2)))
        level = min(rms * 15.0, 1.0)  # Scale up for visibility
        self.on_audio_level(level)

        # Silence detection
        if self._is_silence(mono):
            self._silence_frames += len(mono)
            if self._silence_frames >= self._silence_timeout * self.SAMPLE_RATE:
                self.on_silence_timeout()
        else:
            self._silence_frames = 0

    def _is_silence(self, audio: np.ndarray) -> bool:
        """Check if audio chunk is below the silence threshold."""
        return float(np.abs(audio).mean()) < self._silence_threshold
