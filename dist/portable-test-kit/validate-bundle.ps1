[CmdletBinding()]
param(
    [string]$PackageDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        & $Executable @Arguments
    }
    else {
        Push-Location -LiteralPath $WorkingDirectory
        try {
            & $Executable @Arguments
        }
        finally {
            Pop-Location
        }
    }
    $processExitCode = $LASTEXITCODE
    if ($processExitCode -ne 0) {
        throw "$Description failed with exit code $processExitCode"
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($PackageDirectory)) {
        $PackageDirectory = $PSScriptRoot
    }
    $packageRoot = [System.IO.Path]::GetFullPath($PackageDirectory)
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "Package directory does not exist: $packageRoot"
    }

    $manifestPath = Join-Path $packageRoot 'bundle-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required package file is missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema_version -ne 1) {
        throw 'Bundle manifest schema_version must be 1'
    }
    if ($manifest.target.os -ne 'windows' -or $manifest.target.architecture -ne 'x64') {
        throw 'Bundle manifest target must be Windows x64'
    }
    if ($null -eq $manifest.dependencies -or
        [string]::IsNullOrWhiteSpace($manifest.dependencies.requirements_lock) -or
        [string]::IsNullOrWhiteSpace($manifest.dependencies.requirements_lock_sha256)) {
        throw 'bundle-manifest.json is missing packaged dependencies metadata'
    }

    $pythonPath = Join-Path $packageRoot ($manifest.runtime.package_python_path -replace '/', '\')
    $lockPath = Join-Path $packageRoot $manifest.dependencies.requirements_lock
    $requiredFiles = @(
        $pythonPath,
        $lockPath,
        (Join-Path $packageRoot 'run-tests.cmd'),
        (Join-Path $packageRoot 'validate-bundle.ps1'),
        (Join-Path $packageRoot 'README.md'),
        (Join-Path $packageRoot 'tests\conftest.py'),
        (Join-Path $packageRoot 'tests\test_public_examples.py')
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required package file is missing: $requiredFile"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'logs') -PathType Container)) {
        throw "Required package directory is missing: $(Join-Path $packageRoot 'logs')"
    }

    $actualLockHash = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualLockHash -ne $manifest.dependencies.requirements_lock_sha256.ToLowerInvariant()) {
        throw "requirements.lock SHA-256 mismatch; expected $($manifest.dependencies.requirements_lock_sha256), got $actualLockHash"
    }

    $pythonVersion = (& $pythonPath -c 'import platform; print(platform.python_version())').Trim()
    if ($LASTEXITCODE -ne 0 -or $pythonVersion -ne $manifest.runtime.python_version) {
        throw "Packaged Python version mismatch; expected $($manifest.runtime.python_version), got $pythonVersion"
    }

    $pytestRequirement = @($manifest.dependencies.requirements | Where-Object { $_ -match '^pytest==' }) |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($pytestRequirement)) {
        throw 'Bundle manifest does not pin pytest'
    }
    $expectedPytestVersion = $pytestRequirement -replace '^pytest==', ''
    $pytestVersionOutput = (& $pythonPath -m pytest --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $pytestVersionOutput -notmatch [regex]::Escape("pytest $expectedPytestVersion")) {
        throw "Packaged pytest version mismatch; expected $expectedPytestVersion, got $pytestVersionOutput"
    }

    Invoke-CheckedProcess -Executable $pythonPath -Arguments @(
        '-B', '-m', 'pytest', '--collect-only', '-q', 'tests'
    ) -Description 'Collecting packaged tests' -WorkingDirectory $packageRoot

    Write-Output "Portable test package is valid: $packageRoot"
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
