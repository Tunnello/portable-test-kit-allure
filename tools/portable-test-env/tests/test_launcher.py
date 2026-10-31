import shutil
import subprocess
from pathlib import Path


PORTABLE_TEST_ENV = Path(__file__).resolve().parents[1]
LAUNCHER = PORTABLE_TEST_ENV / "run-tests.cmd"


def test_launcher_reports_missing_packaged_python() -> None:
    command_processor = shutil.which("cmd.exe")
    assert command_processor is not None, "Windows command processor is required"
    completed = subprocess.run(
        [command_processor, "/d", "/c", str(LAUNCHER)],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )

    assert completed.returncode != 0
    assert "python\\python.exe" in completed.stdout + completed.stderr


def test_launcher_reports_missing_report_runner(tmp_path: Path) -> None:
    command_processor = shutil.which("cmd.exe")
    assert command_processor is not None, "Windows command processor is required"
    package_root = tmp_path / "package with spaces"
    python_directory = package_root / "python"
    python_directory.mkdir(parents=True)
    (python_directory / "python.exe").touch()
    launcher = package_root / "run-tests.cmd"
    shutil.copy2(LAUNCHER, launcher)

    completed = subprocess.run(
        [command_processor, "/d", "/c", str(launcher)],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )

    assert completed.returncode != 0
    assert "run_tests.py" in completed.stdout + completed.stderr
