#!/usr/bin/env bash
# manage-profile.sh — CRUD operations on user-profile.json
# Usage:
#   manage-profile.sh read
#   manage-profile.sh get "company"
#   manage-profile.sh set "company.name" "Acme Corp"
#   manage-profile.sh add "expense_landscape.known_sources" '{"name":"AWS"}'
#   manage-profile.sh remove "expense_landscape.known_sources" "AWS"
#   manage-profile.sh delete "company.notes"

set -euo pipefail

PROFILE_PATH="$HOME/.accountant/user-profile.json"

if [ ! -f "$PROFILE_PATH" ]; then
  echo "ERROR: Profile not found at $PROFILE_PATH"
  echo "Run init-db.sh first."
  exit 1
fi

ACTION="${1:-read}"
KEY="${2:-}"
VALUE="${3:-}"

_touch() {
  python3 << 'PY'
import json
from datetime import datetime, timezone
p = "$HOME/.accountant/user-profile.json".replace("$HOME", __import__('os').path.expanduser("~"))
with open(p,'r') as f: d = json.load(f)
d['last_updated'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PY
}

case "$ACTION" in
  read)
    cat "$PROFILE_PATH" | python3 -m json.tool
    ;;

  get)
    [ -z "$KEY" ] && echo "Usage: get <key.path>" && exit 1
    python3 - "$PROFILE_PATH" "$KEY" << 'PY'
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
obj = data
for k in sys.argv[2].split('.'):
    obj = obj[k]
print(json.dumps(obj, indent=2, ensure_ascii=False) if isinstance(obj,(dict,list)) else obj)
PY
    ;;

  set)
    [ -z "$KEY" ] || [ -z "$VALUE" ] && echo "Usage: set <key.path> <value>" && exit 1
    python3 - "$PROFILE_PATH" "$KEY" "$VALUE" << 'PY'
import json, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path,'r') as f: data = json.load(f)
keys = key.split('.')
obj = data
for k in keys[:-1]: obj = obj[k]
try: v = json.loads(val)
except: v = val
obj[keys[-1]] = v
with open(path,'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
print(f'Set {key} = {v}')
PY
    _touch
    ;;

  add)
    [ -z "$KEY" ] || [ -z "$VALUE" ] && echo "Usage: add <array.path> '<json>'" && exit 1
    python3 - "$PROFILE_PATH" "$KEY" "$VALUE" << 'PY'
import json, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path,'r') as f: data = json.load(f)
obj = data
for k in key.split('.'): obj = obj[k]
try: v = json.loads(val)
except: v = val
if isinstance(obj, list):
    obj.append(v)
    with open(path,'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'Added to {key}')
else:
    print('ERROR: Target is not an array')
PY
    _touch
    ;;

  remove)
    [ -z "$KEY" ] || [ -z "$VALUE" ] && echo "Usage: remove <array.path> <name>" && exit 1
    python3 - "$PROFILE_PATH" "$KEY" "$VALUE" << 'PY'
import json, sys
path, key, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path,'r') as f: data = json.load(f)
obj = data
for k in key.split('.'): obj = obj[k]
if isinstance(obj, list):
    before = len(obj)
    obj[:] = [x for x in obj if not ((isinstance(x,dict) and x.get('name')==name) or x==name)]
    with open(path,'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'Removed {before - len(obj)} item(s) matching "{name}"')
else:
    print('ERROR: Target is not an array')
PY
    _touch
    ;;

  delete)
    [ -z "$KEY" ] && echo "Usage: delete <key.path>" && exit 1
    python3 - "$PROFILE_PATH" "$KEY" << 'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path,'r') as f: data = json.load(f)
keys = key.split('.')
obj = data
for k in keys[:-1]: obj = obj[k]
del obj[keys[-1]]
with open(path,'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
print(f'Deleted {key}')
PY
    _touch
    ;;

  *)
    echo "Usage: manage-profile.sh <read|get|set|add|remove|delete> [key] [value]"
    exit 1
    ;;
esac
