$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
python -m app.push_worker
