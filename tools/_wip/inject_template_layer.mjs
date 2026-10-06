// tools/_wip/inject_template_layer.mjs —— 把真机 `208.gil` 的模板补进模拟器存档
//
// ★ v2（2026-10-06 第 20/20 轮 ✓）—— v1 的判定**是错的** ✗ 这里修掉：
//   ★ v1 只比 **guid 数值** ✗ ⇒ 报"四个都已存在"✓
//   ★ 而独立复核给出真相 ✗：★
//     · `1073742330` 在模拟器里是**一个 `text` 控件** ✗（真机：`tpl-container` ✓）
//     · `1073741876` 在模拟器里是 **`action.back.hex1`** ✗（真机：`cell.1.1` 模板 ✓）
//   ⇒ ★★★ **两边的 guid 编号体系完全不同** ✓✓
//     ★ 而日志原话「**它可能不是「客户端控件模板」**」✓ —— ★ **系统早就说对了** ✓
//
// ★ v2 做三件事：
//   ① 判存在 ⇒ **按【名字】判** ✓（★ 不再只看 guid ✗）
//   ② 腾 guid ⇒ 占着目标 guid 但**名字不对**的控件 ⇒ ★ 改成一个**没人用的新 guid** ✓
//      （★ 安全 ✓：Lua 侧全部**按名字**找控件 ✗ 不按 guid ✓）
//   ③ 补节点 ⇒ 按 `208.gil` 的**实测**名字/类型/尺寸 ✓ 建四个 ✓
//
// ★ 尺寸照 `208.gil` 实测抄 ✓（who.mjs ✓ 不猜 ✓）：
//   `1073742330 tpl-container` 150×150 · `1073742331 tpl.stage` 80×80
//   `1073742332 tpl.cell` 80×80 · `1073741876 cell.1.1` 88×88（★ 含 `content` 135×135 ✓）
//
// 用法：
//   node tools/_wip/inject_template_layer.mjs            ← 只报告
//   node tools/_wip/inject_template_layer.mjs --apply    ← 真写
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = path.join(root, 'sim-save', 'murdoku.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(FILE, 'utf8'));

const all = [];
(function walk(n) { all.push(n); for (const c of (n.children || [])) walk(c); })(s.root);
const byId = new Map(all.map(n => [String(n.id), n]));
const byName = new Map(all.map(n => [String(n.name), n]));

const n1 = byId.get('n1'), n12 = byId.get('n12');
console.log('=== 宿主 ===');
console.log('  n1  = ' + (n1 ? (n1.name + ' 子=' + (n1.children || []).length) : '**找不到** ✗'));
console.log('  n12 = ' + (n12 ? (n12.name + ' 子=' + (n12.children || []).length) : '**找不到** ✗'));
if (!n1 || !n12) { console.log('  ✗ 宿主缺失'); process.exit(0); }

// ★ 要补的四个（★ 名字/类型/尺寸/父级 全照 208.gil 实测 ✓）
const spec = [
  { guid: 1073742330, name: 'tpl-container', kind: 'container', w: 150, h: 150, host: n1, why: 'cfg.stage.prefab（阻塞点）' },
  { guid: 1073742331, name: 'tpl.stage', kind: 'container', w: 80, h: 80, host: n12, why: '场景层' },
  { guid: 1073742332, name: 'tpl.cell', kind: 'container', w: 80, h: 80, host: n12, why: '场景层' },
  { guid: 1073741876, name: 'cell.1.1', kind: 'button', w: 88, h: 88, host: n1, why: 'cfg.cells.prefab' },
];

// ★ ① 按【名字】判存在 ✓（★ v1 的错就在这里 ✗）
console.log('=== ① 按名字判存在（★ v2 的关键修正 ✓）===');
const todo = [];
for (const t of spec) {
  const hit = byName.get(t.name);
  console.log('  ' + String(t.guid).padEnd(12) + t.name.padEnd(16) +
    (hit ? ('★ 名字已存在 ⇒ 跳过（实际 guid=' + hit.guid + ' kind=' + hit.kind + '）') : '名字不存在 ⇒ 要补 ✓'));
  if (!hit) todo.push(t);
}

// ★ ② 腾 guid：占着目标 guid 但名字不对的 ⇒ 改成没人用的新 guid ✓
console.log('=== ② guid 冲突（★ 模拟器的编号体系与真机不同 ✓）===');
const used = new Set(all.filter(n => n.guid).map(n => Number(n.guid)));
const wantGuids = spec.map(t => t.guid);
let next = 1073749000;
const conflicts = [];
for (const n of all) {
  const g = Number(n.guid);
  if (!wantGuids.includes(g)) continue;
  const want = spec.find(t => t.guid === g);
  if (String(n.name) === want.name) continue;              // ★ 名字对 ⇒ 不冲突 ✓
  conflicts.push({ node: n, guid: g, shouldBe: want.name });
}
for (const c of conflicts) {
  while (used.has(next)) next++;
  console.log('  ' + String(c.guid).padEnd(12) + '现在占用者 = ' + JSON.stringify(c.node.name) +
    '（kind=' + c.node.kind + '）  ★ 它应该是 ' + JSON.stringify(c.shouldBe) + ' ⇒ 改 guid 到 ' + next);
  used.add(next);
  if (APPLY) c.node.guid = next;
  next++;
}
if (conflicts.length === 0) console.log('  ✓ 没有冲突');

// ★ ③ 补节点
console.log('=== ③ 要补的 ===');
console.log('  共 ' + todo.length + ' 个' + (todo.length ? '：' + todo.map(t => t.name + '(' + t.guid + ')').join('  ') : ''));

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }

