"""Text post-processing pipeline for transcription output."""

import re

FILLER_WORDS = {"um", "uh", "er", "ah"}
# Match filler words as whole words, case-insensitive
FILLER_PATTERN = re.compile(
    r"\b(" + "|".join(re.escape(w) for w in FILLER_WORDS) + r")\b",
    re.IGNORECASE,
)

# Order matters: "new paragraph" before "new line" so longer match wins
LINE_BREAK_PHRASES = [
    (re.compile(r"\bnew\s+paragraph\b", re.IGNORECASE), "\n\n"),
    (re.compile(r"\bnew\s+line\b", re.IGNORECASE), "\n"),
]


def postprocess(
    text: str,
    capitalize: bool = True,
    punctuate: bool = True,
    strip_fillers: bool = True,
    smart_line_breaks: bool = False,
) -> str:
    """Clean up transcribed text.

    Args:
        text: Raw transcription text.
        capitalize: Capitalize the first letter.
        punctuate: Add a period if no ending punctuation.
        strip_fillers: Remove filler words (um, uh, etc).
        smart_line_breaks: Convert "new line"/"new paragraph" to line breaks.

    Returns:
        Cleaned text string.
    """
    text = text.strip()
    if not text:
        return ""

    # Strip Whisper artifacts like [BLANK_AUDIO], [Music], [Silence], etc.
    text = re.sub(r"\[.*?\]", "", text).strip()
    if not text:
        return ""

    if strip_fillers:
        text = FILLER_PATTERN.sub("", text)
        text = re.sub(r"\s+", " ", text).strip()

    if not text:
        return ""

    if smart_line_breaks:
        for pattern, replacement in LINE_BREAK_PHRASES:
            text = pattern.sub(replacement, text)
        # Clean up spaces around line breaks
        text = re.sub(r" *\n *", "\n", text)
        text = text.strip()

    if not text:
        return ""

    if capitalize and text:
        # Capitalize first letter of text and first letter after each line break
        lines = text.split("\n")
        capitalized = []
        for line in lines:
            if line:
                line = line[0].upper() + line[1:]
            capitalized.append(line)
        text = "\n".join(capitalized)

    if punctuate and text and text[-1] not in ".!?\n":
        text += "."

    return text
