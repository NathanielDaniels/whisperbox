"""Whisper transcription wrapper using pywhispercpp.

Loads a whisper.cpp model once and keeps it in memory for fast inference.
Models are auto-downloaded to the specified models directory.
"""

import os
import numpy as np
from pywhispercpp.model import Model


class Transcriber:
    VALID_MODELS = ("tiny", "base", "small", "medium", "large-v3")

    def __init__(self, model_name: str = "small", models_dir: str | None = None):
        self.model_name = model_name
        self.models_dir = models_dir or os.path.expanduser(
            "~/.local/share/whisperbox/models"
        )
        self._model: Model | None = None

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def load(self):
        """Load the whisper model into memory."""
        os.makedirs(self.models_dir, exist_ok=True)
        self._model = Model(
            self.model_name,
            models_dir=self.models_dir,
            n_threads=os.cpu_count() or 4,
        )

    def transcribe(self, audio: np.ndarray, language: str = "en") -> str:
        """Transcribe audio array to text.

        Args:
            audio: Float32 numpy array of audio at 16kHz.
            language: Language code for transcription.

        Returns:
            Transcribed text, stripped and joined from segments.
        """
        if self._model is None:
            raise RuntimeError("Model not loaded. Call load() first.")

        segments = self._model.transcribe(audio, language=language)
        text = " ".join(seg.text.strip() for seg in segments if seg.text.strip())
        return text

    def switch_model(self, model_name: str):
        """Switch to a different model, reloading it into memory."""
        self.model_name = model_name
        self._model = None
        self.load()
