# -*- coding: utf-8 -*-
"""查 GitHub token 的 scope 列表（只看 scope，不打印 token）。"""
import os
import sys
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')


def token():
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'github.com' in line:
                return line.split('://', 1)[1].split(':', 1)[1].split('@', 1)[0]
    raise SystemExit('no token')


req = urllib.request.Request('https://api.github.com/user', headers={
    'Authorization': f'Bearer {token()}', 'User-Agent': 'caloriefit-scope',
    'Accept': 'application/vnd.github+json'})
with urllib.request.urlopen(req, timeout=30) as r:
    scopes = r.headers.get('X-OAuth-Scopes', '(空)')
    allowed = r.headers.get('X-Accepted-OAuth-Scopes', '')
    print(f'token scope 列表: {scopes}')
    print(f'账号允许的 scope: {allowed}')
    for s in [x.strip() for x in scopes.split(',') if x.strip()]:
        print(f'  - {s}')
    print()
    print('删库需要 delete_repo scope —— 上面列表里有没有它：',
          '有' if 'delete_repo' in scopes else '没有')
