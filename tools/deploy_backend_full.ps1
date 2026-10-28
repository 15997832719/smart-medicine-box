[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Server,

    [string]$User = "root",

    [string]$AppDir = "/root/smart-medicine-box-backend",

    [string]$ServiceName = "smart-medicine-box",

    [string]$Archive = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($Archive)) {
    $Archive = Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -Filter "backend-sync-*.tar.gz" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not (Test-Path -LiteralPath $Archive)) {
    throw "Backend archive not found: $Archive"
}

$remote = "$User@$Server"
$stamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$remoteArchive = "/tmp/backend-sync-$stamp.tar.gz"

Write-Host "Uploading backend archive..."
& scp $Archive "${remote}:$remoteArchive"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

$remoteCommand = @"
set -e
mkdir -p '$AppDir'
if [ -d '$AppDir/app' ]; then
  cp -a '$AppDir/app' '$AppDir/app.backup.$stamp'
fi
cd '$AppDir'
tar -xzf '$remoteArchive'
if [ -x '$AppDir/.venv/bin/pip' ]; then
  '$AppDir/.venv/bin/pip' install -r '$AppDir/requirements.txt'
fi
systemctl daemon-reload
systemctl restart '$ServiceName'
sleep 2
systemctl --no-pager --full status '$ServiceName'
rm -f '$remoteArchive'
"@

Write-Host "Deploying on server..."
& ssh $remote $remoteCommand
if ($LASTEXITCODE -ne 0) { throw "remote deployment failed" }

Write-Host ""
Write-Host "Backend synchronized."
Write-Host "Server: $remote"
Write-Host "AppDir: $AppDir"
Write-Host "Service: $ServiceName"
