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
