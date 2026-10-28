from pathlib import Path
p = Path(r"D:\smart-medicine-box\hardware\server\medicine_api.py")
s = p.read_text(encoding="utf-8")
old = '''        con.execute(
            "UPDATE speaker_bindings SET speaker_id=?, pairing_code=NULL, code_expires_at=NULL WHERE id=?",
            (device_id, binding_id),
        )'''
new = '''        con.execute(
            "DELETE FROM speaker_bindings WHERE speaker_id=? AND id<>?",
            (device_id, binding_id),
        )
        con.execute(
            "UPDATE speaker_bindings SET speaker_id=?, pairing_code=NULL, code_expires_at=NULL WHERE id=?",
            (device_id, binding_id),
        )'''
if old in s:
    s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    print("patched")
else:
    print("pattern missing")
