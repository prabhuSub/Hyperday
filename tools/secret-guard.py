#!/usr/bin/env python3
"""pre-commit guard: refuses a commit whose staged changes contain any Tesla secret
(client secret, tokens, private key) or any file from .tesla-keys. Runs locally only."""
import json, os, subprocess, sys
root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip()
keys = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.tesla-keys')
needles = []
try:
    for line in open(os.path.join(keys, 'client.env')):
        if line.startswith('TESLA_CLIENT_SECRET='): needles.append(line.split('=', 1)[1].strip())
except OSError: pass
try:
    t = json.load(open(os.path.join(keys, 'tokens.json')))
    needles += [t[k][-40:] for k in ('access_token', 'refresh_token', 'id_token') if t.get(k)]
except (OSError, ValueError): pass
try: needles.append(open(os.path.join(keys, 'private-key.pem')).read().split('\n')[1][:40])
except (OSError, IndexError): pass
names = subprocess.run(['git', 'diff', '--cached', '--name-only'], capture_output=True, text=True, cwd=root).stdout.split()
diff = subprocess.run(['git', 'diff', '--cached', '-U0'], capture_output=True, text=True, cwd=root).stdout
bad = [n for n in names if '.tesla-keys' in n or n.endswith('private-key.pem') or n.endswith('tokens.json') or n.endswith('client.env')]
if bad or any(n and n in diff for n in needles) or any(('BEGIN ' + k + 'PRIVATE ' + 'KEY') in diff for k in ('EC ', '')):
    print('✗ Commit blocked: it contains a Tesla secret or key file. Nothing was committed.', file=sys.stderr)
    sys.exit(1)
