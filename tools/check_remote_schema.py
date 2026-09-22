import sqlite3
from pathlib import Path
path = Path('/root/smart-medicine-box-backend/smart_medicine_box.db')
connection = sqlite3.connect(path)
columns = [row[1] for row in connection.execute('pragma table_info(reminder)')]
versions = [row[0] for row in connection.execute('select version from schema_migrations order by version')]
print('schedule_date=', 'schedule_date' in columns)
print('columns=', columns)
print('migrations=', versions)
