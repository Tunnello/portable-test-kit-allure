import io
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any

import pytest


PORTABLE_TEST_ENV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PORTABLE_TEST_ENV))

import run_tests


def _create_package(tmp_path: Path) -> Path:
    package_root = tmp_path / "package with spaces"
    for relative_path in (
        "python/python.exe",
        "allure/bin/allure.bat",
        "java/bin/java.exe",
    ):
        executable = package_root / relative_path
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.touch()

    manifest = {
        "runtime": {"package_python_path": "python/python.exe"},
        "allure": {"executable_path": "allure/bin/allure.bat"},
        "java_runtime": {
            "package_path": "java",
            "executable_path": "java/bin/java.exe",
        },
    }
    (package_root / "bundle-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )
    (package_root / "tests").mkdir()
    (package_root / "logs").mkdir()
    return package_root


def _successful_process(
    package_root: Path,
    calls: list[tuple[Any, dict[str, Any]]],
    pytest_exit: int = 0,
    report_exit: int = 0,
):
    results_dir = package_root / "allure-results"
    report_dir = package_root / "allure-report"

    def fake_run(command: Any, **kwargs: Any) -> subprocess.CompletedProcess[str]:
        calls.append((command, kwargs))
        if "-m" in command and "pytest" in command:
            results_dir.mkdir(parents=True, exist_ok=True)
            (results_dir / "current-result.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(command, pytest_exit, "pytest output", "")
        if "generate" in command:
            if report_exit == 0:
                report_dir.mkdir(parents=True, exist_ok=True)
                (report_dir / "index.html").write_text("report", encoding="utf-8")
            return subprocess.CompletedProcess(command, report_exit, "generate output", "")
        return subprocess.CompletedProcess(command, 0, "open output", "")

    return fake_run


def _successful_start_process(
    calls: list[tuple[Any, dict[str, Any]]],
):
    class FakeProcess:
        def __init__(self) -> None:
            self.stdout = io.StringIO(
                "Server started at http://127.0.0.1:49152. Press Ctrl+C to exit.\n"
            )

        def wait(self) -> int:
            return 0

    def fake_start(command: Any, **kwargs: Any) -> FakeProcess:
        calls.append((command, kwargs))
        return FakeProcess()

    return fake_start


def test_failed_pytest_still_generates_and_opens_local_report(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    package_root = _create_package(tmp_path)
    calls: list[tuple[Any, dict[str, Any]]] = []
    process_calls: list[tuple[Any, dict[str, Any]]] = []
    original_path = os.environ.get("PATH")
    original_java_home = os.environ.get("JAVA_HOME")
    fake_run = _successful_process(package_root, calls, pytest_exit=1)

    exit_code = run_tests.run(
        package_root,
        ["-k", "public_examples"],
        process_runner=fake_run,
        process_starter=_successful_start_process(process_calls),
    )

    assert exit_code == 1
    assert len(calls) == 2
    pytest_command, _ = calls[0]
    assert pytest_command[0].endswith("python.exe")
    assert pytest_command[pytest_command.index("--alluredir") + 1].endswith(
        "allure-results"
    )
    assert "public_examples" in pytest_command
    open_command, open_options = process_calls[0]
    assert "127.0.0.1" in open_command
    assert "allure-report" in open_command
    assert open_options["shell"] is True
    assert open_options["stdout"] == subprocess.PIPE
    assert open_options["stderr"] == subprocess.STDOUT
    assert open_options["env"]["JAVA_HOME"].endswith("java")
    assert os.environ.get("PATH") == original_path
    assert os.environ.get("JAVA_HOME") == original_java_home


def test_runner_clears_only_its_previous_report_outputs(tmp_path: Path) -> None:
    package_root = _create_package(tmp_path)
    stale_result = package_root / "allure-results" / "old-result.json"
    stale_result.parent.mkdir()
    stale_result.write_text("stale", encoding="utf-8")
    stale_report = package_root / "allure-report" / "index.html"
    stale_report.parent.mkdir()
    stale_report.write_text("stale", encoding="utf-8")
    unrelated = package_root / "keep.txt"
    unrelated.write_text("keep", encoding="utf-8")
    calls: list[tuple[Any, dict[str, Any]]] = []
    process_calls: list[tuple[Any, dict[str, Any]]] = []

    exit_code = run_tests.run(
        package_root,
        [],
        process_runner=_successful_process(package_root, calls),
        process_starter=_successful_start_process(process_calls),
    )

    assert exit_code == 0
    assert not stale_result.exists()
    assert (package_root / "allure-results" / "current-result.json").is_file()
    assert (package_root / "allure-report" / "index.html").is_file()
    assert unrelated.read_text(encoding="utf-8") == "keep"


def test_runner_rejects_user_managed_alluredir(tmp_path: Path) -> None:
    package_root = _create_package(tmp_path)

    with pytest.raises(run_tests.RunnerError, match="alluredir"):
        run_tests.run(package_root, ["--alluredir=elsewhere"])


def test_report_generation_failure_does_not_open_stale_report(
    tmp_path: Path,
) -> None:
    package_root = _create_package(tmp_path)
    calls: list[tuple[Any, dict[str, Any]]] = []

    exit_code = run_tests.run(
        package_root,
        [],
        process_runner=_successful_process(
            package_root,
            calls,
            pytest_exit=0,
            report_exit=1,
        ),
    )

    assert exit_code != 0
    assert len(calls) == 2
    assert not (package_root / "allure-report" / "index.html").exists()


def test_allure_server_url_is_streamed_and_logged(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    package_root = _create_package(tmp_path)
    calls: list[tuple[Any, dict[str, Any]]] = []
    fake_run = _successful_process(package_root, calls)

    process_calls: list[tuple[Any, dict[str, Any]]] = []

    exit_code = run_tests.run(
        package_root,
        [],
        process_runner=fake_run,
        process_starter=_successful_start_process(process_calls),
    )

    assert exit_code == 0
    assert "http://127.0.0.1:49152" in capsys.readouterr().out
    assert "http://127.0.0.1:49152" in (
        package_root / "logs" / "allure-open.log"
    ).read_text(encoding="utf-8")
    assert len(process_calls) == 1
    assert process_calls[0][1]["stdout"] == subprocess.PIPE
    assert process_calls[0][1]["stderr"] == subprocess.STDOUT
