$env:SMB_DATABASE_URL = 'sqlite:///D:/smart-medicine-box/tools/backups/integration_refactor_20260922.db'
$env:SMB_SEED_DEMO_DATA = 'true'
$env:SMB_CORS_ORIGINS = '["*"]'
Set-Location -LiteralPath 'D:\smart-medicine-box\backend'
& 'D:\smart-medicine-box\backend\.venv\Scripts\python.exe' -m uvicorn app.main:app --host 127.0.0.1 --port 8001
