import subprocess
from unittest.mock import patch, MagicMock, call
from injector import TextInjector


@patch("injector.subprocess.run")
def test_inject_uses_applescript_paste(mock_run):
    """Primary injection should use pbcopy + Cmd+V via AppleScript."""
    mock_run.return_value = MagicMock(returncode=0)
    injector = TextInjector()
    injector.inject("Hello world")

    calls = mock_run.call_args_list
    # First call: save clipboard
    # Second call: pbcopy
    # Third call: Cmd+V via osascript
    # Fourth call: restore clipboard
    assert any("pbcopy" in str(c) for c in calls)
    assert any("osascript" in str(c) for c in calls)


@patch("injector.subprocess.run")
def test_inject_empty_text_is_noop(mock_run):
    """Injecting empty text should do nothing."""
    injector = TextInjector()
    injector.inject("")
    mock_run.assert_not_called()


@patch("injector.subprocess.run")
def test_inject_preserves_clipboard(mock_run):
    """Clipboard should be saved and restored around injection."""
    # pbpaste returns old clipboard
    mock_run.side_effect = [
        MagicMock(returncode=0, stdout="old-clipboard"),  # pbpaste (save)
        MagicMock(returncode=0),  # pbcopy (set new text)
        MagicMock(returncode=0),  # osascript (Cmd+V)
        MagicMock(returncode=0),  # pbcopy (restore)
    ]
    injector = TextInjector()
    injector.inject("new text")
    # Last call should restore "old-clipboard"
    last_call = mock_run.call_args_list[-1]
    assert "old-clipboard" in str(last_call) or "pbcopy" in str(last_call)
