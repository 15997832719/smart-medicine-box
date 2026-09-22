from pathlib import Path
base=Path(r'D:\smart-medicine-box\backend\app')
for name, cls in [('asr.py','class ASRError(RuntimeError):'),('services.py','class MedicineRecognitionError(RuntimeError):')]:
    p=base/name
    s=p.read_text(encoding='utf-8')
    old=cls+'\n\n\n'
    new=cls+'\n    pass\n\n\n'
    if old not in s:
        raise SystemExit(f'{name}: class block not found')
    p.write_text(s.replace(old,new,1),encoding='utf-8')
print('empty class bodies fixed')
