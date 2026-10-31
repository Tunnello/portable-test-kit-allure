import json
import os
import shutil
import subprocess
from pathlib import Path


PORTABLE_TEST_ENV = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = PORTABLE_TEST_ENV / "build.ps1"
VALIDATOR_SCRIPT = PORTABLE_TEST_ENV / "validate-bundle.ps1"


def _run_builder(*arguments: str) -> subprocess.CompletedProcess[str]:
    powershell = shutil.which("powershell.exe")
    assert powershell is not None, "Windows PowerShell is required to test the builder"
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
    return subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(BUILD_SCRIPT),
            *arguments,
        ],
        capture_output=True,
        text=True,
        env=environment,
        check=False,
        timeout=30,
    )


def _copy_project(tmp_path: Path) -> Path:
    project_root = tmp_path / "portable-test-env"
    shutil.copytree(
        PORTABLE_TEST_ENV,
        project_root,
        ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache"),
    )
    return project_root


def _write_manifest(project_root: Path, manifest: dict[str, object]) -> None:
    (project_root / "bundle-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )


def test_builder_validate_only_accepts_complete_inputs() -> None:
    completed = _run_builder("-ProjectRoot", str(PORTABLE_TEST_ENV), "-ValidateOnly")

    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "Input validation passed" in completed.stdout


def test_builder_defaults_project_root_to_script_directory() -> None:
    completed = _run_builder("-ValidateOnly")

    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "Input validation passed" in completed.stdout


def test_builder_validate_only_reports_missing_manifest(tmp_path: Path) -> None:
    completed = _run_builder("-ProjectRoot", str(tmp_path), "-ValidateOnly")

    assert completed.returncode != 0
    assert "bundle-manifest.json" in completed.stdout + completed.stderr


def test_manifest_pins_allure_cli_and_portable_jre() -> None:
    manifest_path = PORTABLE_TEST_ENV / "bundle-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    assert manifest["allure"] == {
        "version": "2.46.1",
        "archive_name": "allure-2.46.1.zip",
        "archive_url": "https://github.com/allure-framework/allure2/releases/download/2.46.1/allure-2.46.1.zip",
        "archive_sha256": "d25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f",
        "archive_path": "allure-2.46.1",
        "package_path": "allure",
        "executable_path": "allure/bin/allure.bat",
        "license": "Apache-2.0",
        "license_url": "https://github.com/allure-framework/allure2/blob/2.46.1/LICENSE",
    }
    assert manifest["java_runtime"] == {
        "distribution": "Eclipse Temurin",
        "version": "21.0.12.1+1",
        "archive_name": "OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip",
        "archive_url": "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip",
        "archive_sha256": "d35f31e712f0fcf6ac5a093edc90204fbff22f720ba3950bd09d331d5e621636",
        "archive_path": "jdk-21.0.12.1+1-jre",
        "package_path": "java",
        "executable_path": "java/bin/java.exe",
        "license": "GPL-2.0-with-classpath-exception",
        "license_url": "https://github.com/adoptium/temurin21-binaries/blob/jdk-21.0.12.1%2B1/LICENSE",
    }


def test_requirements_include_pinned_allure_pytest() -> None:
    requirements = (PORTABLE_TEST_ENV / "requirements.in").read_text(encoding="utf-8")

    assert "pytest==8.3.2" in requirements
    assert "allure-pytest==2.16.2" in requirements


def test_builder_validate_only_requires_allure_metadata(tmp_path: Path) -> None:
    project_root = _copy_project(tmp_path)
    manifest_path = project_root / "bundle-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    del manifest["allure"]
    _write_manifest(project_root, manifest)

    completed = _run_builder("-ProjectRoot", str(project_root), "-ValidateOnly")

    assert completed.returncode != 0
    assert "allure" in completed.stdout + completed.stderr


def test_builder_validate_only_rejects_invalid_java_runtime_metadata(
    tmp_path: Path,
) -> None:
    project_root = _copy_project(tmp_path)
    manifest_path = project_root / "bundle-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["java_runtime"]["archive_url"] = "http://example.invalid/runtime.zip"
    _write_manifest(project_root, manifest)

    completed = _run_builder("-ProjectRoot", str(project_root), "-ValidateOnly")

    assert completed.returncode != 0
    assert "java_runtime.archive_url" in completed.stdout + completed.stderr


def test_builder_validate_only_rejects_invalid_allure_archive_hash(
    tmp_path: Path,
) -> None:
    project_root = _copy_project(tmp_path)
    manifest_path = project_root / "bundle-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["allure"]["archive_sha256"] = "not-a-sha256"
    _write_manifest(project_root, manifest)

    completed = _run_builder("-ProjectRoot", str(project_root), "-ValidateOnly")

    assert completed.returncode != 0
    assert "allure.archive_sha256" in completed.stdout + completed.stderr


def test_builder_validate_only_rejects_missing_report_runner(tmp_path: Path) -> None:
    project_root = _copy_project(tmp_path)
    (project_root / "run_tests.py").unlink()

    completed = _run_builder("-ProjectRoot", str(project_root), "-ValidateOnly")

    assert completed.returncode != 0
    assert "run_tests.py" in completed.stdout + completed.stderr


def test_builder_validate_only_hash_checks_provided_artifacts(tmp_path: Path) -> None:
    project_root = _copy_project(tmp_path)
    bad_archive = tmp_path / "allure.zip"
    bad_archive.write_bytes(b"not the pinned archive")

    completed = _run_builder(
        "-ProjectRoot",
        str(project_root),
        "-AllureArchivePath",
        str(bad_archive),
        "-ValidateOnly",
    )

    assert completed.returncode != 0
    assert "Allure CLI archive SHA-256 mismatch" in completed.stdout + completed.stderr


def test_java_version_probes_merge_stderr_before_capturing_output() -> None:
    for script_path in (BUILD_SCRIPT, VALIDATOR_SCRIPT):
        lines = script_path.read_text(encoding="utf-8").splitlines()
        java_probe = next(
            (line for line in lines if "$javaVersionOutput =" in line),
            "",
        )

        assert "cmd.exe /d /c" in java_probe, script_path.name
