"""AI post-processing via local LLM (LM Studio).

Sends transcribed text to a local OpenAI-compatible API for grammar
and phrasing cleanup. Runs async so it doesn't block transcription.
"""

import asyncio
import json
import logging
import re
import urllib.request
import urllib.error

logger = logging.getLogger(__name__)


class AIPolisher:
    def __init__(self, config: dict):
        ai = config.get("ai", {})
        self._enabled = ai.get("enabled", True)
        self._endpoint = ai.get("endpoint", "http://127.0.0.1:1234/v1/chat/completions")
        self._model = ai.get("model", "google/gemma-3-12b")
        self._max_chars = ai.get("max_chars", 5000)
        self._system_prompt = ai.get(
            "system_prompt",
            "Fix grammar and smooth phrasing. Keep the speaker's voice and intent. "
            "Do not add or remove meaning. Return only the corrected text with no explanation.",
        )

    @property
    def is_available(self) -> bool:
        return self._enabled

    async def polish(self, text: str) -> str | None:
        """Send text to local LLM for cleanup. Returns polished text or None on failure."""
        if not self._enabled or not text or len(text) > self._max_chars:
            return None

        try:
            loop = asyncio.get_running_loop()
            result = await loop.run_in_executor(None, self._call_api, text)
            return result
        except Exception as e:
            logger.warning("AI polish failed: %s", e)
            return None

    def _call_api(self, text: str) -> str | None:
        """Synchronous API call to local LLM."""
        payload = json.dumps({
            "model": self._model,
            "messages": [
                {"role": "system", "content": self._system_prompt},
                {"role": "user", "content": text},
            ],
            "temperature": 0.3,
            "max_tokens": len(text) * 2 + 100,
        }).encode("utf-8")

        req = urllib.request.Request(
            self._endpoint,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read())
                msg = data["choices"][0]["message"]
                # Some models (GLM) put output in content, others in reasoning_content
                content = msg.get("content", "").strip()
                if not content:
                    # Check reasoning_content for reasoning models
                    content = msg.get("reasoning_content", "").strip()
                # Strip model-specific tokens and artifacts
                content = content.lstrip("\n")
                content = re.sub(r"<\|.*?\|>", "", content).strip()
                # Strip markdown quotes if model wraps output
                if content.startswith('"') and content.endswith('"'):
                    content = content[1:-1].strip()
                return content if content else None
        except (urllib.error.URLError, KeyError, IndexError, json.JSONDecodeError) as e:
            logger.warning("LM Studio request failed: %s", e)
            return None
