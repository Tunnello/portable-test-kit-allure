[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$RuntimeArchivePath,
    [string]$WheelhousePath,
    [string]$AllureArchivePath,
    [string]$JavaRuntimeArchivePath,
    [switch]$ValidateOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortableTestInputs {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Project root does not exist: $resolvedRoot"
    }

    $manifestPath = Join-Path $resolvedRoot 'bundle-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required input is missing: $manifestPath"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Could not parse bundle-manifest.json: $($_.Exception.Message)"
    }

    if ($manifest.schema_version -ne 1) {
        throw 'bundle-manifest.json schema_version must be 1'
    }
    if ($manifest.target.os -ne 'windows' -or $manifest.target.architecture -ne 'x64') {
        throw 'bundle-manifest.json target must be Windows x64'
    }
    if ([string]::IsNullOrWhiteSpace($manifest.runtime.archive_url) -or
        $manifest.runtime.archive_url -notmatch '^https://') {
        throw 'bundle-manifest.json runtime.archive_url must be an HTTPS URL'
    }
    if ($manifest.runtime.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'bundle-manifest.json runtime.archive_sha256 must contain 64 hexadecimal characters'
    }
    if ([string]::IsNullOrWhiteSpace($manifest.runtime.archive_python_path) -or
        [string]::IsNullOrWhiteSpace($manifest.runtime.package_python_path)) {
        throw 'bundle-manifest.json must define runtime archive and package Python paths'
    }

    foreach ($artifactName in @('allure', 'java_runtime')) {
        $artifact = $manifest.$artifactName
        if ($null -eq $artifact) {
            throw "bundle-manifest.json must define $artifactName metadata"
        }

        foreach ($fieldName in @(
                'version',
                'archive_name',
                'archive_url',
                'archive_sha256',
                'archive_path',
                'package_path',
                'executable_path',
                'license',
                'license_url'
            )) {
            if ([string]::IsNullOrWhiteSpace([string]$artifact.$fieldName)) {
                throw "bundle-manifest.json $artifactName.$fieldName must be provided"
            }
        }
        if ($artifact.archive_url -notmatch '^https://') {
            throw "bundle-manifest.json $artifactName.archive_url must be an HTTPS URL"
        }
        if ($artifact.license_url -notmatch '^https://') {
            throw "bundle-manifest.json $artifactName.license_url must be an HTTPS URL"
        }
        if ($artifact.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "bundle-manifest.json $artifactName.archive_sha256 must contain 64 hexadecimal characters"
        }

        foreach ($pathField in @('archive_path', 'package_path', 'executable_path')) {
            $relativePath = [string]$artifact.$pathField
            $normalizedPath = $relativePath.Replace('\', '/')
            if ([System.IO.Path]::IsPathRooted($relativePath) -or
                $normalizedPath -match '(^|/)\.\.?(/|$)' -or
                $normalizedPath -match '^[A-Za-z]:') {
                throw "bundle-manifest.json $artifactName.$pathField must stay within its package directory"
            }
        }

        $packagePrefix = ([string]$artifact.package_path).TrimEnd('/') + '/'
        if (-not ([string]$artifact.executable_path).StartsWith(
                $packagePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "bundle-manifest.json $artifactName.executable_path must be inside package_path"
        }
    }

    $lockPath = Join-Path $resolvedRoot $manifest.requirements_lock
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw "Required dependency lock file is missing: $lockPath"
    }

    if ($null -eq $manifest.tests -or $manifest.tests.Count -eq 0) {
        throw 'bundle-manifest.json must list at least one test file'
    }
    foreach ($testFile in $manifest.tests) {
        $testPath = Join-Path $resolvedRoot ($testFile -replace '/', '\')
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
            throw "Required test file is missing: $testPath"
        }
    }

    $readmePath = Join-Path $resolvedRoot 'README.md'
    if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        throw "Required user guide is missing: $readmePath"
    }

    $buildScriptPath = Join-Path $resolvedRoot 'build.ps1'
    if (-not (Test-Path -LiteralPath $buildScriptPath -PathType Leaf)) {
        throw "Required build script is missing: $buildScriptPath"
    }

    $launcherPath = Join-Path $resolvedRoot 'run-tests.cmd'
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "Required test launcher is missing: $launcherPath"
    }

    $validatorPath = Join-Path $resolvedRoot 'validate-bundle.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
        throw "Required bundle validator is missing: $validatorPath"
    }

    $runtimeArchive = $null
    if (-not [string]::IsNullOrWhiteSpace($RuntimeArchivePath)) {
        $runtimeArchive = [System.IO.Path]::GetFullPath($RuntimeArchivePath)
        if (-not (Test-Path -LiteralPath $runtimeArchive -PathType Leaf)) {
            throw "Runtime archive was not found: $runtimeArchive"
        }
    }

    $wheelhouse = $null
    if (-not [string]::IsNullOrWhiteSpace($WheelhousePath)) {
        $wheelhouse = [System.IO.Path]::GetFullPath($WheelhousePath)
        if (-not (Test-Path -LiteralPath $wheelhouse -PathType Container)) {
            throw "Wheelhouse directory was not found: $wheelhouse"
        }
    }

    $allureArchive = $null
    if (-not [string]::IsNullOrWhiteSpace($AllureArchivePath)) {
        $allureArchive = [System.IO.Path]::GetFullPath($AllureArchivePath)
        if (-not (Test-Path -LiteralPath $allureArchive -PathType Leaf)) {
            throw "Allure archive was not found: $allureArchive"
        }
    }

    $javaRuntimeArchive = $null
    if (-not [string]::IsNullOrWhiteSpace($JavaRuntimeArchivePath)) {
        $javaRuntimeArchive = [System.IO.Path]::GetFullPath($JavaRuntimeArchivePath)
        if (-not (Test-Path -LiteralPath $javaRuntimeArchive -PathType Leaf)) {
            throw "Java runtime archive was not found: $javaRuntimeArchive"
        }
    }

    $thirdPartyNoticesPath = Join-Path $resolvedRoot 'THIRD_PARTY_NOTICES.md'
    if (-not (Test-Path -LiteralPath $thirdPartyNoticesPath -PathType Leaf)) {
        throw "Required third-party notices file is missing: $thirdPartyNoticesPath"
    }

    $reportRunnerPath = Join-Path $resolvedRoot 'run_tests.py'
    if (-not (Test-Path -LiteralPath $reportRunnerPath -PathType Leaf)) {
        throw "Required report runner is missing: $reportRunnerPath"
    }

    [pscustomobject]@{
        Root = $resolvedRoot
        ManifestPath = $manifestPath
        Manifest = $manifest
        LockPath = $lockPath
        Tests = @($manifest.tests | ForEach-Object {
            Join-Path $resolvedRoot ($_ -replace '/', '\')
        })
        ReadmePath = $readmePath
        BuildScriptPath = $buildScriptPath
        LauncherPath = $launcherPath
        ValidatorPath = $validatorPath
        RuntimeArchivePath = $runtimeArchive
        WheelhousePath = $wheelhouse
        AllureArchivePath = $allureArchive
        JavaRuntimeArchivePath = $javaRuntimeArchive
        ThirdPartyNoticesPath = $thirdPartyNoticesPath
        ReportRunnerPath = $reportRunnerPath
    }
}

