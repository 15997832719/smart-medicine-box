from pathlib import Path
p = Path(r"D:\smart-medicine-box\hardware\server\medicine_api.py")
s = p.read_text(encoding="utf-8")
old = '"UPDATE speaker_bindings SET speaker_id=?, pairing_code=NULL, code_expires_at=NULL WHERE id=?",'
new = '"UPDATE speaker_bindings SET speaker_id=?, platform=\'xiaozhi\', pairing_code=NULL, code_expires_at=NULL WHERE id=?",'
if old in s:
    s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    print("patched")
else:
    print("missing")
