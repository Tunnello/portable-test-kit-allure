import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from collections.abc import Callable, Sequence


REPORT_FAILURE_EXIT_CODE = 2
ProcessRunner = Callable[..., subprocess.CompletedProcess[str]]
ProcessStarter = Callable[..., subprocess.Popen[str]]


class RunnerError(Exception):
    pass


def _package_path(package_root: Path, relative_path: object, label: str) -> Path:
    if not isinstance(relative_path, str) or not relative_path.strip():
        raise RunnerError(f"Package manifest is missing {label}")

    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise RunnerError(f"Package manifest {label} must be a package-relative path")

    resolved = (package_root / relative).resolve()
    if not resolved.is_relative_to(package_root):
        raise RunnerError(f"Package manifest {label} escapes the package directory")
    if not resolved.is_file():
        raise RunnerError(f"Required packaged file was not found: {resolved}")
    return resolved


def _load_runtime_paths(package_root: Path) -> tuple[Path, Path, Path]:
    manifest_path = package_root / "bundle-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RunnerError(f"Could not read package manifest {manifest_path}: {exc}") from exc
    if not isinstance(manifest, dict):
        raise RunnerError("Package manifest must contain a JSON object")

    try:
        runtime = manifest["runtime"]
        allure = manifest["allure"]
        java_runtime = manifest["java_runtime"]
    except KeyError as exc:
        raise RunnerError(f"Package manifest is missing {exc.args[0]} metadata") from exc
    if not all(isinstance(item, dict) for item in (runtime, allure, java_runtime)):
        raise RunnerError("Package manifest runtime, allure, and java_runtime must be objects")

    python_executable = _package_path(
        package_root,
        runtime.get("package_python_path"),
        "runtime.package_python_path",
    )
    allure_executable = _package_path(
        package_root,
        allure.get("executable_path"),
        "allure.executable_path",
    )
    java_executable = _package_path(
        package_root,
        java_runtime.get("executable_path"),
        "java_runtime.executable_path",
    )
    java_home_value = java_runtime.get("package_path")
    if not isinstance(java_home_value, str) or not java_home_value.strip():
        raise RunnerError("Package manifest is missing java_runtime.package_path")
    java_home = (package_root / java_home_value).resolve()
    if not java_home.is_relative_to(package_root) or not java_home.is_dir():
        raise RunnerError("Package manifest java_runtime.package_path must be a packaged directory")
    if not java_executable.is_relative_to(java_home):
        raise RunnerError("Package manifest java_runtime.executable_path must be inside package_path")
    return python_executable, allure_executable, java_home


def _remove_managed_output(path: Path) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def _write_process_log(
    log_path: Path,
    result: subprocess.CompletedProcess[str],
) -> None:
    stdout = result.stdout or ""
    stderr = result.stderr or ""
    log_path.write_text(
        stdout + (f"\n[stderr]\n{stderr}" if stderr else ""),
        encoding="utf-8",
    )
    if stdout:
        print(stdout, end="" if stdout.endswith("\n") else "\n")
    if stderr:
        print(stderr, file=sys.stderr, end="" if stderr.endswith("\n") else "\n")


def _run_allure_command(
    allure_executable: Path,
    arguments: Sequence[str],
    package_root: Path,
    environment: dict[str, str],
    process_runner: ProcessRunner,
) -> subprocess.CompletedProcess[str]:
    command = subprocess.list2cmdline([str(allure_executable), *arguments])
    return process_runner(
        command,
        cwd=str(package_root),
        env=environment,
        shell=True,
        capture_output=True,
        text=True,
        check=False,
    )


