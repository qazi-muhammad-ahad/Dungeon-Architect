param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$cmakeCandidates = @(
    (Join-Path $projectRoot '.tools/cmake-3.31.10-windows-x86_64/bin/cmake.exe'),
    (Join-Path $projectRoot '.tools/cmake/cmake/data/bin/cmake.exe')
)
$cmake = $cmakeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $cmake) {
    $installed = Get-Command cmake -ErrorAction SilentlyContinue
    if ($installed) { $cmake = $installed.Source }
}
if (-not $cmake) { throw 'CMake missing. Run tools/bootstrap-native.ps1 first.' }
$ctest = Join-Path (Split-Path $cmake -Parent) 'ctest.exe'
$mode = $Configuration.ToLowerInvariant()
Push-Location $projectRoot
try {
    & $cmake --preset "windows-$mode"
    if ($LASTEXITCODE -ne 0) { throw 'Native configure failed.' }
    & $cmake --build --preset $mode --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
    & $ctest --preset $mode
    if ($LASTEXITCODE -ne 0) { throw 'Native tests failed.' }
    & "./build/windows-$mode/bin/dungeon_cli.exe" --version
    if ($LASTEXITCODE -ne 0) { throw 'CLI launch failed.' }
} finally {
    Pop-Location
}
