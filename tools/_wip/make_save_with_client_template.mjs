// tools/_wip/make_save_with_client_template.mjs —— 生成"客户端资产里带 1073742330 模板"的存档
//
// ★ 为什么需要它（2026-10-06 第 28~29 轮 ✓ 两条错误给的答案 ✓）：
//   ★ `setControlGuid` 报：★「控件索引 1073742330 **已被其他控件或脚本占用**」✗
//   ★ 改服务端那个占用者报：★「**仅客户端控件或客户端控件模板允许修改索引**」✗
//   ⇒ ★★ 占用者 = 服务端资产里的 `n2001`（guid 1073742330 ✓ 我第 20 轮设的 ✓）
//     ★ 而它**改不了** ✗ ⇒ ★ **只能改文件** ✓
//   ★ 且客户端模板必须真的存在 ✓ —— ★ 会话里 `addTemplate` 造出的 `n6` 拿不到那个索引 ✓
//   ⇒ ★★★ 那就 ★ **一次把两件事都写进文件** ✓：
//     ① 服务端 `n2001/n2002/n2003` 的 guid **让开** ✓（→ 1073749010..9012 ✓）
//     ② 客户端资产 `save.assets.client.root.children` 里 ★ **加一个 `tpl-container`，
//        guid = 1073742330** ✓（★ 形状照插件 `Je()` 与 `addTemplate` 的实现 ✓）
//
// ★ 输入 / 输出（★ 不碰钉住的那份 ✓）：
//   读 `sim-save/PINNED-main-good.json` ✓ ⇒ 写 `sim-save/with-template.save.json` ✓
//
// 用法：node tools/_wip/make_save_with_client_template.mjs [--apply]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const SRC = path.join(root, 'sim-save', 'PINNED-main-good.json');
const DST = path.join(root, 'sim-save', 'with-template.save.json');
const APPLY = process.argv.includes('--apply');

const s = JSON.parse(fs.readFileSync(SRC, 'utf8'));

// ── ① 让开服务端的三个 guid ──────────────────────────────────────────────
const FREE = { 1073742330: 1073749010, 1073742331: 1073749011, 1073742332: 1073749012 };
const freed = [];
(function walk(n) {
  const g = Number(n.guid);
  if (FREE[g] !== undefined) { freed.push({ name: n.name, from: g, to: FREE[g] }); n.guid = FREE[g]; }
  for (const c of (n.children || [])) walk(c);
})(s.root);

// ── ② 客户端资产里加模板（★ 形状照 `Je()`：root 是 server-container ✓ 模板是它的子节点 ✓）──
const cl = s.save && s.save.assets && s.save.assets.client;
if (!cl) { console.log('  ✗ 没有 save.assets.client'); process.exit(1); }

// 找一个可深拷贝的样板：★ 用 `addTemplate` 造出来的那种形状（★ 这里手工给最简合法形状 ✓
//   但**必须带 transformByPlatform 四平台** ✓ 否则 `ke()` 报"需要完整的四平台布局" ✗）
function proto(guid, name, w, h) {
  const t = {};
  for (const p of ['KEYBOARD', 'TOUCHSCREEN', 'CONTROLLER_CONSOLE', 'CONTROLLER_MOBILE']) {
    t[p] = {
      scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 },
      anchorMin: { x: 0.5, y: 0.5 }, anchorMax: { x: 0.5, y: 0.5 },
      offset: { x: 0, y: 0 }, size: { x: w, y: h }, pivot: { x: 0.5, y: 0.5 },
    };
  }
  return {
    id: 'c' + guid, kind: 'container', name, guid,
    giaRelatedGuids: [], active: true, visible: true, canControllerFocus: false,
    syncAllDevices: true, giaRaw: { genericField501: 0, footerField505: 0 },
    transformByPlatform: t, children: [], scriptMappingIds: [],
  };
}

const clientRoot = cl.root && cl.root.children ? cl.root
  : { id: 'cc1', kind: 'server-container', name: '客户端控件模板', guid: 0,
      giaRelatedGuids: [], active: true, visible: true, canControllerFocus: false,
      syncAllDevices: true, giaRaw: { genericField501: 0, footerField505: 0 },
      transformByPlatform: { KEYBOARD: { scale: { x: 1, y: 1, z: 1 }, rotation: { x: 0, y: 0, z: 0 }, anchorMin: { x: 0, y: 0 }, anchorMax: { x: 1, y: 1 }, offset: { x: 0, y: 0 }, size: { x: 0, y: 0 }, pivot: { x: 0.5, y: 0.5 } } },
      children: [] };

