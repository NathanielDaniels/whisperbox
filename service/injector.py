"""Text injection into the focused application.

Primary: saves clipboard, copies text via pbcopy, pastes via Cmd+V
(AppleScript), then restores clipboard. Fast and Unicode-safe.
"""

import subprocess
import time


class TextInjector:
    # Delay after setting clipboard before sending Cmd+V
    CLIPBOARD_SETTLE_DELAY = 0.05
    # Delay after paste before restoring clipboard
    PASTE_DELAY = 0.25

    def inject(self, text: str):
        """Inject text at the current cursor position in the focused app."""
        if not text:
            return

        # Save current clipboard
        saved = self._get_clipboard()

        try:
            # Copy transcribed text to clipboard
            self._set_clipboard(text)

            # Let the pasteboard change propagate
            time.sleep(self.CLIPBOARD_SETTLE_DELAY)

            # Paste via Cmd+V using AppleScript
            subprocess.run(
                [
                    "osascript",
                    "-e",
                    'tell application "System Events" to keystroke "v" using command down',
                ],
                check=True,
                capture_output=True,
            )

            # Wait for paste to complete
            time.sleep(self.PASTE_DELAY)
        finally:
            # Restore original clipboard
            self._set_clipboard(saved)

    def _get_clipboard(self) -> str:
        """Read current clipboard contents."""
        try:
            result = subprocess.run(
                ["pbpaste"], capture_output=True, text=True, timeout=2
            )
            return result.stdout
        except Exception:
            return ""

    def _set_clipboard(self, text: str):
        """Set clipboard contents via pbcopy."""
        subprocess.run(
            ["pbcopy"],
            input=text.encode("utf-8"),
            check=True,
            timeout=2,
        )
