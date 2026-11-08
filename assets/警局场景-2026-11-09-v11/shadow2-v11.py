import numpy as np
from PIL import Image
T = r'C:\Users\18182\AppData\Local\Temp\wb-art-build'
sc = np.array(Image.open(T + r'\scene-no-cup.png').convert('RGB')).astype(int)
bg = np.array(Image.open(T + r'\background.png').convert('RGB')).astype(int)
fg = np.abs(sc - bg).max(2) > 14
darken = fg & ((sc.sum(2) - bg.sum(2)) < -20)
print('=== darken (shadow) row runs, x 350..1200 ===')
for y in range(0, 690, 20):
    xs = np.where(darken[y, 350:1200])[0] + 350
    if len(xs) < 8: continue
    runs = []; s = int(xs[0]); p = int(xs[0])
    for x in xs[1:]:
        x = int(x)
        if x > p + 5: runs.append((s, p)); s = x
        p = x
    runs.append((s, p)); runs = [r for r in runs if r[1] - r[0] > 10]
    print('y=%3d' % y, runs[:5])
print('\n=== darken column runs, y 0..700, x every 40 ===')
for x in range(700, 1200, 40):
    ys = np.where(darken[0:700, x])[0]
    if len(ys) < 8: continue
    runs = []; s = int(ys[0]); p = int(ys[0])
    for yy in ys[1:]:
        yy = int(yy)
        if yy > p + 5: runs.append((s, p)); s = yy
        p = yy
    runs.append((s, p)); runs = [r for r in runs if r[1] - r[0] > 10]
    print('x=%4d' % x, runs[:4])
