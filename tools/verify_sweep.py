# -*- coding: utf-8 -*-
"""
量化验证「扫描动画」是否真的发生了。

为什么不能只看终态截图：
    终态和「根本没有动画、直接跳到终值」在像素上完全一样。
    必须拿冷启动的连续帧，比较进度环填充色的覆盖量随时间的变化。

颜色要同时认两套主题的主色，否则换个主题就全是 0：
    暗色 primary = #D5EE6E（石灰绿，高 G、低 B）
    浅色 primary = #147A5E（深绿，低亮度、G 略高于 B）
统计范围限制在主视觉卡的纵向带内，只盖住热量环 ——
按钮和底栏也有主色，会把计数污染成另一个数。
"""
import os
import sys
from PIL import Image

from harmony_paths import shots_dir

SHOTS = shots_dir()

# 主视觉卡纵向范围（1280x2832 原始坐标），上界压在 CTA 按钮之上
BAND = (0, 540, 1280, 1560)


def is_primary(r, g, b):
    lime = g > 170 and r > 140 and b < 170 and (g - r) > 8 and (g - b) > 60
    deep = r < 70 and 90 < g < 170 and 60 < b < 140 and 12 < (g - b) < 60
    return lime or deep


def count_primary(path):
    im = Image.open(path).convert('RGB')
    crop = im.crop(BAND)
    px = crop.load()
    w, h = crop.size
    n = 0
    for y in range(h):
        for x in range(w):
            if is_primary(*px[x, y]):
                n += 1
    return n


def main():
    files = sorted(f for f in os.listdir(SHOTS)
                   if f.startswith('anim_') and f.endswith('.jpeg'))
    if not files:
        print('no anim_*.jpeg found')
        return 1
    print('%-22s %10s  %s' % ('frame', 'ring_px', 'trend'))
    print('-' * 52)
    prev = None
    for f in files:
        n = count_primary(os.path.join(SHOTS, f))
        if prev is None:
            note = 'cold start, first frame'
        elif n > prev:
            note = 'ring sweeping   +%d' % (n - prev)
        elif n == prev:
            note = 'settled'
        else:
            note = 'receding        %+d' % (n - prev)
        print('%-22s %10d  %s' % (f, n, note))
        prev = n
    return 0


if __name__ == '__main__':
    sys.exit(main())
