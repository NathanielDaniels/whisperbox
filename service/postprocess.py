"""Text post-processing pipeline for transcription output."""

import re

FILLER_WORDS = {"um", "uh", "er", "ah"}
# Match filler words as whole words, case-insensitive
FILLER_PATTERN = re.compile(
    r"\b(" + "|".join(re.escape(w) for w in FILLER_WORDS) + r")\b",
    re.IGNORECASE,
)


def postprocess(
    text: str,
    capitalize: bool = True,
    punctuate: bool = True,
    strip_fillers: bool = True,
) -> str:
    """Clean up transcribed text.

    Args:
        text: Raw transcription text.
        capitalize: Capitalize the first letter.
        punctuate: Add a period if no ending punctuation.
        strip_fillers: Remove filler words (um, uh, etc).

    Returns:
        Cleaned text string.
    """
    text = text.strip()
    if not text:
        return ""

    if strip_fillers:
        text = FILLER_PATTERN.sub("", text)
        text = re.sub(r"\s+", " ", text).strip()

    if not text:
        return ""

    if capitalize and text:
        text = text[0].upper() + text[1:]

    if punctuate and text and text[-1] not in ".!?":
        text += "."

    return text
