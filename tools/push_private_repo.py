# -*- coding: utf-8 -*-
"""建私有仓库并推送。

流程：
  1. 查同名仓库是否已存在（存在就复用，不存在就建 **private**）
  2. 设为 origin 并推送分支
  3. 打印最终远端状态

密钥从 ~/.git-credentials 读，全程不打印。
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')
OWNER = 'Rinne666'
REPO_NAME = 'caloriefit'
API = 'https://api.github.com'


def token_for(host):
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line or '@' not in line:
                continue
            head, tail = line.split('@', 1)
            scheme_user = head.split('://', 1)[-1]
            user, tok = scheme_user.split(':', 1)
            if tail.split('/')[0] == host:
                return user, tok
    raise SystemExit(f'找不到 {host} 的凭据')


TOKEN = token_for('github.com')[1]
HEADERS = {
    'Authorization': f'Bearer {TOKEN}',
    'User-Agent': 'caloriefit-setup',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
}


def api(method, path, payload=None):
    url = path if path.startswith('http') else API + path
    data = json.dumps(payload).encode('utf-8') if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode('utf-8')
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', errors='replace')
        return e.code, body


def git(*args, **kw):
    return subprocess.run(['git', *args], cwd=REPO, capture_output=True, text=True,
                          timeout=kw.get('timeout', 300))


print(f'=== 目标：GitHub 私有仓库 {OWNER}/{REPO_NAME} ===')

st, data = api('GET', f'/repos/{OWNER}/{REPO_NAME}')
if st == 200:
    print(f'仓库已存在，私有={data.get("private")}，直接复用')
elif st == 404:
    st, data = api('POST', '/user/repos', {
        'name': REPO_NAME,
        'private': True,
        'description': 'CalorieFit —— HarmonyOS 饮食/饮水/运动/步数记录应用（ArkTS / ArkUI）',
        'auto_init': False,
    })
    if st in (200, 201):
        print(f'已创建私有仓库：{data.get("html_url")}（private={data.get("private")}）')
    else:
        print(f'创建失败 HTTP {st}: {data}')
        sys.exit(1)
else:
    print(f'查询失败 HTTP {st}: {data}')
    sys.exit(1)

print('\n=== 设置远端 ===')
remotes = git('remote').stdout.split()
if 'origin' in remotes:
    git('remote', 'set-url', 'origin', f'https://github.com/{OWNER}/{REPO_NAME}.git')
    print(f'origin 已指向 https://github.com/{OWNER}/{REPO_NAME}.git')
else:
    git('remote', 'add', 'origin', f'https://github.com/{OWNER}/{REPO_NAME}.git')
    print(f'已添加 origin → https://github.com/{OWNER}/{REPO_NAME}.git')

print('\n=== 推送分支 ===')
branches = ['main', 'feature/glass-poster-ui']
for b in branches:
    r = git('push', '-u', 'origin', b)
    ok = r.returncode == 0
    print(f'  {b:28} {"OK" if ok else "FAIL"}')
    if not ok:
        print('    ' + (r.stderr or r.stdout).strip().replace('\n', '\n    ')[:600])

print('\n=== 远端状态 ===')
r = git('ls-remote', '--heads', 'origin')
print(r.stdout.strip() or (r.stderr or '').strip())
