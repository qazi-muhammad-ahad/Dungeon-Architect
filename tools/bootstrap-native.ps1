# Downloads only pinned, official portable tools under this checkout.
# Does not modify system PATH, registry, or existing compiler installations.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolsRoot = Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Force $toolsRoot | Out-Null

function Install-PortableTool($Name, $Url, $Sha256) {
    $destination = Join-Path $toolsRoot $Name
    $stamp = Join-Path $destination '.dungeon-setup-complete'
    if (Test-Path -LiteralPath $stamp) { return }
    $archive = Join-Path $toolsRoot "$Name.zip"
    if (-not (Test-Path -LiteralPath $archive) -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Sha256) {
        Invoke-WebRequest -Uri $Url -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum mismatch for $Name. No archive was extracted."
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $toolsRoot -Force
    Set-Content -LiteralPath $stamp -Value $Sha256
}

Install-PortableTool 'llvm-mingw-20261006-ucrt-x86_64' `
    'https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-x86_64.zip' `
    '317492c456aa27ee607a5919f1d2d38dcdc1112516a24d0bf4b00d078f52d17a'
Install-PortableTool 'cmake-3.31.10-windows-x86_64' `
    'https://github.com/Kitware/CMake/releases/download/v3.31.10/cmake-3.31.10-windows-x86_64.zip' `
    '13d1a463d7130df5339baedd63d8ae990aaf385062b2f42f372796143ae94086'
Write-Output 'Portable native tools are ready. Run tools/build-native.ps1.'
