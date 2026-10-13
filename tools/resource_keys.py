import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'app/assets/i18n/zh_CN.json'

class LanguageKeys:
    def __init__(self):
        self.values = json.loads(SOURCE.read_text())
        self.reverse = {value: key for key, value in reversed(list(self.values.items()))}

    def key(self, value):
        if value not in self.reverse:
            key = 'text_' + hashlib.sha1(value.encode()).hexdigest()[:10]
            assert key not in self.values or self.values[key] == value
            self.values[key] = value
            self.reverse[value] = key
        return self.reverse[value]

    def label(self, entry):
        for name in ('name', 'category'):
            if name in entry:
                entry[name+'Key'] = self.key(entry[name])
        return entry

    def save(self):
        SOURCE.write_text(json.dumps(self.values, ensure_ascii=False, indent=2)+'\n')
