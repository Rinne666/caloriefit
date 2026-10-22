# -*- coding: utf-8 -*-
"""推送后核验：仓库私有性 + 敏感信息扫描。"""
import json
import os
import re
import subprocess
import sys
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRED = os.path.join(os.path.expanduser('~'), '.git-credentials')
OWNER = 'Rinne666'
NAME = 'caloriefit'


def token():
    with open(CRED, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'github.com' in line:
                return line.split('://', 1)[1].split(':', 1)[1].split('@', 1)[0]
    raise SystemExit('no token')


req = urllib.request.Request(
    f'https://api.github.com/repos/{OWNER}/{NAME}',
    headers={'Authorization': f'Bearer {token()}', 'User-Agent': 'caloriefit-verify',
             'Accept': 'application/vnd.github+json'})
with urllib.request.urlopen(req, timeout=30) as r:
    d = json.loads(r.read().decode('utf-8'))

print('=== 仓库属性 ===')
print(f"  URL        {d.get('html_url')}")
print(f"  private    {d.get('private')}")
print(f"  visibility {d.get('visibility')}")
print(f"  default    {d.get('default_branch')}")
print(f"  size       {d.get('size')} KB")

print('\n=== 推送内容里的敏感信息扫描 ===')
# 只扫已跟踪文件；找出像密钥/口令的东西
pats = [
    (r'sk-[A-Za-z0-9]{20,}', '疑似 OpenAI/DashScope API Key'),
    (r'AKIA[0-9A-Z]{16}', '疑似 AWS AccessKey'),
    (r'-----BEGIN [A-Z ]*PRIVATE KEY-----', '私钥文件'),
    (r'(?i)(password|passwd|secret|api[_-]?key|token)\s*[=:]\s*["\'][^"\']{12,}["\']',
     '疑似硬编码口令'),
    (r'gh[pousr]_[A-Za-z0-9]{30,}', '疑似 GitHub Token'),
]
files = subprocess.run(['git', 'ls-files'], cwd=REPO, capture_output=True, text=True).stdout.split()
hits = 0
scanned = 0
for f in files:
    p = os.path.join(REPO, f)
    if not os.path.isfile(p) or os.path.getsize(p) > 2_000_000:
        continue
    try:
        with open(p, 'r', encoding='utf-8', errors='replace') as fh:
            body = fh.read()
    except Exception:
        continue
    scanned += 1
    for pat, label in pats:
        for m in re.finditer(pat, body):
            hits += 1
            line = body[:m.start()].count('\n') + 1
            print(f'  [命中] {f}:{line}  {label}')
print(f'  已扫描 {scanned} 个跟踪文件，命中 {hits} 处')

print('\n=== 远端分支 ===')
r = subprocess.run(['git', 'ls-remote', '--heads', 'origin'], cwd=REPO,
                   capture_output=True, text=True)
for line in r.stdout.strip().splitlines():
    sha, ref = line.split('\t')
    print(f'  {ref}  {sha[:10]}')

print('\n=== 本地未推送的提交 ===')
r = subprocess.run(['git', 'log', '--oneline', 'origin/feature/glass-poster-ui..HEAD'],
                   cwd=REPO, capture_output=True, text=True)
print('  ' + (r.stdout.strip() or '（无，工作区与远端一致）'))
