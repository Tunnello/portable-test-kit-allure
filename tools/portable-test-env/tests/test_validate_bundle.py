import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


PORTABLE_TEST_ENV = Path(__file__).resolve().parents[1]
VALIDATOR = PORTABLE_TEST_ENV / "validate-bundle.ps1"


def _powershell_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["PSModulePath"] = os.pathsep.join(
        [
            str(Path.home() / "Documents" / "WindowsPowerShell" / "Modules"),
            str(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "WindowsPowerShell" / "Modules"),
            str(
                Path(os.environ.get("SystemRoot", r"C:\Windows"))
                / "System32"
                / "WindowsPowerShell"
                / "v1.0"
                / "Modules"
            ),
        ]
    )
    return environment


def _create_validator_package(package_root: Path) -> None:
    lock_content = "pytest==8.3.2\nallure-pytest==2.16.2\n"
    manifest = {
        "schema_version": 1,
        "target": {"os": "windows", "architecture": "x64"},
        "runtime": {
            "python_version": "3.13.18",
            "package_python_path": "python/python.exe",
        },
        "dependencies": {
            "requirements_lock": "requirements.lock",
            "requirements_lock_sha256": "",
            "requirements": ["pytest==8.3.2", "allure-pytest==2.16.2"],
        },
        "allure": {
            "version": "2.46.1",
            "archive_name": "allure-2.46.1.zip",
            "archive_url": "https://github.com/allure-framework/allure2/releases/download/2.46.1/allure-2.46.1.zip",
            "package_path": "allure",
            "executable_path": "allure/bin/allure.bat",
            "archive_sha256": "d25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f",
            "license": "Apache-2.0",
            "license_url": "https://github.com/allure-framework/allure2/blob/2.46.1/LICENSE",
        },
        "java_runtime": {
            "version": "21.0.12.1+1",
            "archive_name": "OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip",
            "archive_url": "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip",
            "package_path": "java",
            "executable_path": "java/bin/java.exe",
            "archive_sha256": "d35f31e712f0fcf6ac5a093edc90204fbff22f720ba3950bd09d331d5e621636",
            "license": "GPL-2.0-with-classpath-exception",
            "license_url": "https://github.com/adoptium/temurin21-binaries/blob/jdk-21.0.12.1%2B1/LICENSE",
        },
    }
    package_root.mkdir(parents=True)
    (package_root / "bundle-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )
    (package_root / "requirements.lock").write_text(lock_content, encoding="utf-8")
    manifest["dependencies"]["requirements_lock_sha256"] = hashlib.sha256(
        (package_root / "requirements.lock").read_bytes()
    ).hexdigest()
    (package_root / "bundle-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )
    for relative_path in (
        "python/python.exe",
        "run-tests.cmd",
        "run_tests.py",
        "validate-bundle.ps1",
        "README.md",
        "THIRD_PARTY_NOTICES.md",
        "tests/conftest.py",
        "tests/test_public_examples.py",
        "allure/bin/allure.bat",
        "java/bin/java.exe",
    ):
        file_path = package_root / relative_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.touch()
    (package_root / "logs").mkdir()
    (package_root / "allure-results").mkdir()


def _run_validator(package_root: Path) -> subprocess.CompletedProcess[str]:
    powershell = shutil.which("powershell.exe")
    assert powershell is not None, "Windows PowerShell is required to test the bundle validator"
    return subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(VALIDATOR),
            "-PackageDirectory",
            str(package_root),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
        env=_powershell_environment(),
    )


def test_validator_defaults_to_its_script_directory() -> None:
    powershell = shutil.which("powershell.exe")
    assert powershell is not None, "Windows PowerShell is required to test the bundle validator"
    completed = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(VALIDATOR),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
        env=_powershell_environment(),
    )

    assert completed.returncode != 0
    assert "dependencies" in completed.stdout + completed.stderr


def test_validator_reports_missing_bundle_manifest(tmp_path: Path) -> None:
    powershell = shutil.which("powershell.exe")
    assert powershell is not None, "Windows PowerShell is required to test the bundle validator"
    completed = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(VALIDATOR),
            "-PackageDirectory",
            str(tmp_path),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
        env=_powershell_environment(),
    )

    assert completed.returncode != 0
    assert "bundle-manifest.json" in completed.stdout + completed.stderr


def test_validator_reports_missing_allure_cli(tmp_path: Path) -> None:
    package_root = tmp_path / "bundle"
    _create_validator_package(package_root)
    (package_root / "allure/bin/allure.bat").unlink()

    completed = _run_validator(package_root)

    assert completed.returncode != 0
    assert "allure\\bin\\allure.bat" in completed.stdout + completed.stderr


def test_validator_reports_missing_bundled_java(tmp_path: Path) -> None:
    package_root = tmp_path / "bundle"
    _create_validator_package(package_root)
    (package_root / "java/bin/java.exe").unlink()

    completed = _run_validator(package_root)

    assert completed.returncode != 0
    assert "java\\bin\\java.exe" in completed.stdout + completed.stderr
