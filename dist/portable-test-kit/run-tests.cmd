@echo off
setlocal

set "PACKAGE_ROOT=%~dp0"
set "PYTHON=%PACKAGE_ROOT%python\python.exe"
set "LOG_DIR=%PACKAGE_ROOT%logs"
set "LOG_FILE=%LOG_DIR%\pytest.log"

if not exist "%PYTHON%" (
    >&2 echo ERROR: Packaged Python runtime not found: "%PYTHON%"
    exit /b 2
)

if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%" >nul 2>&1
    if errorlevel 1 (
        >&2 echo ERROR: Could not create package log directory: "%LOG_DIR%"
        exit /b 3
    )
)

pushd "%PACKAGE_ROOT%" >nul
if errorlevel 1 (
    >&2 echo ERROR: Could not enter package directory: "%PACKAGE_ROOT%"
    exit /b 4
)

"%PYTHON%" -B -m pytest "tests" %* >"%LOG_FILE%" 2>&1
set "TEST_EXIT=%ERRORLEVEL%"
popd
type "%LOG_FILE%"
exit /b %TEST_EXIT%
