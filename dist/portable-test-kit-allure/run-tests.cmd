@echo off
setlocal

set "PACKAGE_ROOT=%~dp0"
set "PYTHON=%PACKAGE_ROOT%python\python.exe"
set "REPORT_RUNNER=%PACKAGE_ROOT%run_tests.py"
set "LOG_DIR=%PACKAGE_ROOT%logs"

if not exist "%PYTHON%" (
    >&2 echo ERROR: Packaged Python runtime not found: "%PYTHON%"
    exit /b 2
)

if not exist "%REPORT_RUNNER%" (
    >&2 echo ERROR: Packaged report runner not found: "%REPORT_RUNNER%"
    exit /b 3
)

if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%" >nul 2>&1
    if errorlevel 1 (
        >&2 echo ERROR: Could not create package log directory: "%LOG_DIR%"
        exit /b 4
    )
)

pushd "%PACKAGE_ROOT%" >nul
if errorlevel 1 (
    >&2 echo ERROR: Could not enter package directory: "%PACKAGE_ROOT%"
    exit /b 5
)

"%PYTHON%" -B "%REPORT_RUNNER%" %*
set "RUNNER_EXIT=%ERRORLEVEL%"
popd
exit /b %RUNNER_EXIT%
