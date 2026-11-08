import numpy as np
from PIL import Image

TMP = r'C:\Users\18182\AppData\Local\Temp\wb-art-build'
sc = np.array(Image.open(TMP + r'\scene-no-cup.png').convert('RGB')).astype(int)   # 1280x720 clean design
bg = np.array(Image.open(TMP + r'\background.png').convert('RGB')).astype(int)
shotS = np.array(Image.open(r'C:\Users\18182\.workbuddy\clipboard-images\clipboard-2026-11-08T19-25-16-179Z-12b0a18f.png').convert('RGB'))[58:958, 4:1604]
shotS = np.array(Image.fromarray(shotS).resize((1280, 720), Image.Resampling.LANCZOS)).astype(int)

BAG = np.array([217, 148, 49]); DARK = np.array([200, 109, 32]); RED = np.array([200, 92, 17])
FRAME = np.array([251, 243, 207]); PHOTO = np.array([73, 48, 61])
TAPE = np.array([252, 202, 0])
def near(img, c, t):
    return (np.abs(img - c).max(2) <= t)

def linefit(pairs):
    xs = np.array([p[0] for p in pairs]); ys = np.array([p[1] for p in pairs])
    A = np.vstack([np.ones(len(xs)), xs]).T
    b, a = np.linalg.lstsq(A, ys, rcond=None)[0]
    return a, b, list(zip(xs.tolist(), ys.tolist()))

print('=== DESIGN (1280x720) scanline transitions ===')
# bag left/right: first/last pixel close to BAG|DARK|RED, per row
bagish = near(sc, BAG, 10) | near(sc, DARK, 10) | near(sc, RED, 12)
left = []; right = []
for y in range(10, 680, 10):
    xs = np.where(bagish[y])[0]
    xs = xs[(xs > 150) & (xs < 1150)]
    if len(xs) > 100:
        left.append((y, int(xs.min()))); right.append((y, int(xs.max())))
print('bag left first/last', left[:4], left[-4:])
print('bag right first/last', right[:4], right[-4:])
print('bag left fit x=%.3f*y+%.1f' % tuple(linefit([(p[1], p[0]) for p in left])[:2][::-1]) if False else '')
# fit y = a*x+b then invert
for nm, pairs in [('left', left), ('right', right)]:
    a, b, _ = linefit([(p[1], p[0]) for p in pairs])  # y = a*x + b -> x = (y-b)/a
    print(f'bag {nm}: x = (y - {b:.1f}) / {a:.5f}  =>  x = {1/a:.5f} y + {-b/a:.1f}')

# dark diagonal: leftmost DARK pixel with >= 25 dark pixels to the right on that row
dark = near(sc, DARK, 12)
print('\ndark diagonal (leftmost dark run >=20):')
dd = []
for y in range(180, 660, 10):
    row = dark[y]
    xs = np.where(row)[0]
    if len(xs) < 20: continue
    # find first x with 20 consecutive-ish dark pixels
    ok = None
    for x in xs:
        if x > 1100: break
        if row[x:min(x + 20, 1280)].mean() > 0.85:
            ok = x; break
    if ok is not None and ok > 300:
        dd.append((y, int(ok)))
print(dd[:5], dd[-5:])
if len(dd) > 5:
    a, b, _ = linefit([(p[1], p[0]) for p in dd])
    print('dark diag: x = %.5f y + %.1f' % (1/a, -b/a))

# red wedge: left/right extents of RED per row in x 250..500
red = near(sc, RED, 14)
print('\nred wedge rows (1280):')
for y in range(150, 520, 20):
    xs = np.where(red[y, 250:520])[0] + 250
    if len(xs) > 2:
        print(' y=%3d  x %3d..%3d  n=%d' % (y, xs.min(), xs.max(), len(xs)))

# frame / photo transitions
frame = near(sc, FRAME, 14); photo = near(sc, PHOTO, 18)
print('\nframe rows (1280):')
for y in [200, 230, 250, 280, 300, 330, 360, 400, 440, 480, 520, 560, 580]:
    xs = np.where(frame[y, 800:1220])[0] + 800
    if len(xs) > 5: print(' y=%3d  x %4d..%4d n=%d' % (y, xs.min(), xs.max(), len(xs)))
print('photo rows (1280):')
for y in [280, 300, 320, 350, 380, 410, 440, 470, 500, 520]:
    xs = np.where(photo[y, 850:1200])[0] + 850
    if len(xs) > 5: print(' y=%3d  x %4d..%4d n=%d' % (y, xs.min(), xs.max(), len(xs)))
print('photo colours across x at y=400 (1280):')
for x in [880, 900, 920, 950, 980, 1000, 1010, 1020, 1040, 1060, 1080, 1100, 1130, 1150]:
    print(' ', x, tuple(sc[400, x]))

# tape colour along centerlines
print('\ntape colour samples (1280):')
for y, x in [(212, 100), (190, 200), (175, 300), (150, 500), (130, 700), (115, 900), (100, 1100),
             (520, 100), (530, 200), (545, 300), (560, 500), (580, 700), (600, 900), (620, 1100), (640, 1250)]:
    print(f' ({x},{y}) design={tuple(sc[y,x])} shot={tuple(shotS[y,x])} bg={tuple(bg[y,x])}')

# black bars
print('\nblack bar rows (fraction of near-black pixels):')
for y in list(range(0, 50, 5)) + list(range(670, 720, 5)):
    f = (np.abs(bg[y]).max(1) < 8).mean()
    print(y, round(float(f), 3))

# background vignette profile from bg.png (sample grid, 1280 coords -> report 1600)
print('\n=== background.png luminance grid (R channel), 1600 coords ===')
for Y in [50, 100, 200, 300, 450, 600, 750, 850]:
    row = []
    for X in [20, 100, 200, 400, 600, 800, 1000, 1200, 1400, 1580]:
        x, y = int(X/1.25), int(Y/1.25)
        row.append(int(bg[y, x][0]))
    print('Y=%3d' % Y, row)
