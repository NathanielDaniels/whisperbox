from postprocess import postprocess


def test_capitalize_first_letter():
    assert postprocess("hello world", capitalize=True) == "Hello world."


def test_add_period_when_missing():
    assert postprocess("Hello world", punctuate=True) == "Hello world."


def test_no_double_period():
    assert postprocess("Hello world.", punctuate=True) == "Hello world."


def test_preserve_question_mark():
    assert postprocess("How are you?", punctuate=True) == "How are you?"


def test_preserve_exclamation():
    assert postprocess("Wow!", punctuate=True) == "Wow!"


def test_strip_fillers():
    assert postprocess("Um hello uh world", strip_fillers=True) == "Hello world."


def test_strip_fillers_case_insensitive():
    assert postprocess("UM hello UH world", strip_fillers=True) == "Hello world."


def test_empty_string():
    assert postprocess("") == ""


def test_whitespace_only():
    assert postprocess("   ") == ""


def test_all_options_disabled():
    result = postprocess(
        "um hello", capitalize=False, punctuate=False, strip_fillers=False
    )
    assert result == "um hello"


def test_filler_only_input():
    assert postprocess("um uh", strip_fillers=True) == ""


def test_new_line_replacement():
    result = postprocess("first line new line second line", smart_line_breaks=True)
    assert result == "First line\nSecond line."


def test_new_paragraph_replacement():
    result = postprocess("first paragraph new paragraph second paragraph", smart_line_breaks=True)
    assert result == "First paragraph\n\nSecond paragraph."


def test_line_break_case_insensitive():
    result = postprocess("hello New Line world", smart_line_breaks=True)
    assert result == "Hello\nWorld."


def test_multiple_line_breaks():
    result = postprocess("one new line two new line three", smart_line_breaks=True)
    assert result == "One\nTwo\nThree."


def test_line_breaks_disabled_by_default():
    """With smart_line_breaks=False (default), phrases pass through literally."""
    result = postprocess("hello new line world")
    assert result == "Hello new line world."


def test_line_break_with_fillers():
    result = postprocess("um first um new line second", strip_fillers=True, smart_line_breaks=True)
    assert result == "First\nSecond."
