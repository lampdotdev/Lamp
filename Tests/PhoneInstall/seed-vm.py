#!/usr/bin/env python3
"""Make only fictional Lamp chats from the production classifier's replayed messages."""
import json
from pathlib import Path
import sys
import uuid

messages = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
fixtures = Path(__file__).parent / 'Fixtures'
for name, fixture in [('Pocket Timer', 'local-launch-security.txt'),
                      ('Trail Notes', 'capability.txt'), ('Weekly Planner', 'app-limit.txt')]:
    app = root / name.replace(' ', '').lower()
    meta = app / '.lamp'
    meta.mkdir(parents=True, exist_ok=True)
    (meta / 'meta.json').write_text(json.dumps(dict(name=name, exe='PhoneReplay', platform='iphone',
                                                  device='TEST-PHONE', family='iphone')))
    (app / 'icon.json').write_text(json.dumps(dict(subject='', symbol='timer', background='blue', tint='#FFFFFF')))
    rows = []
    def line(kind, text, **extra):
        rows.append(dict(id=str(uuid.uuid4()).upper(), kind=kind, text=text, **extra))
    line('status', f'Opening {name} on Test iPhone…')
    line('detail', (fixtures / fixture).read_text())
    line('error', messages[fixture], retryPhone='TEST-PHONE')
    (meta / 'chat.json').write_text(json.dumps(rows))
