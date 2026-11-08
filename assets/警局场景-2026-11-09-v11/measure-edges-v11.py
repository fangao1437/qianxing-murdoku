import numpy as np
from PIL import Image
T = r'C:\Users\18182\AppData\Local\Temp\wb-art-build'
d = np.array(Image.open(T + r'\scene-no-cup.png').convert('RGB')).astype(int)  # 1280
s = np.array(Image.open(T + r'\police-v11-notext.png').convert('RGB')).astype(int)  # 1600
shotS = np.array(Image.fromarray(s.astype(np.uint8)).resize((1280, 720), Image.Resampling.LANCZOS)).astype(int)

def fit(pairs):
    xs = np.array([p[0] for p in pairs], float); ys = np.array([p[1] for p in pairs], float)
    A = np.vstack([np.ones(len(xs)), xs]).T
    a, b = np.linalg.lstsq(A, ys, rcond=None)[0]
    return a, b

# --- polaroid white frame edges (1280) ---
white = lambda im: (im[:, :, 0] > 232) & (im[:, :, 1] > 222) & (im[:, :, 2] > 185)
for name, im in [('design', d), ('v11', shotS)]:
    w = white(im)
    L = []; R = []; T = []; B = []
    for y in range(250, 580, 5):
        xs = np.where(w[y, 800:1200])[0] + 800
        if len(xs) > 8: L.append((y, xs.min())); R.append((y, xs.max()))
    for x in range(830, 1180, 5):
        ys = np.where(w[220:620, x])[0] + 220
        if len(ys) > 8: T.append((x, ys.min())); B.append((x, ys.max()))
    print('\n', name, 'frame L fit x=a*y+b', tuple(round(v, 4) for v in fit([(p[0], p[1]) for p in L])))
    print(name, 'frame R fit x=a*y+b', tuple(round(v, 4) for v in fit([(p[0], p[1]) for p in R])))
    print(name, 'frame T fit y=a*x+b', tuple(round(v, 4) for v in fit(T)))
    print(name, 'frame B fit y=a*x+b', tuple(round(v, 4) for v in fit(B)))
    print(name, 'frame bbox', (min(p[1] for p in L), min(p[1] for p in T), max(p[1] for p in R), max(p[1] for p in B)))

# --- bag right edge on clean rows (1280) ---
bag = (np.abs(d - np.array([217, 148, 49])).max(2) <= 9) | (np.abs(d - np.array([200, 109, 32])).max(2) <= 9)
print('\n=== design bag right edge per row (1280) ===')
pts = []
for y in range(60, 300, 10):
    xs = np.where(bag[y, 600:950])[0] + 600
    if len(xs) > 40: pts.append((y, int(xs.max())))
print(pts)
print('fit x = a*y+b', tuple(round(v, 4) for v in fit([(p[0], p[1]) for p in pts])))

# --- design bag left edge ---
print('\n=== design bag left edge per row (1280) ===')
pts2 = []
for y in range(60, 600, 20):
    xs = np.where(bag[y, 150:600])[0] + 150
    if len(xs) > 40: pts2.append((y, int(xs.min())))
print(pts2[:6], pts2[-6:])
print('fit x = a*y+b', tuple(round(v, 4) for v in fit([(p[0], p[1]) for p in pts2])))
