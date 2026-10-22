# -*- coding: utf-8 -*-
"""核验 GitHub 远端是否真的没有某个密钥了。

**密钥本身不能出现在本仓库里**（包括本脚本）。
用环境变量传进来：$env:LEAKED_SECRET = "sk-..."
未设置时只做结构检查，跳过内容比对。

检查三件事：
  1. 旧提交（推过一次、含密钥的那个）在远端是否还可达
  2. 远端当前分支上的文件内容是否含密钥
  3. 仓库 code search 是否还能搜到密钥
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
OLD_COMMIT = os.environ.get('LEAKED_OLD_COMMIT', '')


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


if OLD_COMMIT:
    print('=== 1. 旧提交（含密钥）是否还可达 ===')
    st, body = get(f'/repos/{OWNER}/{NAME}/commits/{OLD_COMMIT}')
    if st == 200:
        print(f'  [!] 旧提交仍可访问 HTTP {st} —— 密钥可能仍能从 GitHub 取到')
    elif st == 404:
        print('  [OK] 旧提交已 404，从 GitHub 上取不到了')
    else:
        print(f'  [?] HTTP {st}: {body[:200]}')

print('\n=== 2. 远端当前分支的文件内容 ===')
st, data = get(f'/repos/{OWNER}/{NAME}/contents/_verify_ai_e2e.py?ref=feature/glass-poster-ui')
if st == 200:
    content = base64.b64decode(json.loads(data)['content']).decode('utf-8', errors='replace')
    if SECRET:
        print(f'  {"[OK] 远端文件已脱敏" if SECRET not in content else "[!] 远端文件仍含密钥"}')
    for line in content.splitlines()[:10]:
        if 'KEY' in line or 'DASHSCOPE' in line:
            print(f'    {line.strip()}')
else:
    print(f'  HTTP {st}: {str(data)[:200]}')

if SECRET:
    print('\n=== 3. 仓库 code search ===')
    st, data = get(f'/search/code?q={SECRET}+repo:{OWNER}/{NAME}')
    if st == 200:
        n = json.loads(data).get('total_count', 0)
        print(f'  命中 {n} 处' + ('  [OK]' if n == 0 else '  [!] 仍有命中'))
    else:
        print(f'  HTTP {st}: {str(data)[:200]}')

print('\n=== 4. 远端分支现状 ===')
st, data = get(f'/repos/{OWNER}/{NAME}/branches')
if st == 200:
    for b in json.loads(data):
        print(f"  {b['name']:30} {b['commit']['sha'][:10]}")
