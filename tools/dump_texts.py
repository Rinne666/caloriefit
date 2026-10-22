import json, sys, io

src = sys.argv[1]
dst = sys.argv[2]
with open(src, 'r', encoding='utf-8') as f:
    data = json.load(f)

rows = []

def walk(node):
    attrs = node.get('attributes', {})
    t = attrs.get('text', '')
    if t:
        rows.append((t, attrs.get('bounds', ''), attrs.get('type', '')))
    for c in node.get('children', []) or []:
        walk(c)

walk(data)
with io.open(dst, 'w', encoding='utf-8') as out:
    for t, b, ty in rows:
        out.write(f'{b}\t{ty}\t{t}\n')
print(f'rows={len(rows)}')