let idn = 2001;

// ★★★★★ 2026-10-06 第 21 轮修正 ✗✓ —— **必须克隆已有节点，不能手搓** ✓
//   起因：★ `qxqy_studio_load` 直接报错 ✗：
//     「`tpl.stage.transformByPlatform: 需要完整的四平台布局`」✓
//   ★ 因为我手搓的节点只有 6 个键 ✗ 而标准节点有 **16 个** ✓：
//     id|kind|name|guid|giaRelatedGuids|active|visible|canControllerFocus|syncAllDevices
//     |**giaRaw**|**transformByPlatform**|children|scriptMappingIds|isolateNavigation
//     |disableKeyEventPassthrough|disableCursorEventPassthrough|showCursor
//   ⇒ ★★ 做法：★ **深拷贝一个已有节点（用 `n31` = stage ✓ 因为它四平台齐全 ✓）** ✓
//     ★ 再覆盖 `id/name/guid/kind/children` ✓ + 按真机实测设 `size` ✓
//   ★（★ 这正是仓库 `tools/gil/gen.mjs` 的"克隆原型记录 + 打补丁"思路 ✓）
const PROTOTYPE = byId.get('n31');
if (!PROTOTYPE) { console.log('  ✗ 找不到原型 n31 ⇒ 无法克隆'); process.exit(1); }

function makeNode(id, kind, name, guid, w, h) {
  const n = JSON.parse(JSON.stringify(PROTOTYPE));   // ★ 深拷贝 ⇒ 四平台/giaRaw 全带上 ✓
  n.id = id; n.kind = kind; n.name = name; n.guid = guid;
  n.children = [];
  // ★ 尺寸照真机实测改 ✓（★ 四平台都改 ✓ 否则平台间会不一致 ✓）
  for (const plat of Object.keys(n.transformByPlatform || {})) {
    const t = n.transformByPlatform[plat];
    if (t && t.size) { t.size.x = w; t.size.y = h; }
    if (t && t.offset) { t.offset.x = 0; t.offset.y = 0; }
  }
  return n;
}

for (const t of todo) {
  const node = makeNode('n' + (idn++), t.kind, t.name, t.guid, t.w, t.h);
  if (t.guid === 1073741876) {
    node.children.push(makeNode('n' + (idn++), 'container', 'content', 1073741888, 135, 135));
  }
  t.host.children.push(node);
}

fs.writeFileSync(FILE, JSON.stringify(s));
console.log('  ✓ 腾 guid ' + conflicts.length + ' 个 · 补节点 ' + todo.length + ' 个（存档 ' + (fs.statSync(FILE).size / 1048576).toFixed(2) + ' MB）');
console.log('  ⚠️ 下一步：`qxqy_studio_load` ⇒ `qxqy_studio_play start`');
console.log('  ★ 判据：「选关按钮（脚本创建）：新建 **4** 个」✓ 且不再报「容器模板 1073742330 实例化失败」✓');
