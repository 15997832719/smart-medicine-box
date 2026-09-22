import os
import sqlite3
from pathlib import Path

path = Path(r'D:\smart-medicine-box\tools\backups\temp_schedule_date_migration.db')
if path.exists():
    path.unlink()
os.environ['SMB_DATABASE_URL'] = f'sqlite:///{path.as_posix()}'
conn = sqlite3.connect(path)
conn.execute('''
CREATE TABLE reminder (
    id INTEGER PRIMARY KEY,
    medicine_id INTEGER NOT NULL,
    title VARCHAR(120) NOT NULL,
    dose VARCHAR(80),
    remind_time TIME NOT NULL,
    frequency VARCHAR(20),
    enabled BOOLEAN,
    note VARCHAR(300),
    owner_id INTEGER,
    created_at DATETIME
)
''')
conn.commit()
conn.close()

import app.models
from app.database import engine, init_db
from sqlalchemy import inspect

init_db()
columns = {item['name'] for item in inspect(engine).get_columns('reminder')}
print('schedule_date' in columns, sorted(columns))
if 'schedule_date' not in columns:
    raise SystemExit('migration failed')

