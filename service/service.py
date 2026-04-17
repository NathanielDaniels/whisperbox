"""WhisperBox transcription service — main orchestrator.

Coordinates audio capture, transcription, post-processing, and text
injection. Communicates with the Swift menu bar app via Unix socket.
"""

import asyncio
import functools
import os
import signal
import sys
import threading

from audio import AudioRecorder
from config import load_config
from injector import TextInjector
from postprocess import postprocess
from socket_server import SocketServer
from transcriber import Transcriber


class WhisperBoxService:
    def __init__(self, config: dict | None = None, sock_path: str | None = None):
        self._config = config or load_config()
        tc = self._config["transcription"]
        bc = self._config["behavior"]

        self._sock_path = sock_path or os.path.expanduser(
            "~/.local/share/whisperbox/whisperbox.sock"
        )
        self._server = SocketServer(self._sock_path)
        self._server.on_command = self._handle_command
        self._server.on_client_connected = self._on_client_connected

        self._recorder = AudioRecorder(
            silence_timeout=bc.get("silence_timeout", 10),
        )
        self._recorder.on_silence_timeout = self._on_silence_timeout
        self._recorder.on_audio_level = self._on_audio_level

        self._transcriber = Transcriber(model_name=tc.get("model", "small"))
        self._injector = TextInjector()

        self._state = "idle"  # idle, recording, transcribing
        self._max_duration = bc.get("max_duration", 300)
        self._duration_timer: threading.Timer | None = None
        self._loop: asyncio.AbstractEventLoop | None = None

    async def _handle_command(self, cmd: dict):
        """Dispatch incoming commands from the Swift app."""
        action = cmd.get("cmd")

        if action == "start_recording" and self._state == "idle":
            await self._start_recording()
        elif action == "stop_recording" and self._state == "recording":
            await self._stop_and_transcribe()
        elif action == "cancel_recording" and self._state == "recording":
            await self._cancel_recording()
        elif action == "inject_text":
            # Preview mode: user confirmed text, inject it now
            text = cmd.get("text", "")
            if text:
                self._injector.inject(text)
        elif action == "switch_model":
            model = cmd.get("model", "small")
            await self._switch_model(model)
        elif action == "reload_config":
            self._config = load_config()

    async def _start_recording(self):
        """Begin audio capture."""
        self._state = "recording"
        self._recorder.start()
        await self._send_event({
            "event": "recording_started",
            "sound_feedback": self._config["behavior"].get("sound_feedback", True),
        })

        # Max duration safety timer
        self._duration_timer = threading.Timer(
            self._max_duration, self._on_max_duration
        )
        self._duration_timer.start()

    async def _stop_and_transcribe(self):
        """Stop recording, transcribe, and inject text."""
        self._cancel_timer()
        self._recorder.stop()
        self._state = "transcribing"
        await self._send_event({
            "event": "recording_stopped",
            "sound_feedback": self._config["behavior"].get("sound_feedback", True),
        })

        audio = self._recorder.get_audio()
        if audio is None or len(audio) < 1600:  # Less than 100ms
            self._state = "idle"
            await self._send_event(
                {"event": "transcription_error", "error": "Recording too short"}
            )
            return

        try:
            pp = self._config["postprocessing"]
            loop = asyncio.get_running_loop()

            # Run blocking transcription in thread pool
            raw_text = await loop.run_in_executor(
                None,
                functools.partial(
                    self._transcriber.transcribe,
                    audio,
                    language=self._config["transcription"].get("language", "en"),
                ),
            )
            text = postprocess(
                raw_text,
                capitalize=pp.get("auto_capitalize", True),
                punctuate=pp.get("auto_punctuate", True),
                strip_fillers=pp.get("strip_fillers", True),
            )

            mode = self._config["behavior"].get("mode", "instant")
            # Injection is handled by the Swift app via CGEvent

            await self._send_event(
                {
                    "event": "transcription_complete",
                    "text": text,
                    "preview": mode == "preview",
                }
            )
        except Exception as e:
            await self._send_event({"event": "transcription_error", "error": str(e)})
        finally:
            self._state = "idle"

    async def _cancel_recording(self):
        """Cancel recording without transcription."""
        self._cancel_timer()
        self._recorder.cancel()
        self._state = "idle"
        await self._send_event({
            "event": "recording_stopped",
            "sound_feedback": False,
        })

    async def _switch_model(self, model_name: str):
        """Switch to a different Whisper model."""
        await self._send_event({"event": "model_loading", "model": model_name})
        try:
            self._transcriber.switch_model(model_name)
            await self._send_event({"event": "model_loaded"})
        except Exception as e:
            await self._send_event({"event": "transcription_error", "error": str(e)})

    async def _on_client_connected(self):
        """Send current config to the Swift app on connect."""
        hk = self._config["hotkey"]
        bc = self._config["behavior"]
        await self._send_event({
            "event": "config",
            "hotkey_combo": hk.get("combo", "ctrl+shift+space"),
            "sound_feedback": bc.get("sound_feedback", True),
        })

    def _on_audio_level(self, level: float):
        """Called from audio thread with RMS level 0.0-1.0."""
        if self._loop and self._state == "recording":
            asyncio.run_coroutine_threadsafe(
                self._server.send_event({"event": "audio_level", "level": round(level, 3)}),
                self._loop,
            )

    def _on_silence_timeout(self):
        """Called when silence exceeds the timeout during recording."""
        if self._state == "recording" and self._loop:
            asyncio.run_coroutine_threadsafe(
                self._stop_and_transcribe(), self._loop
            )

    def _on_max_duration(self):
        """Called when recording exceeds the maximum duration."""
        if self._state == "recording" and self._loop:
            asyncio.run_coroutine_threadsafe(
                self._stop_and_transcribe(), self._loop
            )

    def _cancel_timer(self):
        if self._duration_timer:
            self._duration_timer.cancel()
            self._duration_timer = None

    async def _send_event(self, event: dict):
        """Send event to Swift app via socket."""
        await self._server.send_event(event)

    async def run(self):
        """Main entry point — load model and start socket server."""
        self._loop = asyncio.get_running_loop()

        # Load whisper model
        print(f"Loading Whisper model: {self._transcriber.model_name}")
        self._transcriber.load()
        print("Model loaded, starting socket server...")

        await self._server.start()


def main():
    config = load_config()
    service = WhisperBoxService(config=config)

    def shutdown(sig, frame):
        service._server.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    asyncio.run(service.run())


if __name__ == "__main__":
    main()