const already = (clientRoot.children || []).some(n => Number(n.guid) === 1073742330);
if (!already) {
  clientRoot.children.push(proto(1073742330, 'tpl-container', 150, 150));
  if (!(clientRoot.children || []).some(n => Number(n.guid) === 1073742331)) clientRoot.children.push(proto(1073742331, 'tpl.stage', 80, 80));
  if (!(clientRoot.children || []).some(n => Number(n.guid) === 1073742332)) clientRoot.children.push(proto(1073742332, 'tpl.cell', 80, 80));
} else {
  // ★★★★★ 2026-10-06 第 29 轮 —— **关键修正** ✗✓
  //   ★ 第 15 轮注入的那个 `容器节点`(guid 1073742330 ✓) **早就在文件里** ✓
  //   ★ 但它**没有 `transformByPlatform`** ✗ ⇒ ★ `ke()` 的校验会拒绝它 ✗
  //     ⇒ ★★ **这就是当初"注入不生效"的真正原因** ✓✓（不是 `ke()` 不采纳 root ✗）
  //   ⇒ ★ 修法：★ **给它补全四平台形状** ✓（★ 照 `addTemplate` 造出来的那种 ✓）
  for (const c of clientRoot.children) {
    const g = Number(c.guid);
    if (g !== 1073742330 && g !== 1073742331 && g !== 1073742332) continue;
    const w = g === 1073742330 ? 150 : 80;
    const good = proto(g, g === 1073742330 ? 'tpl-container' : (g === 1073742331 ? 'tpl.stage' : 'tpl.cell'), w, w);
    // ★ 保留原 id（★ 免得破坏引用 ✓），其余全部换成合法形状 ✓
    good.id = c.id;
    Object.keys(c).forEach(k => delete c[k]);
    Object.assign(c, good);
    console.log('  ★ 升级已有模板：' + c.id + ' guid=' + g + ' → 名字 ' + c.name + '，四平台已补 ✓');
  }
}
// ★ 若客户端 root 里缺 tpl.stage / tpl.cell，也补上 ✓
for (const [g, nm, sz] of [[1073742331, 'tpl.stage', 80], [1073742332, 'tpl.cell', 80]]) {
  if (!(clientRoot.children || []).some(n => Number(n.guid) === g)) {
    clientRoot.children.push(proto(g, nm, sz, sz));
    console.log('  ★ 新增模板：' + nm + ' guid=' + g);
  }
}

cl.type = 'client-control-template';
cl.layoutSchemaVersion = 2;
cl.version = 1;
cl.meta = { name: (cl.meta && cl.meta.name) || cl.name || 'Lua实例化面板', assetType: 'client-control-template', sourceFormat: 'authoring', sourceFile: '' };
cl.canvasId = s.canvasId || 'pc-16-9';
cl.root = clientRoot;

console.log('=== 让开服务端 guid（★ ' + freed.length + ' 个 ✓）===');
for (const f of freed) console.log('  ' + f.from + ' → ' + f.to + '   「' + f.name + '」');
console.log('=== 客户端资产 ===');
console.log('  键: ' + Object.keys(cl).join(' | '));
console.log('  模板数 = ' + clientRoot.children.length);
for (const t of clientRoot.children) console.log('    guid=' + t.guid + '  ' + t.name + '  ' + t.kind +
  '  size=' + ((t.transformByPlatform && t.transformByPlatform.KEYBOARD && t.transformByPlatform.KEYBOARD.size) ? (t.transformByPlatform.KEYBOARD.size.x + 'x' + t.transformByPlatform.KEYBOARD.size.y) : '-'));

if (!APPLY) { console.log('  （只报告 ✓ 要真写加 --apply ✓）'); process.exit(0); }
fs.writeFileSync(DST, JSON.stringify(s));
console.log('  ✓ 已写 ' + path.relative(root, DST) + '（' + (fs.statSync(DST).size / 1048576).toFixed(2) + ' MB）');
console.log('  ★ 下一步：load 它 ⇒ play start ⇒ 判据「选关按钮（脚本创建）：新建 4 个」');