def _run_allure_open(
    allure_executable: Path,
    report_directory: Path,
    package_root: Path,
    environment: dict[str, str],
    log_path: Path,
    process_starter: ProcessStarter,
) -> subprocess.CompletedProcess[str]:
    command = subprocess.list2cmdline(
        [
            str(allure_executable),
            "open",
            str(report_directory),
            "--host",
            "127.0.0.1",
        ]
    )
    with log_path.open("w", encoding="utf-8") as log_file:
        process = process_starter(
            command,
            cwd=str(package_root),
            env=environment,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        if process.stdout is None:
            raise subprocess.SubprocessError("Allure report server output was not captured")
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            log_file.write(line)
            log_file.flush()
        return subprocess.CompletedProcess(command, process.wait(), None, None)


def run(
    package_root: Path,
    pytest_args: Sequence[str],
    process_runner: ProcessRunner = subprocess.run,
    process_starter: ProcessStarter = subprocess.Popen,
) -> int:
    package_root = package_root.resolve()
    if not package_root.is_dir():
        raise RunnerError(f"Package directory does not exist: {package_root}")

    if any(arg == "--alluredir" or arg.startswith("--alluredir=") for arg in pytest_args):
        raise RunnerError("Do not pass --alluredir; the package runner manages the Allure results directory")

    python_executable, allure_executable, java_home = _load_runtime_paths(package_root)
    tests_directory = package_root / "tests"
    if not tests_directory.is_dir():
        raise RunnerError(f"Packaged test directory was not found: {tests_directory}")

    results_directory = package_root / "allure-results"
    report_directory = package_root / "allure-report"
    log_directory = package_root / "logs"
    log_directory.mkdir(parents=True, exist_ok=True)
    _remove_managed_output(results_directory)
    _remove_managed_output(report_directory)
    results_directory.mkdir()

    pytest_command = [
        str(python_executable),
        "-B",
        "-m",
        "pytest",
        "tests",
        *pytest_args,
        "--alluredir",
        str(results_directory),
    ]
    try:
        pytest_result = process_runner(
            pytest_command,
            cwd=str(package_root),
            capture_output=True,
            text=True,
            check=False,
        )
        _write_process_log(log_directory / "pytest.log", pytest_result)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: Could not run packaged pytest: {exc}", file=sys.stderr)
        return REPORT_FAILURE_EXIT_CODE

    pytest_exit_code = pytest_result.returncode
    if not any(path.is_file() for path in results_directory.rglob("*")):
        print(
            f"ERROR: Pytest produced no Allure result files in {results_directory}; "
            "no report was opened.",
            file=sys.stderr,
        )
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE

    allure_environment = os.environ.copy()
    java_bin = java_home / "bin"
    allure_environment["JAVA_HOME"] = str(java_home)
    allure_environment["PATH"] = str(java_bin) + os.pathsep + allure_environment.get("PATH", "")

    try:
        generate_result = _run_allure_command(
            allure_executable,
            ["generate", str(results_directory), "--clean", "-o", str(report_directory)],
            package_root,
            allure_environment,
            process_runner,
        )
        _write_process_log(log_directory / "allure-generate.log", generate_result)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: Could not generate the Allure report: {exc}", file=sys.stderr)
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE

    if generate_result.returncode != 0:
        print(
            f"ERROR: Allure report generation failed with exit code {generate_result.returncode}",
            file=sys.stderr,
        )
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE
    if not (report_directory / "index.html").is_file():
        print(
            f"ERROR: Allure did not create the report entry point: {report_directory / 'index.html'}",
            file=sys.stderr,
        )
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE

    try:
        print("Starting Allure report server; waiting for its URL...", flush=True)
        open_result = _run_allure_open(
            allure_executable,
            report_directory,
            package_root,
            allure_environment,
            log_directory / "allure-open.log",
            process_starter,
        )
    except KeyboardInterrupt:
        print("Allure report server stopped by user.", file=sys.stderr)
        return pytest_exit_code
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: Could not open the Allure report: {exc}", file=sys.stderr)
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE

    if open_result.returncode != 0:
        print(
            f"ERROR: Allure report server exited with code {open_result.returncode}",
            file=sys.stderr,
        )
        return pytest_exit_code or REPORT_FAILURE_EXIT_CODE
    return pytest_exit_code


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        return run(Path(__file__).resolve().parent, arguments)
    except RunnerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return REPORT_FAILURE_EXIT_CODE


if __name__ == "__main__":
    raise SystemExit(main())
