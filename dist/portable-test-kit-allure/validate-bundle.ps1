[CmdletBinding()]
param(
    [string]$PackageDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PackagePath {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $normalizedPath = $RelativePath.Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        $normalizedPath -match '(^|/)\.\.?(/|$)' -or
        $normalizedPath -match '^[A-Za-z]:') {
        throw "bundle-manifest.json $FieldName must be a package-relative path"
    }

    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $PackageRoot $RelativePath))
    $rootPrefix = $PackageRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "bundle-manifest.json $FieldName escapes the package directory"
    }
    return $resolvedPath
}

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

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Could not parse bundle-manifest.json: $($_.Exception.Message)"
    }
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

    foreach ($artifactName in @('allure', 'java_runtime')) {
        $artifact = $manifest.$artifactName
        if ($null -eq $artifact) {
            throw "bundle-manifest.json is missing $artifactName metadata"
        }
        foreach ($fieldName in @(
                'version',
                'archive_name',
                'archive_url',
                'archive_sha256',
                'package_path',
                'executable_path',
                'license',
                'license_url'
            )) {
            if ([string]::IsNullOrWhiteSpace([string]$artifact.$fieldName)) {
                throw "bundle-manifest.json is missing $artifactName.$fieldName"
            }
        }
        if ($artifact.archive_url -notmatch '^https://' -or
            $artifact.license_url -notmatch '^https://') {
            throw "bundle-manifest.json $artifactName URLs must use HTTPS"
        }
        if ($artifact.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "bundle-manifest.json $artifactName.archive_sha256 must contain 64 hexadecimal characters"
        }
    }

    $pythonPath = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.runtime.package_python_path `
        -FieldName 'runtime.package_python_path'
    $lockPath = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.dependencies.requirements_lock `
        -FieldName 'dependencies.requirements_lock'
    $allurePath = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.allure.executable_path `
        -FieldName 'allure.executable_path'
    $allureRoot = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.allure.package_path `
        -FieldName 'allure.package_path'
    $javaPath = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.java_runtime.executable_path `
        -FieldName 'java_runtime.executable_path'
    $javaHome = Resolve-PackagePath `
        -PackageRoot $packageRoot `
        -RelativePath $manifest.java_runtime.package_path `
        -FieldName 'java_runtime.package_path'
    if (-not $allurePath.StartsWith(
            $allureRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'bundle-manifest.json allure.executable_path must be inside allure.package_path'
    }
    if (-not $javaPath.StartsWith(
            $javaHome.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'bundle-manifest.json java_runtime.executable_path must be inside java_runtime.package_path'
    }
    $requiredFiles = @(
        $pythonPath,
        $lockPath,
        $allurePath,
        $javaPath,
        (Join-Path $packageRoot 'run-tests.cmd'),
        (Join-Path $packageRoot 'run_tests.py'),
        (Join-Path $packageRoot 'validate-bundle.ps1'),
        (Join-Path $packageRoot 'README.md'),
        (Join-Path $packageRoot 'THIRD_PARTY_NOTICES.md'),
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
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'allure-results') -PathType Container)) {
        throw "Required package directory is missing: $(Join-Path $packageRoot 'allure-results')"
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

    $allurePytestRequirement = @($manifest.dependencies.requirements |
        Where-Object { $_ -match '^allure-pytest==' }) |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($allurePytestRequirement)) {
        throw 'Bundle manifest does not pin allure-pytest'
    }
    $expectedAllurePytestVersion = $allurePytestRequirement -replace '^allure-pytest==', ''
    $allurePytestVersionOutput = (& $pythonPath -c "from importlib.metadata import version; print(version('allure-pytest'))" 2>&1 |
        Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $allurePytestVersionOutput -ne $expectedAllurePytestVersion) {
        throw "Packaged allure-pytest version mismatch; expected $expectedAllurePytestVersion, got $allurePytestVersionOutput"
    }

    $javaVersionOutput = (& cmd.exe /d /c "`"$javaPath`" -version 2>&1" | Out-String).Trim()
    $expectedJavaVersion = ($manifest.java_runtime.version -split '\+')[0]
    if ($LASTEXITCODE -ne 0 -or
        $javaVersionOutput -notmatch [regex]::Escape($expectedJavaVersion)) {
        throw "Packaged Java runtime version mismatch; expected $expectedJavaVersion, got $javaVersionOutput"
    }

    $previousJavaHome = $env:JAVA_HOME
    $previousPath = $env:PATH
    try {
        $env:JAVA_HOME = $javaHome
        $env:PATH = (Join-Path $javaHome 'bin') + [System.IO.Path]::PathSeparator + $previousPath
        $allureVersionOutput = (& $allurePath --version 2>&1 | Out-String).Trim()
        $allureExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousJavaHome) {
            Remove-Item Env:\JAVA_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:JAVA_HOME = $previousJavaHome
        }
        $env:PATH = $previousPath
    }
    if ($allureExitCode -ne 0 -or
        $allureVersionOutput -notmatch [regex]::Escape($manifest.allure.version)) {
        throw "Packaged Allure CLI version mismatch; expected $($manifest.allure.version), got $allureVersionOutput"
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
