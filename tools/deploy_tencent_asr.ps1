[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Server,

    [string]$User = "root",

    [string]$AppDir = "/root/smart-medicine-box-backend",

    [ValidateSet("tiny", "base", "small")]
    [string]$Model = "base"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$remote = "$User@$Server"
$stamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$staging = "/tmp/smart-medicine-box-asr-$stamp"

$files = @(
    @{ Local = Join-Path $projectRoot "backend\app\asr.py"; Remote = "$staging/app/asr.py" },
    @{ Local = Join-Path $projectRoot "backend\app\config.py"; Remote = "$staging/app/config.py" },
    @{ Local = Join-Path $projectRoot "backend\app\routers.py"; Remote = "$staging/app/routers.py" },
    @{ Local = Join-Path $projectRoot "backend\requirements.txt"; Remote = "$staging/requirements.txt" },
    @{ Local = Join-Path $projectRoot "tools\install_local_asr_tencent.sh"; Remote = "$staging/install_local_asr_tencent.sh" }
)

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Local)) {
        throw "Missing local file: $($file.Local)"
    }
}

Write-Host "Creating remote staging directory: $staging"
& ssh $remote "mkdir -p '$staging/app'"

Write-Host "Uploading backend ASR files..."
foreach ($file in $files) {
    & scp $file.Local "${remote}:$($file.Remote)"
}

Write-Host "Installing local Whisper and restarting the backend service..."
$remoteCommand = "cp '$staging/app/asr.py' '$AppDir/app/asr.py' && " +
    "cp '$staging/app/config.py' '$AppDir/app/config.py' && " +
    "cp '$staging/app/routers.py' '$AppDir/app/routers.py' && " +
    "cp '$staging/requirements.txt' '$AppDir/requirements.txt' && " +
    "chmod +x '$staging/install_local_asr_tencent.sh' && " +
    "APP_DIR='$AppDir' SMB_ASR_MODEL='$Model' bash '$staging/install_local_asr_tencent.sh'"

& ssh $remote $remoteCommand

Write-Host ""
Write-Host "Deployment command finished."
Write-Host "Model: $Model"
Write-Host "Backend directory: $AppDir"
Write-Host "Check with: ssh $remote 'systemctl status smart-medicine-box'"