function Get-VerifiedArchive {
    param(
        [string]$ProvidedPath,
        [Parameter(Mandatory = $true)][string]$ArchiveName,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        Copy-Item -LiteralPath $ProvidedPath -Destination $DestinationPath
    }
    else {
        Invoke-WebRequest -Uri $Uri -OutFile $DestinationPath -UseBasicParsing
    }

    $actualHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $ExpectedSha256.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "$Description SHA-256 mismatch; expected $expectedHash, got $actualHash"
    }
    return $DestinationPath
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
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $ProjectRoot = $PSScriptRoot
    }
    $inputs = Get-PortableTestInputs -Root $ProjectRoot
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $OutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'dist\portable-test-kit-allure'))

    if ($ValidateOnly) {
        foreach ($archive in @(
                @{
                    Path = $inputs.RuntimeArchivePath
                    Sha256 = $inputs.Manifest.runtime.archive_sha256
                    Description = 'Python archive'
                },
                @{
                    Path = $inputs.AllureArchivePath
                    Sha256 = $inputs.Manifest.allure.archive_sha256
                    Description = 'Allure CLI archive'
                },
                @{
                    Path = $inputs.JavaRuntimeArchivePath
                    Sha256 = $inputs.Manifest.java_runtime.archive_sha256
                    Description = 'Java runtime archive'
                }
            )) {
            if ($null -ne $archive.Path) {
                $actualHash = (Get-FileHash -LiteralPath $archive.Path -Algorithm SHA256).Hash.ToLowerInvariant()
                $expectedHash = $archive.Sha256.ToLowerInvariant()
                if ($actualHash -ne $expectedHash) {
                    throw "$($archive.Description) SHA-256 mismatch; expected $expectedHash, got $actualHash"
                }
            }
        }
        Write-Output 'Input validation passed'
        exit 0
    }

    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'The portable test package must be built on Windows x64'
    }
    if ((Test-Path -LiteralPath $OutputDirectory) -and -not $Force) {
        throw "Output directory already exists; use -Force to replace it: $OutputDirectory"
    }

    $outputParent = Split-Path -Parent $OutputDirectory
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $buildId = [guid]::NewGuid().ToString('N')
    $tempRoot = Join-Path $env:TEMP "portable-test-env-build-$buildId"
    $stagingDirectory = Join-Path $outputParent ".portable-test-kit-staging-$buildId"
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

    try {
        $archivePath = Join-Path $tempRoot $inputs.Manifest.runtime.archive_name
        Get-VerifiedArchive `
            -ProvidedPath $inputs.RuntimeArchivePath `
            -ArchiveName $inputs.Manifest.runtime.archive_name `
            -Uri $inputs.Manifest.runtime.archive_url `
            -ExpectedSha256 $inputs.Manifest.runtime.archive_sha256 `
            -DestinationPath $archivePath `
            -Description 'Python archive' | Out-Null
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

        $extractDirectory = Join-Path $tempRoot 'runtime'
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDirectory
        $archivePythonPath = Join-Path $extractDirectory ($inputs.Manifest.runtime.archive_python_path -replace '/', '\')
        $pythonRelativePath = $inputs.Manifest.runtime.package_python_path -replace '/', '\'
        $pythonRelativeDirectory = Split-Path -Parent $pythonRelativePath
        $pythonDirectory = Join-Path $stagingDirectory $pythonRelativeDirectory
        New-Item -ItemType Directory -Path $pythonDirectory -Force | Out-Null
        Copy-Item -Path (Join-Path $archivePythonPath '*') -Destination $pythonDirectory -Recurse -Force

        $pythonExecutable = Join-Path $stagingDirectory $pythonRelativePath
        if (-not (Test-Path -LiteralPath $pythonExecutable -PathType Leaf)) {
            throw "Python runtime executable was not found in the archive: $pythonExecutable"
        }
        $pythonVersion = (& $pythonExecutable -c 'import platform; print(platform.python_version())').Trim()
        if ($LASTEXITCODE -ne 0 -or $pythonVersion -ne $inputs.Manifest.runtime.python_version) {
            throw "Python runtime version mismatch; expected $($inputs.Manifest.runtime.python_version), got $pythonVersion"
        }

        $allureArchive = Join-Path $tempRoot $inputs.Manifest.allure.archive_name
        Get-VerifiedArchive `
            -ProvidedPath $inputs.AllureArchivePath `
            -ArchiveName $inputs.Manifest.allure.archive_name `
            -Uri $inputs.Manifest.allure.archive_url `
            -ExpectedSha256 $inputs.Manifest.allure.archive_sha256 `
            -DestinationPath $allureArchive `
            -Description 'Allure CLI archive' | Out-Null
        $allureArchiveHash = (Get-FileHash -LiteralPath $allureArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        $allureExtractDirectory = Join-Path $tempRoot 'allure-runtime'
        Expand-Archive -LiteralPath $allureArchive -DestinationPath $allureExtractDirectory
        $allureArchiveRoot = Join-Path $allureExtractDirectory ($inputs.Manifest.allure.archive_path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $allureArchiveRoot -PathType Container)) {
            throw "Allure archive root was not found: $allureArchiveRoot"
        }
        $allurePackagePath = Join-Path $stagingDirectory ($inputs.Manifest.allure.package_path -replace '/', '\')
        New-Item -ItemType Directory -Path $allurePackagePath -Force | Out-Null
        Copy-Item -Path (Join-Path $allureArchiveRoot '*') -Destination $allurePackagePath -Recurse -Force
        $allureExecutable = Join-Path $stagingDirectory ($inputs.Manifest.allure.executable_path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $allureExecutable -PathType Leaf)) {
            throw "Allure CLI executable was not found in the archive: $allureExecutable"
        }

        $javaArchive = Join-Path $tempRoot $inputs.Manifest.java_runtime.archive_name
        Get-VerifiedArchive `
            -ProvidedPath $inputs.JavaRuntimeArchivePath `
            -ArchiveName $inputs.Manifest.java_runtime.archive_name `
            -Uri $inputs.Manifest.java_runtime.archive_url `
            -ExpectedSha256 $inputs.Manifest.java_runtime.archive_sha256 `
            -DestinationPath $javaArchive `
            -Description 'Java runtime archive' | Out-Null
        $javaArchiveHash = (Get-FileHash -LiteralPath $javaArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        $javaExtractDirectory = Join-Path $tempRoot 'java-runtime'
        Expand-Archive -LiteralPath $javaArchive -DestinationPath $javaExtractDirectory
        $javaArchiveRoot = Join-Path $javaExtractDirectory ($inputs.Manifest.java_runtime.archive_path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $javaArchiveRoot -PathType Container)) {
            throw "Java runtime archive root was not found: $javaArchiveRoot"
        }
        $javaPackagePath = Join-Path $stagingDirectory ($inputs.Manifest.java_runtime.package_path -replace '/', '\')
        New-Item -ItemType Directory -Path $javaPackagePath -Force | Out-Null
        Copy-Item -Path (Join-Path $javaArchiveRoot '*') -Destination $javaPackagePath -Recurse -Force
        $javaExecutable = Join-Path $stagingDirectory ($inputs.Manifest.java_runtime.executable_path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $javaExecutable -PathType Leaf)) {
            throw "Java runtime executable was not found in the archive: $javaExecutable"
        }

        $javaVersionOutput = (& cmd.exe /d /c "`"$javaExecutable`" -version 2>&1" | Out-String).Trim()
        $javaExitCode = $LASTEXITCODE
        $expectedJavaVersion = ($inputs.Manifest.java_runtime.version -split '\+')[0]
        if ($javaExitCode -ne 0 -or $javaVersionOutput -notmatch [regex]::Escape($expectedJavaVersion)) {
            throw "Packaged Java runtime version mismatch; expected $expectedJavaVersion, got $javaVersionOutput"
        }

        $previousJavaHome = $env:JAVA_HOME
        try {
            $env:JAVA_HOME = $javaPackagePath
            $allureVersionOutput = (& $allureExecutable --version 2>&1 | Out-String).Trim()
            $allureExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $previousJavaHome) {
                Remove-Item Env:\JAVA_HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:JAVA_HOME = $previousJavaHome
            }
        }
        if ($allureExitCode -ne 0 -or
            $allureVersionOutput -notmatch [regex]::Escape($inputs.Manifest.allure.version)) {
            throw "Packaged Allure CLI version mismatch; expected $($inputs.Manifest.allure.version), got $allureVersionOutput"
        }

        $wheelhouse = Join-Path $tempRoot 'wheelhouse'
        New-Item -ItemType Directory -Path $wheelhouse | Out-Null
        if ($null -ne $inputs.WheelhousePath) {
            Copy-Item -Path (Join-Path $inputs.WheelhousePath '*.whl') -Destination $wheelhouse -Force
        }
        else {
            $versionParts = $inputs.Manifest.runtime.python_version.Split('.')
            $pythonMinorVersion = '{0}.{1}' -f $versionParts[0], $versionParts[1]
            $pythonAbi = 'cp{0}{1}' -f $versionParts[0], $versionParts[1]
            Invoke-CheckedProcess -Executable $pythonExecutable -Arguments @(
                '-m', 'pip', 'download',
                '--disable-pip-version-check',
                '--require-hashes',
                '--only-binary=:all:',
                '--dest', $wheelhouse,
                '--platform', 'win_amd64',
                '--python-version', $pythonMinorVersion,
                '--implementation', 'cp',
                '--abi', $pythonAbi,
                '-r', $inputs.LockPath
            ) -Description 'Downloading locked Windows x64 wheels'
        }

        $sitePackages = Join-Path (Split-Path -Parent $pythonExecutable) 'Lib\site-packages'
        New-Item -ItemType Directory -Path $sitePackages -Force | Out-Null
        Invoke-CheckedProcess -Executable $pythonExecutable -Arguments @(
            '-m', 'pip', 'install',
            '--disable-pip-version-check',
            '--no-index',
            '--find-links', $wheelhouse,
            '--require-hashes',
            '--upgrade',
            '--target', $sitePackages,
            '-r', $inputs.LockPath
        ) -Description 'Installing locked pytest dependencies offline'

        $pipLaunchers = Join-Path (Split-Path -Parent $pythonExecutable) 'Scripts\pip*.exe'
        Get-ChildItem -Path $pipLaunchers -ErrorAction SilentlyContinue |
            Remove-Item -Force

        $bundleTestsDirectory = Join-Path $stagingDirectory 'tests'
        New-Item -ItemType Directory -Path $bundleTestsDirectory | Out-Null
        foreach ($testPath in $inputs.Tests) {
            Copy-Item -LiteralPath $testPath -Destination $bundleTestsDirectory -Force
        }
        Copy-Item -LiteralPath $inputs.LockPath -Destination (Join-Path $stagingDirectory 'requirements.lock')
        Copy-Item -LiteralPath $inputs.ReadmePath -Destination (Join-Path $stagingDirectory 'README.md')
        Copy-Item -LiteralPath $inputs.LauncherPath -Destination (Join-Path $stagingDirectory 'run-tests.cmd')
        Copy-Item -LiteralPath $inputs.ValidatorPath -Destination (Join-Path $stagingDirectory 'validate-bundle.ps1')
        Copy-Item -LiteralPath $inputs.ThirdPartyNoticesPath -Destination (Join-Path $stagingDirectory 'THIRD_PARTY_NOTICES.md')
        if ($null -ne $inputs.ReportRunnerPath) {
            Copy-Item -LiteralPath $inputs.ReportRunnerPath -Destination (Join-Path $stagingDirectory 'run_tests.py')
        }
        New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'logs') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'allure-results') | Out-Null

        Invoke-CheckedProcess -Executable $pythonExecutable -Arguments @(
            '-B', '-m', 'pytest', '--collect-only', '-q', 'tests'
        ) -Description 'Collecting bundled pytest tests' -WorkingDirectory $stagingDirectory

        $lockHash = (Get-FileHash -LiteralPath $inputs.LockPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $bundleManifest = [ordered]@{
            schema_version = 1
            target = $inputs.Manifest.target
            runtime = [ordered]@{
                distribution = $inputs.Manifest.runtime.distribution
                release = $inputs.Manifest.runtime.release
                python_version = $pythonVersion
                archive_name = $inputs.Manifest.runtime.archive_name
                archive_url = $inputs.Manifest.runtime.archive_url
                archive_sha256 = $actualHash
                package_python_path = $inputs.Manifest.runtime.package_python_path
            }
            allure = [ordered]@{
                version = $inputs.Manifest.allure.version
                archive_name = $inputs.Manifest.allure.archive_name
                archive_url = $inputs.Manifest.allure.archive_url
                archive_sha256 = $allureArchiveHash
                package_path = $inputs.Manifest.allure.package_path
                executable_path = $inputs.Manifest.allure.executable_path
                license = $inputs.Manifest.allure.license
                license_url = $inputs.Manifest.allure.license_url
            }
            java_runtime = [ordered]@{
                distribution = $inputs.Manifest.java_runtime.distribution
                version = $inputs.Manifest.java_runtime.version
                archive_name = $inputs.Manifest.java_runtime.archive_name
                archive_url = $inputs.Manifest.java_runtime.archive_url
                archive_sha256 = $javaArchiveHash
                package_path = $inputs.Manifest.java_runtime.package_path
                executable_path = $inputs.Manifest.java_runtime.executable_path
                license = $inputs.Manifest.java_runtime.license
                license_url = $inputs.Manifest.java_runtime.license_url
            }
            dependencies = [ordered]@{
                requirements_lock = 'requirements.lock'
                requirements_lock_sha256 = $lockHash
                requirements = @((Get-Content -LiteralPath $inputs.LockPath | Where-Object {
                    $_ -match '^[A-Za-z0-9_.-]+=='
                }) | ForEach-Object { ($_ -replace '\s+\\\s*$', '').Trim() })
            }
            external_prerequisites = @(
                'Windows x64 with ping.exe',
                'Read access to the C:\ root directory',
                'Outbound ICMP access for ping tests',
                'Default system browser for Allure reports'
            )
            built_utc = [DateTime]::UtcNow.ToString('o')
        }
        $bundleManifest | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $stagingDirectory 'bundle-manifest.json') -Encoding UTF8

        if (Test-Path -LiteralPath $OutputDirectory) {
            Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
        }
        Move-Item -LiteralPath $stagingDirectory -Destination $OutputDirectory
        Write-Output "Portable test package created at $OutputDirectory"
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
