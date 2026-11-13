// 656 · 首页按设计图补齐 / 复刻
//
// 输入：qianxing-murdoku/650_全面优化/655_遍历负载优化.gil（锁定 SHA256，不覆盖）
// 输出：qianxing-murdoku/656_首页设计/656_首页设计.gil
//
// 范围（用户口径）：
//   · 背景 police-v12 是独立项目，存档内已导入，不改一行；
//   · 设计图里两个回形针、右上角咖啡杯不要，不新增；
//   · 其余前景（中央纸/网格纹理/棕面板/四胶囊/相机/教程圆/便利贴/胶带/波浪线）按设计图补齐；
//   · 用户追加：删掉首页四键旧素材（107179 蓝色云纹胶囊）的引用路线，bg 子控件可删则删，
//     按钮改由「1 矩形 + 2 圆」纯色胶囊承担；并带上 650-655 验证过的可用手段
//     （删控件三处同步 + 四道闸、recTop/childList 双同步、静态分类父级、精确路径表不被扰动、
//      Lua 语法编译 + 往返编码断言）。
//
// 内嵌 Lua 只有两处定向补丁：入口层胶囊守卫名单去掉首页四键；btn_list 收集排除 home.*。
// 655 的 279 条精确路径表、索引代数/弱键缓存等全部减负补丁原样保留。
//
// 复现：node 构建656_首页复刻.mjs        （输出已存在时 FORCE=1 才覆盖）
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '首页复刻规格_656.json'), 'utf8'));
const INPUT = path.resolve(DIR, SPEC.base.file);
const OUTPUT = path.join(DIR, '656_首页设计.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
if (sha(INPUT) !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符：' + INPUT);
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1') throw Error('输出已存在，需 FORCE=1：' + OUTPUT);

const { readGil, stateBlocks, pairOf, setPair, cloneField, ensureChildListTop,
  findChildListTop, asIdList, setChildList, textsOf, encodeMsg } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')).href);
const { writeGil, findScriptLeaf } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')).href);
const { setHiddenRecord } =
  await import(pathToFileURL(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')).href);

const g = readGil(INPUT);
const by = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = by.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const recTop = g.tree.find(q => q.field === 9);
let max = BigInt(g.maxId);
const added = [], modified = [], hidden = [];
const P = SPEC.palette, G = SPEC.geometry;

// ── 通用字段工具 ───────────────────────────────────────────────────────────
const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
function setNum(p, k, v) {
  let f = p.sub.find(q => q.field === k && q.wt === 0);
  if (!f) p.sub.push(f = { field: k, wt: 0 });
  f.num = BigInt(v >>> 0);
}
function states(r) { return stateBlocks(r.field.sub, []); }
function setGeom(r, cx, cy, w, h) {
  for (const st of states(r)) {
    setPair(pairOf(st, 504), cx - 800, 450 - cy);
    setPair(pairOf(st, 505), w, h);
  }
  modified.push(r.name);
}
function setRot(r, deg) {
  for (const st of states(r)) {
    let rf = st.sub.find(q => q.field === 508);
    if (!rf) st.sub.push(rf = { field: 508, wt: 2 });
    rf.sub = [{ field: 3, wt: 5, f: deg }]; rf.payload = null; rf.len = 5;
  }
  modified.push(r.name);
}
function imgParts(r) { return ns(r.field, [505, 503, 84]); }
function txtParts(r) { return ns(r.field, [505, 503, 75]); }
function argb(hex) { return parseInt('FF' + hex.slice(1), 16); }
function setColor(r, hex) { for (const p of imgParts(r)) setNum(p, 502, argb(hex)); modified.push(r.name); }
function setColorRaw(r, v) { for (const p of imgParts(r)) setNum(p, 502, v); modified.push(r.name); }
function setImage(r, id) { for (const p of imgParts(r)) setNum(p, 503, id); modified.push(r.name); }
function setTextColor(r, hex, size) {
  for (const p of txtParts(r)) { setNum(p, 504, argb(hex)); if (size) { setNum(p, 512, size); setNum(p, 513, size); } }
  modified.push(r.name);
}
function hide(name) { const r = R(name); setHiddenRecord(r.field, true); hidden.push(name); modified.push(name); }

// ── 新增图元 ───────────────────────────────────────────────────────────────
function remap(a, from, to, d = 0) {
  for (const q of a) {
    if (!(d === 0 && q.field === 504) && q.num === BigInt(from)) q.num = BigInt(to);
    if (q.sub) remap(q.sub, from, to, d + 1);
  }
}
function makeLayer(L, parent) {
  const proto = R('td.home.page.1.help619.icon');
  const f = cloneField(proto.field), id = Number(++max);
  remap(f.sub, proto.id, id);
  const nf = textsOf(f.sub, []).find(q => q.payload?.toString('utf8') === proto.name);
  if (!nf) throw Error('克隆原型缺名字叶子');
  nf.payload = Buffer.from(L.name); nf.len = nf.payload.length;
  f.sub = f.sub.filter(q => !(q.field === 504 && q.wt === 0));
  f.sub.push({ field: 504, wt: 0, num: BigInt(parent.id) });
  const cl = findChildListTop(f.sub); if (cl) setChildList(cl, []);
  setHiddenRecord(f, false);
  const r = { id, name: L.name, parentId: parent.id, field: f };
  added.push(r); by.set(L.name, r);
  setGeom(r, L.cx, L.cy, L.w, L.h);
  setRot(r, L.rot || 0);
  setColor(r, L.color);
  setImage(r, L.imageId || 100001);
  for (const p of imgParts(r)) setNum(p, 504, 1);   // 使用染色
  return r;
}
// 把一批层插到 anchor 在【全局记录表】与【父 childList】的同一位置
function addAt(anchorName, layers, parentName, where = 'after') {
  const anchor = R(anchorName), parent = R(parentName);
  const created = layers.map(L => makeLayer(L, parent));
  const fields = created.map(r => r.field);
  const i = recTop.sub.indexOf(anchor.field);
  if (i < 0) throw Error('全局记录锚点丢失 ' + anchorName);
  recTop.sub.splice(where === 'before' ? i : i + 1, 0, ...fields);
  const cl = ensureChildListTop(parent);
  const ids = asIdList(cl.payload, true), ai = ids.indexOf(anchor.id);
  if (ai < 0) throw Error('childList 锚点丢失 ' + anchorName);
  ids.splice(where === 'before' ? ai : ai + 1, 0, ...created.map(r => r.id));
  setChildList(cl, ids);
  return created;
}
// 旋转纸/便签的局部坐标 → 绝对画布坐标（与渲染器 rotate(-rot) 一致）
function local2abs(cx, cy, deg, lx, ly) {
  const t = deg * Math.PI / 180;
  return [cx + lx * Math.cos(t) + ly * Math.sin(t), cy - lx * Math.sin(t) + ly * Math.cos(t)];
}
const box = (name, x0, y0, x1, y1, color, rot = 0, imageId = 100001) =>
  ({ name, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, w: x1 - x0, h: y1 - y0, color, rot, imageId });
const rotBox = (name, cx, cy, w, h, color, deg, deg2, lx, ly, imageId = 100001) => {
  const [X, Y] = local2abs(cx, cy, deg2, lx, ly);
  return { name, cx: X, cy: Y, w, h, color, rot: deg, imageId };
};
// 折线段（旋转细矩形），与 641 的 line() 同口径
function segment(name, a, b, color, width) {
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy);
  return { name, cx: (a[0] + b[0]) / 2, cy: (a[1] + b[1]) / 2,
    w: len + width * 0.35, h: width, color, rot: -Math.atan2(dy, dx) * 180 / Math.PI, imageId: 100001 };
}
const N = n => 'art656.home.' + n;

// ── 一、改现有层 ───────────────────────────────────────────────────────────
// 中央纸 / 面板
const paper = R('art641.home.document.paper');
setGeom(paper, G.paper.cx, G.paper.cy, G.paper.w, G.paper.h); setRot(paper, 0); setColor(paper, P.paper);
const panel = R('art641.home.panel');
setGeom(panel, G.panel.cx, G.panel.cy, G.panel.w, G.panel.h); setRot(panel, 0); setColor(panel, P.panel);
// 四个按钮：容器 + 命中区同步到设计图位置；删除旧素材 bg 子控件，label 改深棕字。
// 用户口径：旧素材引用路线删掉、素材控件可删就删；按钮外观改由下方纯色胶囊承担。
// 删控件按项目 tools/gil/delete_controls.mjs 的三处同步：父 childList / 全局记录表 / recs，
// bg 不是根对象（有父容器），无需动 /9/#501；且 bg 自身无子控件，不存在悬空子树。
const btnNames = ['home.select', 'home.continue', 'home.shop', 'home.bag'];
const deletedBg = [];
btnNames.forEach((n, i) => {
  const r = R(n), [cx, cy] = G.buttons.centers[i];
  setGeom(r, cx, cy, G.buttons.w, G.buttons.h);
  const childList = findChildListTop(r.field.sub);
  const ids = childList ? asIdList(childList.payload, true) : [];
  const keep = [];
  for (const cid of ids) {
    const c = g.recs.find(q => q.id === cid); if (!c) continue;
    if (imgParts(c).length) {
      deletedBg.push({ id: c.id, name: n + '/bg', parent: n });
      const j = recTop.sub.indexOf(c.field);
      if (j < 0) throw Error('bg 记录不在全局记录表：' + n);
      recTop.sub.splice(j, 1);
      const k = g.recs.indexOf(c);
      if (k < 0) throw Error('bg 记录不在 recs：' + n);
      g.recs.splice(k, 1);
      continue;                       // 不写回 keep ⇒ 同步从父 childList 移除
    }
    keep.push(cid);
    if (txtParts(c).length) {
      setGeom(c, 800, 450, G.buttons.w - 12, G.buttons.h);
      setTextColor(c, P.buttonText, 24);
    }
  }
  if (childList) setChildList(childList, keep);
});
if (deletedBg.length !== 4) throw Error('应删除 4 个 bg，实际 ' + deletedBg.length);
// 教程圆：bg=外金圆 / mid=中棕圆 / ring=内深圆 / label 米白字 / hit 跟随
const T = G.tutorial;
setGeom(R('home.tutorial627.bg'), T.cx, T.cy, T.outer, T.outer); setImage(R('home.tutorial627.bg'), 100002); setColor(R('home.tutorial627.bg'), P.tutorialOuter);
setGeom(R('home.tutorial627.ring'), T.cx, T.cy, T.inner, T.inner); setImage(R('home.tutorial627.ring'), 100002); setColor(R('home.tutorial627.ring'), P.tutorialInner);
setGeom(R('home.tutorial627.label'), T.cx, T.cy, 115, 48); setTextColor(R('home.tutorial627.label'), P.tutorialText, 26);
setGeom(R('home.tutorial627.hit'), T.cx, T.cy, T.outer, T.outer);
// 标题：保留功能文字，改成与棕面板低对比的深棕（设计图未画文字）
if (SPEC.options.title) setTextColor(R('home.title'), P.buttonText, 20);
else hide('home.title');
// 相机：机身 / 上盖 / 取景窗 / 两个圆点
const C = G.camera;
setGeom(R('art641.home.camera.body'), (C.x0 + C.x1) / 2, (C.body[0] + C.body[1]) / 2, C.x1 - C.x0, C.body[1] - C.body[0]);
setRot(R('art641.home.camera.body'), 0); setColor(R('art641.home.camera.body'), P.cameraBodyMid);
setGeom(R('art641.home.camera.top'), (C.x0 + C.x1) / 2, (C.capTop + C.capBottom) / 2, C.x1 - C.x0, C.capBottom - C.capTop);
setRot(R('art641.home.camera.top'), 0); setColor(R('art641.home.camera.top'), P.cameraCap);
setGeom(R('art641.home.camera.window'), (C.window[0] + C.window[1]) / 2, (C.window[2] + C.window[3]) / 2, C.window[1] - C.window[0], C.window[3] - C.window[2]);
setRot(R('art641.home.camera.window'), 0); setColor(R('art641.home.camera.window'), P.cameraWindow);
C.dots.forEach(([x, y, s], i) => {
  const r = R('art641.home.camera.dot' + i);
  setGeom(r, x, y, s, s); setRot(r, 0); setColor(r, P.cameraDot); setImage(r, 100002);
});
// 设计图没有的纯装饰：黑色纸投影、红图钉、相机下方青色拍立得
for (const n of ['art641.home.document.shadow', 'art641.home.pin',
  'art641.home.camera.photo.shadow', 'art641.home.camera.photo.paper', 'art641.home.camera.photo.inner']) hide(n);

// ── 二、新增层：纸张背后的斜网格纸 + 纹理线（画在主体纸之前） ──────────────
const back = [];
back.push({ name: N('grid.paper'), cx: G.gridPaper.cx, cy: G.gridPaper.cy, w: G.gridPaper.w, h: G.gridPaper.h,
  color: P.gridBase, rot: G.gridPaper.rot, imageId: 100001 });
const GL = G.gridLines;
for (let i = 0; i < GL.count; i++) {
  const lx = -G.gridPaper.w / 2 + 12 + i * GL.step;
  const [X, Y] = local2abs(G.gridPaper.cx, G.gridPaper.cy, G.gridPaper.rot, lx, 0);
  back.push({ name: N('grid.v' + i), cx: X, cy: Y, w: GL.width, h: G.gridPaper.h,
    color: P.gridLine, rot: G.gridPaper.rot, imageId: 100001 });
}
GL.horizontalY.forEach((ly, i) => {
  const [X, Y] = local2abs(G.gridPaper.cx, G.gridPaper.cy, G.gridPaper.rot, 0, ly);
  back.push({ name: N('grid.h' + i), cx: X, cy: Y, w: G.gridPaper.w, h: GL.width,
    color: P.gridLine, rot: G.gridPaper.rot, imageId: 100001 });
});
back.push(box(N('paper.edge'), 1119, 119, 1124, 824, P.paperEdge));
addAt('art641.home.document.shadow', back, 'grp653.static.1.art641.home', 'before');

// ── 三、新增层：相机细节（插在 camera.body 之后、上盖/取景窗之前） ─────────
const cam = [];
// 机身左右两条略浅的竖带
cam.push(box(N('camera.side.l'), C.x0, C.body[0], 125, C.body[1], P.cameraBodySide));
cam.push(box(N('camera.side.r'), 412, C.body[0], C.x1, C.body[1], P.cameraBodySide));
// 上盖与机身之间的浅缝、机身下沿
// ±1px 重叠，避免相邻色带之间出现透出背景的 1px 缝
cam.push(box(N('camera.seam'), C.x0, C.seam[0] - 1, C.x1, C.seam[1] + 1, P.cameraSeam));
cam.push(box(N('camera.bottom'), C.x0, C.bottom[0] - 1, C.x1, C.bottom[1], P.cameraCap));
// 斜角改用 1 个 100003 等腰三角形（rot=0 尖端朝上）：包围盒 x200..290 / y208..249，
// 左斜边 (200,249)→(245,208) 正是设计图的相机斜边；右半三角被随后绘制的高台矩形盖住，
// 底边以下的 1px 被 cam 组之后绘制的 camera.top 盖住 ⇒ 多余部分全在内部，无痕迹。
// 相比原 15 级台阶：少 14 个控件，且边缘是真正的直线。
cam.push({ name: N('camera.cap.slope'), cx: 245, cy: (C.capHighTop + 249) / 2, w: 90, h: 249 - C.capHighTop,
  color: P.cameraCap, rot: 0, imageId: 100003 });
cam.push(box(N('camera.cap.high'), 245, C.capHighTop, C.x1, C.capTop, P.cameraCap));
// 上盖左侧两个凸起
C.bumps.forEach(([x0, x1], i) => cam.push(box(N('camera.bump' + i), x0, 234, x1, C.capTop, P.cameraBump)));
addAt('art641.home.camera.body', cam, 'grp653.static.1.art641.home', 'after');

// ── 四、新增层：教程圆中环（插在 bg 之后、ring 之前） ──────────────────────
addAt('home.tutorial627.bg', [
  { name: 'home.tutorial627.mid', cx: T.cx, cy: T.cy, w: T.mid, h: T.mid, color: P.tutorialMid, rot: 0, imageId: 100002 },
], 'home', 'after');

// ── 五、新增层：便利贴 / 青胶带 / 手绘波浪线（插在相机之后） ────────────────
const front = [];
// 四颗按钮的纯色胶囊：官方 107179 自带蓝色云纹且运行时写死，改用「1 矩形 + 2 圆」拼。
// 挂在静态美术组 ⇒ 画在 home 功能组（bg/label）之前，文字由 label 正常叠在上面。
G.buttons.centers.forEach(([bcx, bcy], i) => {
  const bw = G.buttons.w, bh = G.buttons.h, bodyW = bw - bh;
  front.push({ name: N('button.' + i + '.body'), cx: bcx, cy: bcy, w: bodyW, h: bh, color: P.button, rot: 0, imageId: 100001 });
  front.push({ name: N('button.' + i + '.left'), cx: bcx - bodyW / 2, cy: bcy, w: bh, h: bh, color: P.button, rot: 0, imageId: 100002 });
  front.push({ name: N('button.' + i + '.right'), cx: bcx + bodyW / 2, cy: bcy, w: bh, h: bh, color: P.button, rot: 0, imageId: 100002 });
});
const NT = G.note, step = NT.w / 4, noteColors = [P.note1, P.note2, P.note3, P.note4];
for (let i = 0; i < 4; i++) {
  const lx = -NT.w / 2 + step * (i + 0.5);
  const [X, Y] = local2abs(NT.cx, NT.cy, NT.rot, lx, 0);
  front.push({ name: N('note.band' + i), cx: X, cy: Y, w: step + 1.5, h: NT.h,
    color: noteColors[i], rot: NT.rot, imageId: 100001 });
}
front.push({ name: N('note.tape'), cx: G.tape.cx, cy: G.tape.cy, w: G.tape.w, h: G.tape.h,
  color: P.tape, rot: G.tape.rot, imageId: 100001 });
const W = SPEC.waves, ww = G.waveWidth;
for (const [key, pts] of [['upper', W.upper], ['dot', W.dot], ['lower', W.lower]]) {
  for (let i = 0; i < pts.length - 1; i++)
    front.push(segment(N('wave.' + key + '.' + i), pts[i], pts[i + 1], P.wave, ww));
}
addAt('art641.home.camera.dot1', front, 'grp653.static.1.art641.home', 'after');

// ── 六、内嵌 Lua：删除首页四键的旧素材引用路线 ─────────────────────────────
// 655 的减负核心是「查找不落到全树 DFS」。bg 控件已删，若脚本仍按名单 sub(bid,"bg")
// 就会每会话多做 4 次无效查找（含 GetChild 失败与 miss 计数），所以两处名单同步收紧。
// 除这两处外，655 的 279 条精确路径表、索引代数、弱键缓存等减负补丁全部原样保留。
const script0 = findScriptLeaf(g).buf.toString('utf8');
let script = script0;
const PATCHES = [
  {
    id: 'A/入口层胶囊守卫名单去掉首页四键',
    from: '      "modal.exit", "modal.save", "modal.settle", "modal.cancel",\n      "home.select", "home.continue", "home.shop", "home.bag",\n',
    to: '      "modal.exit", "modal.save", "modal.settle", "modal.cancel",\n',
  },
  {
    id: 'B/上色名单排除 home.*',
    from: 'if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") then',
    to: 'if nd.kind == "button" and type(id) == "string" and not id:match("^cell%.") and not id:match("^home%.") then',
  },
];
for (const p of PATCHES) {
  const n = script.split(p.from).length - 1;
  if (n !== 1) throw Error(`补丁 ${p.id} 锚点出现 ${n} 次（应为 1）`);
  script = script.replace(p.from, p.to);
}
// 655 的精确路径表必须逐字节不变
const routeBlock = s => s.slice(s.indexOf('local STATIC_PATH_655 = {'), s.indexOf('local function path_lookup_655'));
if (routeBlock(script) !== routeBlock(script0)) throw Error('655 精确路径表被扰动');
// Lua 5.4 语法编译（写到 ASCII 临时路径，避开中文路径下 Lua 取参限制；与 655 同口径）
const tmpLua = path.join(os.tmpdir(), 'murdoku656_syntax_check.lua');
fs.writeFileSync(tmpLua, script);
const chk = spawnSync('lua', ['-e', `assert(loadfile(${JSON.stringify(tmpLua)}))`], { encoding: 'utf8' });
if (chk.status !== 0) throw Error('Lua 编译失败：' + (chk.stderr || chk.stdout || ''));
fs.unlinkSync(tmpLua);
const scriptBuf = Buffer.from(script, 'utf8');
const scriptLeaf = findScriptLeaf(g);
scriptLeaf.field.payload = scriptBuf;
scriptLeaf.field.len = scriptBuf.length;
scriptLeaf.field.sub = null;
fs.writeFileSync(path.join(DIR, '656_首页设计.lua'), scriptBuf);

// ── 七、写档 + 磁盘重读校验 ────────────────────────────────────────────────
const expected = new Map([...g.recs, ...added].map(r => [r.id, encodeMsg([r.field])]));
writeGil(g, OUTPUT, {
  label: '656 home screen design replication (primitive capsule + triangle slope)',
  expectRecs: expected.size,
  assert(t) {
    if (!findScriptLeaf(t).buf.equals(scriptBuf)) return 'script mismatch';
    for (const r of t.recs) if (!expected.get(r.id)?.equals(encodeMsg([r.field]))) return 'record mismatch ' + r.name;
    return true;
  },
});
const disk = readGil(OUTPUT);
const names = new Set(disk.recs.map(r => r.name).filter(Boolean));
for (const r of added) if (!names.has(r.name)) throw Error('磁盘缺新增层 ' + r.name);
for (const n of ['police-v12', 'home.select', 'home.continue', 'home.shop', 'home.bag',
  'home.tutorial627.hit', 'art647.home.settle.ribbon', 'art641.home.document.paper',
  'grp653.static.1.art641.home', 'art641.home.camera.body'])
  if (!names.has(n)) throw Error('关键控件丢失 ' + n);
if (!findScriptLeaf(disk).buf.equals(scriptBuf)) throw Error('磁盘内嵌脚本与交付 lua 不一致');
if (disk.recs.length !== g.recs.length + added.length) throw Error('记录数不符');
// 闸 1：被删的 4 个 bg id 在整个文件里 0 次出现（varint 字段 + 任何 ID 列表载荷）
const deadIds = new Set(deletedBg.map(x => x.id));
let dangling = 0;
const scanIds = f => {
  if (f.wt === 0 && f.num !== undefined && deadIds.has(Number(f.num))) dangling++;
  if (f.payload && !f.isText) {
    const arr = asIdList(f.payload, true);
    if (arr) for (const x of arr) if (deadIds.has(x)) dangling++;
  }
  if (f.sub) f.sub.forEach(scanIds);
};
disk.tree.forEach(scanIds);
if (dangling !== 0) throw Error('被删 bg 的 id 仍有 ' + dangling + ' 处悬空引用');
for (const d of deletedBg) {
  if (disk.recs.some(r => r.id === d.id)) throw Error('bg 记录未删除 ' + d.name);
  const parent = disk.recs.find(r => r.name === d.parent);
  const cl = parent && findChildListTop(parent.field.sub);
  if (cl && asIdList(cl.payload, true).includes(d.id)) throw Error('父 childList 仍引用 ' + d.name);
}

const audit = {
  version: 1, name: 'home-656', base: path.basename(INPUT), baseSha256: SPEC.base.sha256,
  output: path.basename(OUTPUT), outputSha256: sha(OUTPUT),
  inputBytes: fs.statSync(INPUT).size, outputBytes: fs.statSync(OUTPUT).size,
  recordsBefore: 6340, recordsAfter: disk.recs.length,
  addedRecords: added.length, deletedRecords: deletedBg.map(d => d.name),
  modifiedExisting: [...new Set(modified)].length, hidden: [...new Set(hidden)],
  scriptUnchanged: false, scriptBytes: scriptBuf.length, scriptBytesBefore: Buffer.byteLength(script0),
  scriptPatches: PATCHES.map(p => p.id), staticPathTable655ByteIdentical: true, luaCompile: true,
  deletedIdsDanglingReferences: dangling,
  backgroundUntouched: 'police-v12 组及其子控件 0 改动',
  excluded: SPEC.excluded,
  layerGroups: {
    beforePaper: back.map(r => r.name),
    afterCameraBody: cam.map(r => r.name),
    tutorialMid: ['home.tutorial627.mid'],
    afterCameraDots: front.map(r => r.name),
  },
  layerNames: added.map(r => r.name),
  checks: { diskReread: true, roundtrip: true, scriptMatchesDeliveredLua: true,
    keyControlsPresent: true, addedLayersPresent: true, deletedIdsZeroOccurrence: true,
    parentChildListsClean: true },
};
fs.writeFileSync(path.join(DIR, '656_构建审计.json'), JSON.stringify(audit, null, 2));
console.log(JSON.stringify({ output: OUTPUT, records: disk.recs.length, added: added.length,
  deleted: deletedBg.map(d => d.name), hidden: hidden.length, modifiedExisting: audit.modifiedExisting,
  scriptPatches: audit.scriptPatches, luaCompile: true, deletedIdsDanglingReferences: dangling,
  outputSha256: audit.outputSha256 }, null, 2));
