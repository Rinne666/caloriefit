# -*- coding: utf-8 -*-
"""检查旧提交在 GitHub 上是否仍能读出密钥内容。

**密钥不能出现在本仓库里**，用 $env:LEAKED_SECRET 传进来。
未设置时只列 refs 与 PR，不做内容比对。
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')
OWNER, NAME = 'Rinne666', 'caloriefit'
SECRET = os.environ.get('LEAKED_SECRET', '')
OLD = os.environ.get('LEAKED_OLD_COMMIT', '')


def token():
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'github.com' in line:
                return line.split('://', 1)[1].split(':', 1)[1].split('@', 1)[0]
    raise SystemExit('no token')


H = {'Authorization': f'Bearer {token()}', 'User-Agent': 'caloriefit-verify',
     'Accept': 'application/vnd.github+json'}


def get(path):
    req = urllib.request.Request(f'https://api.github.com{path}', headers=H)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', errors='replace')


if OLD and SECRET:
    print('=== 旧提交里的文件内容 ===')
    st, body = get(f'/repos/{OWNER}/{NAME}/contents/_verify_ai_e2e.py?ref={OLD}')
    if st == 200:
        d = json.loads(body)
        content = base64.b64decode(d['content']).decode('utf-8', errors='replace')
        hit = SECRET in content
        print(f'  HTTP {st}  仍含密钥: {hit}')
    else:
        print(f'  HTTP {st}: {body[:200]}')

print('\n=== 仓库里是否还有其它引用（refs / PR） ===')
st, body = get(f'/repos/{OWNER}/{NAME}/git/refs')
if st == 200:
    for r in json.loads(body):
        print(f"  {r['ref']}  {r['object']['sha'][:10]}")
else:
    print(f'  HTTP {st}: {body[:200]}')

st, body = get(f'/repos/{OWNER}/{NAME}/pulls?state=all')
if st == 200:
    prs = json.loads(body)
    print(f'  PR 数量: {len(prs)}')
    for p in prs:
        print(f"    #{p['number']} {p['title']} head={p['head']['sha'][:10]}")
else:
    print(f'  PR 查询 HTTP {st}')
