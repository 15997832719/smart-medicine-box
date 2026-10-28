[CmdletBinding()]
param(
    [string]$IndexPath = 'C:\Users\kjkhkh\AppData\Local\Arduino15\package_index.json',
    [string]$StagingDir = 'C:\Users\kjkhkh\AppData\Local\Arduino15\staging\packages',
    [string]$PlatformVersion = '3.3.12'
)

$ErrorActionPreference = 'Stop'
$stagingRoot = [System.IO.Path]::GetFullPath($StagingDir)
$expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Arduino15\staging\packages'))
if ($stagingRoot.TrimEnd('\') -ne $expectedRoot.TrimEnd('\')) {
    throw "Refusing to write outside Arduino staging directory: $stagingRoot"
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

$index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
$platform = $index.packages.platforms |
    Where-Object { $_.name -eq 'esp32' -and $_.version -eq $PlatformVersion } |
    Select-Object -First 1
if (-not $platform) { throw "ESP32 platform $PlatformVersion not found in $IndexPath" }

$packages = @([pscustomobject]@{
    Name = 'esp32:esp32 platform'
    Url = $platform.url
    File = $platform.archiveFileName
    Size = [long]$platform.size
    Checksum = $platform.checksum
})

foreach ($dependency in $platform.toolsDependencies) {
    $package = $index.packages | Where-Object { $_.name -eq $dependency.packager } | Select-Object -First 1
    if (-not $package) { throw "Package not found: $($dependency.packager)" }
    $tool = $package.tools |
        Where-Object { $_.name -eq $dependency.name -and $_.version -eq $dependency.version } |
        Select-Object -First 1
    if (-not $tool) { throw "Tool not found: $($dependency.packager):$($dependency.name)@$($dependency.version)" }
    $system = $tool.systems | Where-Object { $_.host -eq 'x86_64-mingw32' } | Select-Object -First 1
    if (-not $system) { $system = $tool.systems | Where-Object { $_.host -eq 'i686-mingw32' } | Select-Object -First 1 }
    if (-not $system) { throw "No Windows package for $($dependency.name)@$($dependency.version)" }
    $packages += [pscustomobject]@{
        Name = "$($dependency.packager):$($dependency.name)@$($dependency.version)"
        Url = $system.url
        File = $system.archiveFileName
        Size = [long]$system.size
        Checksum = $system.checksum
    }
}

function Get-ExpectedHash([string]$checksum) {
    if ($checksum -match '^SHA-256:([0-9a-fA-F]{64})$') { return $Matches[1].ToLowerInvariant() }
    throw "Unsupported checksum: $checksum"
}

function Test-Package([string]$path, [long]$size, [string]$expectedHash) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $path).Length -ne $size) { return $false }
    return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedHash)
}

function Get-ProxyUrl([string]$url) {
    if ($url -match '^https://github\.com/') { return "https://gh-proxy.com/$url" }
    return $url
}

$totalBytes = ($packages | Measure-Object -Property Size -Sum).Sum
$completedBytes = 0L
$downloaded = 0
$skipped = 0
$started = Get-Date
Write-Output ("Preparing {0} packages ({1:N1} MiB) in {2}" -f $packages.Count, ($totalBytes / 1MB), $stagingRoot)

foreach ($package in $packages) {
    $target = Join-Path $stagingRoot $package.File
    $expectedHash = Get-ExpectedHash $package.Checksum
    if (Test-Package $target $package.Size $expectedHash) {
        Write-Output ("[cached] {0} ({1:N1} MiB)" -f $package.Name, ($package.Size / 1MB))
        $skipped++
        $completedBytes += $package.Size
        continue
    }

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $actualSize = (Get-Item -LiteralPath $target).Length
        if ($actualSize -gt $package.Size) {
            Remove-Item -LiteralPath $target -Force
        }
    }

    $url = Get-ProxyUrl $package.Url
    Write-Output ("[download] {0} ({1:N1} MiB)" -f $package.Name, ($package.Size / 1MB))
    & curl.exe --location --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 --continue-at - --output $target $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed for $($package.Name): curl exit code $LASTEXITCODE" }

    if (-not (Test-Package $target $package.Size $expectedHash)) {
        Write-Warning "Checksum or size mismatch for $($package.Name); retrying from scratch"
        if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        & curl.exe --location --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 --output $target $url
        if ($LASTEXITCODE -ne 0) { throw "Retry failed for $($package.Name): curl exit code $LASTEXITCODE" }
        if (-not (Test-Package $target $package.Size $expectedHash)) { throw "Checksum validation failed for $($package.Name)" }
    }

    $downloaded++
    $completedBytes += $package.Size
    Write-Output ("[ok] {0}" -f $package.Name)
}

$elapsed = (Get-Date) - $started
[pscustomobject]@{
    Packages = $packages.Count
    Downloaded = $downloaded
    Cached = $skipped
    TotalMiB = [math]::Round($totalBytes / 1MB, 1)
    Elapsed = $elapsed.ToString('mm\:ss')
    StagingDir = $stagingRoot
} | Format-List
