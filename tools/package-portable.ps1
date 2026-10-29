param(
    [Parameter(Mandatory=$true)][string]$NativeBuildDirectory,
    [Alias('WebBuildDirectory')][string]$WebDirectory = 'apps/flutter_ui/build/web',
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$FlutterRoot,
    [string]$ToolchainDirectory = '.tools/llvm-mingw-20261006-ucrt-x86_64',
    [string]$EmscriptenDirectory = '.tools/emsdk/upstream/emscripten'
)
# Assemble already-built, validated Release artifacts. No SDK is shipped or installed.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
function Absolute([string]$path) {
    if ([IO.Path]::IsPathRooted($path)) { return [IO.Path]::GetFullPath($path) }
    return [IO.Path]::GetFullPath((Join-Path $projectRoot $path))
}
$native = Absolute $NativeBuildDirectory
$web = Absolute $WebDirectory
$destinationRoot = Absolute $Destination
$toolchain = Absolute $ToolchainDirectory
$emscripten = Absolute $EmscriptenDirectory
$flutter = Absolute $FlutterRoot
if (Test-Path -LiteralPath $destinationRoot) { throw 'Destination already exists. Choose a new package directory.' }
foreach ($artifact in @('bin/dungeon_cli.exe','bin/libdungeon_api.dll','bin/dungeon_api_caller.exe','bin/dungeon_launcher.exe','lib/libdungeon_api.dll.a')) {
    if (-not (Test-Path -LiteralPath (Join-Path $native $artifact) -PathType Leaf)) { throw "Missing native artifact: $artifact" }
}
foreach ($artifact in @('index.html','main.dart.js','engine/dungeon_engine.wasm','assets/NOTICES')) {
    if (-not (Test-Path -LiteralPath (Join-Path $web $artifact) -PathType Leaf)) { throw "Missing web artifact: $artifact" }
}
$readobj = Join-Path $toolchain 'bin/llvm-readobj.exe'
$imports = @{}
foreach ($binary in @('dungeon_cli.exe','libdungeon_api.dll','dungeon_api_caller.exe','dungeon_launcher.exe')) {
    $inspection = & $readobj --coff-imports (Join-Path $native "bin/$binary")
    if ($LASTEXITCODE -ne 0) { throw "Import inspection failed: $binary" }
    $names = @($inspection | Select-String '^\s+Name: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if (-not $names.Count) { throw "No imports found: $binary" }
    foreach ($name in $names) {
        if ($name -notmatch '^(?i:api-ms-win-.*\.dll|KERNEL32\.dll|WS2_32\.dll|SHELL32\.dll|libdungeon_api\.dll)$') {
            throw "Unreviewed runtime dependency $name in $binary; resolve and license it before packaging."
        }
    }
    $imports[$binary] = $names
}
New-Item -ItemType Directory -Path $destinationRoot | Out-Null
function Copy-Required([string]$source, [string]$relative) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required package input missing: $relative" }
    $target = Join-Path $destinationRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}
foreach ($binary in @('dungeon_cli.exe','libdungeon_api.dll','dungeon_api_caller.exe')) { Copy-Required (Join-Path $native "bin/$binary") "bin/$binary" }
Copy-Required (Join-Path $native 'bin/dungeon_launcher.exe') 'dungeon_launcher.exe'
Copy-Item -LiteralPath $web -Destination (Join-Path $destinationRoot 'web') -Recurse
# Build metadata/maps are not runtime inputs.
Get-ChildItem -LiteralPath (Join-Path $destinationRoot 'web') -Recurse -File -Force |
    Where-Object { $_.Name.StartsWith('.') -or $_.Extension -eq '.map' } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName }
Copy-Required (Join-Path $projectRoot 'datasets/pipeline/teaching.json') 'samples/teaching.json'
Copy-Required (Join-Path $projectRoot 'datasets/pipeline/irregular-fortress.json') 'samples/irregular-fortress.json'
Copy-Required (Join-Path $projectRoot 'packaging/blank.json') 'samples/blank.json'
Copy-Required (Join-Path $projectRoot 'api/include/dungeon_architect_c.h') 'api/include/dungeon_architect_c.h'
Copy-Required (Join-Path $projectRoot 'api/examples/caller.c') 'api/example.c'
Copy-Required (Join-Path $native 'lib/libdungeon_api.dll.a') 'api/lib/libdungeon_api.dll.a'
foreach ($doc in @('portable-package.md','native_api.md','cli.md','project_format.md','result_format.md','design_canvas.md','room_encounter_editor.md','analyze_benchmarks.md','scenarios_play.md','visual_polish.md','dependencies.md','platform_decision.md')) {
    Copy-Required (Join-Path $projectRoot "docs/$doc") "docs/$doc"
}
Copy-Required (Join-Path $projectRoot 'docs/schema/project-v1.schema.json') 'docs/schema/project-v1.schema.json'
Copy-Required (Join-Path $projectRoot 'packaging/Start Dungeon Architect.cmd') 'Start Dungeon Architect.cmd'
Copy-Required (Join-Path $projectRoot 'docs/portable-package.md') 'START-HERE.md'
Copy-Required (Join-Path $projectRoot 'packaging/THIRD-PARTY-NOTICES.md') 'licenses/THIRD-PARTY-NOTICES.md'
Copy-Required (Join-Path $projectRoot 'third_party/nlohmann/LICENSE.MIT') 'licenses/nlohmann-json-MIT.txt'
Copy-Required (Join-Path $toolchain 'LICENSE.TXT') 'licenses/LLVM-Apache-2.0-with-exceptions.txt'
foreach ($notice in Get-ChildItem -LiteralPath (Join-Path $toolchain 'x86_64-w64-mingw32/share/mingw32') -Filter 'COPYING*' -File) {
    Copy-Required $notice.FullName "licenses/mingw-w64/$($notice.Name)"
}
Copy-Required (Join-Path $emscripten 'LICENSE') 'licenses/Emscripten-LICENSE.txt'
Copy-Required (Join-Path $emscripten 'system/lib/libc/musl/COPYRIGHT') 'licenses/musl-COPYRIGHT.txt'
Copy-Required (Join-Path $flutter 'LICENSE') 'licenses/Flutter-LICENSE.txt'
Copy-Required (Join-Path $flutter 'bin/cache/dart-sdk/LICENSE') 'licenses/Dart-LICENSE.txt'
Copy-Required (Join-Path $web 'assets/NOTICES') 'licenses/Flutter-runtime-NOTICES'
$cliVersion = & (Join-Path $native 'bin/dungeon_cli.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'CLI version probe failed.' }
$files = @(Get-ChildItem -LiteralPath $destinationRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
    @{ path = [IO.Path]::GetRelativePath($destinationRoot,$_.FullName).Replace('\','/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$manifest = [ordered]@{
    format = 1; platform = 'Windows x64 + Chrome over loopback HTTP'; engine = ($cliVersion -join "`n");
    abi = 1; project_schema = 1; native_imports = $imports; files = $files
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destinationRoot 'package-manifest.json') -Encoding utf8
Write-Host "Package assembled: $destinationRoot"
Write-Host 'Validate the relocated package before archiving or publication. Manifest covers all files except itself.'
