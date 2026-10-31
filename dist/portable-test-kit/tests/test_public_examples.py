"""Public, non-invasive examples for the portable pytest kit.

These tests only send ICMP echo requests and read the root of the C: drive.
They do not modify files or system configuration.
"""

from pathlib import Path
import shutil
import subprocess

import pytest


PING_EXECUTABLE = shutil.which("ping")
BAIDU_HOST = "www.baidu.com"
GOOGLE_HOST = "www.google.com"
GOOGLE_TIMEOUT_SECONDS = 3


def _ping_command(
    host: str,
    count: int,
    reply_timeout_seconds: int | None = None,
) -> list[str]:
    if PING_EXECUTABLE is None:
        pytest.fail("ping.exe was not found on PATH")

    command = [PING_EXECUTABLE, "-n", str(count)]
    if reply_timeout_seconds is not None:
        command.extend(["-w", str(reply_timeout_seconds * 1000)])
    command.append(host)
    return command


def _run_ping(
    host: str,
    count: int,
    process_timeout_seconds: int,
    reply_timeout_seconds: int | None = None,
) -> subprocess.CompletedProcess[str]:
    command = _ping_command(host, count, reply_timeout_seconds)
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="oem",
            errors="replace",
            check=False,
            timeout=process_timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"ping {host} exceeded the {process_timeout_seconds}-second timeout"
        )

    return completed


def test_ping_baidu() -> None:
    completed = _run_ping(BAIDU_HOST, count=4, process_timeout_seconds=15)

    output = completed.stdout + completed.stderr
    assert completed.returncode == 0, output
    assert "TTL=" in output.upper(), output


def test_ping_google_with_three_second_timeout() -> None:
    completed = _run_ping(
        GOOGLE_HOST,
        count=1,
        process_timeout_seconds=GOOGLE_TIMEOUT_SECONDS,
        reply_timeout_seconds=GOOGLE_TIMEOUT_SECONDS,
    )

    output = completed.stdout + completed.stderr
    assert completed.returncode == 0, output
    assert "TTL=" in output.upper(), output


def test_list_c_drive_root_directory() -> None:
    c_drive = Path("C:/")
    assert c_drive.is_dir(), f"{c_drive} is not an accessible directory"

    entries = sorted(entry.name for entry in c_drive.iterdir())

    assert entries, f"{c_drive} is empty"
    assert any(name.casefold() == "windows" for name in entries), entries
