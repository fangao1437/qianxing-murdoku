// tools/sim/kit.mjs —— 模拟器建树公共逻辑
//
// 坐标语义（2026-09-26 标定确认）：
//   模拟器 posX/posY = 控件**中心点**的**画布绝对坐标**（原点左下），
//   父级被完全忽略，pivot/anchor 设置不生效。
//   这与真机编辑器「位置 X, Y」输入框语义**完全一致**（位置=中心点绝对坐标，跟父级无关）。
//   → 同一份 layout-plan.json 既建模拟器、又直接抄进编辑器，不会打架。

import fs from 'node:fs';
import path from 'node:path';

export const SIM_PLUGIN = process.env.SIM_PLUGIN
  || 'C:/Users/18182/.dsh/profiles/web/node_modules/dsh-plugin-beyond-simulator/dsh-plugin/dist/index.js';
export const WORKSPACE = process.env.SIM_WORKSPACE
  || 'D:\\新建文件夹\\miHoYo Launcher\\qianxing-murdoku';
export const OUT = path.join(WORKSPACE, 'tools', 'sim', 'out');

export async function makeController() {
  const { SimulatorController } = await import('file://' + SIM_PLUGIN);
  return new SimulatorController(WORKSPACE);
}

export function loadPlan(file = 'layout-plan.json') {
  return JSON.parse(fs.readFileSync(path.join(OUT, file), 'utf8'));
}

const KIND = { container: 'container', panel: 'container', text: 'textbox', button: 'button', image: 'image' };

// 把 layout-plan.json 建进「服务端画布」，并把 Lua 脚本挂到客户端模板上。
// opts.showCursor === false 时**故意不打开**「显示常驻光标」，
// 用来验证脚本能否自己打开它（Adapter:enable_cursor）。
export function buildProject(c, plan, luaFile, opts = {}) {
  const errs = [];
  const P = (label, op) => { try { return c.patch(op); } catch (e) { errs.push(label + ' :: ' + e.message); return null; } };

  // ── 1. 客户端模板：只用来承载脚本 ───────────────────────────────────────
  const luaSource = fs.readFileSync(luaFile, 'utf8');
  let p = P('newAsset(template)', { op: 'newAsset', assetType: 'client-control-template' });
  const tplRoot = p.asset.currentTemplateId;
  for (const ch of (((p.root.children || [])[0] || {}).children || []).slice()) P('rm tpl child', { op: 'remove', id: ch.id });
  P('addScript', { op: 'addScript', path: 'client_script.lua', source: luaSource, controlId: tplRoot, controlAsset: 'client' });

  // ── 2. 服务端画布 ───────────────────────────────────────────────────────
  p = P('newAsset(server)', { op: 'newAsset', assetType: 'server-control-template' });
  const canvasRoot = (p.root.children || [])[0];
  for (const ch of (canvasRoot.children || []).slice()) P('rm canvas child', { op: 'remove', id: ch.id });

  // ★★ 关键：模拟器只在「某个祖先容器 showCursor === true」时才派发光标事件：
  //     cursorEventsEnabled(t){ for(let i=t;i;i=i.parent) if(i.kind==="container"&&i.showCursor===!0) return true; return false }
  //     showCursor 就是编辑器里容器的**「显示常驻光标」**开关。
  //     不打开它，所有按钮都是死的 —— 这正是真机上点击一直没反应的原因。
  //
  //     注意：默认**打开**是为了让 UI 回归能测交互；
  //     想验证「脚本能不能自己打开它」（Adapter:enable_cursor），
  //     传 opts.showCursor = false，模拟真机默认（没勾）的状态。
  if (opts.showCursor !== false) {
    P('canvasRoot.showCursor', { op: 'set', id: canvasRoot.id, key: 'showCursor', value: true });
  }

  const idOf = {};
  const add = (name, kind, parentId, box, extra) => {
    const r = P('add ' + name, { op: 'add', kind, name, parentId });
    if (!r) return null;
    const id = r.selectedId;
    const props = { width: box.w, height: box.h, posX: box.cx, posY: box.cy };
    if (kind === 'button') { props.raycastTarget = true; props.interactable = true; }
    for (const [k, v] of Object.entries({ ...props, ...(extra || {}) })) P(name + '.' + k, { op: 'set', id, key: k, value: v });
    return id;
  };
  const boxOf = (n) => ({ cx: n.cx, cy: n.cy, w: n.w, h: n.h });

  let made = 0;
  for (const n of plan.nodes) {
    const parentId = (n.parent && idOf[n.parent]) || canvasRoot.id;
    const kind = KIND[n.kind] || 'container';
    const vis = n.visible === false ? { visible: false } : {};
    const id = add(n.id, kind, parentId, n, vis);
    if (!id) continue;
    idOf[n.id] = id;
    made++;
  }

  // ── 3. 子控件（适配层约定）──────────────────────────────────────────────
  //   text 子控件 ← 按钮/文本的显示文字
  //   face 子控件 ← 头像/格子外观（图片）
  //   note 子控件 ← 铅笔笔记（文本）
  //   x    子控件 ← X 标记（图片）
  let subs = 0;
  const addSub = (parentName, childName, kind, box, extra) => {
    const key = parentName + '.' + childName;
    // ★ 控件的**名字**必须就是 childName（"face"/"note"/"x"/"text"），
    //   因为适配层是用 parent:GetChild("note") 找它的。
    //   之前误把名字写成 "cell.2.2.note"，导致笔记和 X 标记永远找不到。
    const id = add(childName, kind, idOf[parentName], box, extra);
    if (id) { idOf[key] = id; subs++; }
    return id;
  };

  for (const n of plan.nodes) {
    if (n.kind === 'button') {
      addSub(n.id, 'text', 'textbox', { cx: n.cx, cy: n.cy, w: n.w, h: n.h },
        { text: n.text || '', fontSize: 18 });
      // 预设按钮的外观来自状态节点引用的子控件
      for (const k of ['selectedChildId', 'hoverChildId', 'pressedChildId', 'unavailableChildId']) {
        P(n.id + '.' + k, { op: 'set', id: idOf[n.id], key: k, value: idOf[n.id + '.text'] });
      }
    }
    if (n.kind === 'text') {
      P(n.id + '.text', { op: 'set', id: idOf[n.id], key: 'text', value: n.text || '' });
      // 线索行数多（最多 18 行），字号要小一点才不挤
      const fs = n.style === 'title' ? 26 : (n.style === 'clue' ? 13 : 16);
      P(n.id + '.fontSize', { op: 'set', id: idOf[n.id], key: 'fontSize', value: fs });
    }
  }

  for (const n of plan.nodes) {
    if (!/^cell\.\d+\.\d+$/.test(n.id)) continue;
    const b = boxOf(n);
    addSub(n.id, 'face', 'image', b, { imageId: 100001 });
    addSub(n.id, 'note', 'textbox', { cx: n.cx, cy: n.cy, w: n.w - 8, h: 34 },
      { text: '', fontSize: 14, visible: false });
    addSub(n.id, 'x', 'image', b, { imageId: 100004, visible: false });
    // ★ 2026-09-28：`obj` 也必须建 —— 真机存档里格子有这个子控件（留给物件图标），
    //   默认 **visible=true + 白图 106053**，而它在 `layer_order` 里排在 `face` **之上**。
    //   模拟器原来没建它，于是「白块盖住头像」这个 bug 在模拟器里**测不出来**，
    //   只能靠用户真机截图发现（来回两轮）。
    //   ⇒ 补齐结构，让 `verify_art` 的 obj 检查真正有效。
    addSub(n.id, 'obj', 'image', { cx: n.cx, cy: n.cy, w: Math.round(n.w * 0.65), h: Math.round(n.h * 0.65) },
      { imageId: 106053, visible: true });
    for (const k of ['selectedChildId', 'hoverChildId', 'pressedChildId', 'unavailableChildId']) {
      P(n.id + '.' + k, { op: 'set', id: idOf[n.id], key: k, value: idOf[n.id + '.face'] });
    }
  }

  for (const n of plan.nodes) {
    if (!/^tray\.[A-Z]$/.test(n.id)) continue;
    addSub(n.id, 'face', 'image', boxOf(n), { imageId: 100002 });
    // ★ 2026-09-28：头像卡的**名字**子控件必须补上。
    //
    // 真机存档里它叫 `text`（我和 `face` 一起生成的），而模拟器原来只建了 `face` ——
    // 于是适配层写文字时 `sub(id,"text")` 落空，**头像卡的名字一直是规划里的静态文案**
    // （多关并集取的是最后一关，所以显示了 case_003 的"值班保安"）。
    // 表现是 `play_test` 报「头像卡 A 文案正确 ✗」，看着像脚本坏了，
    // 其实是**模拟器和真机存档不同构**。
    addSub(n.id, 'text', 'textbox', { cx: n.cx, cy: n.cy - 32, w: n.w - 4, h: 20 },
      { text: '', fontSize: 14 });
    for (const k of ['selectedChildId', 'hoverChildId', 'pressedChildId']) {
      P(n.id + '.' + k, { op: 'set', id: idOf[n.id], key: k, value: idOf[n.id + '.face'] });
    }
  }

  // ★★ 2026-09-28：**给所有按钮补 `bg` + `label` 子控件，镜像真机存档的结构**。
  //
  // 为什么必须补：这两个子控件是我用 `tools/gil/gen_btn_art.mjs` **写进 .gil** 的，
  //   **不在 `layout-plan.json` 里**。于是模拟器建出来的树**没有它们** ——
  //   结果是「模拟器根本测不了 .gil 层的美术」：
  //   我写了 verify_art.mjs 想验证"按钮有没有底图/名字"，
  //   8 条断言全报"没有子控件"，看着像代码坏了，其实是**模拟器缺件**。
  //
  //   模拟器的价值就在于"能在交付前发现外观问题"，所以它必须和真机存档同构。
  //   这里按真机的实际情况补：`bg`（图片，真机是 100108）+ `label`（文字框）。
  for (const n of plan.nodes) {
    if (n.kind !== 'button' || /^cell\./.test(n.id)) continue;
    // ⚠️ **头像卡不要 `label`** —— 真机存档里头像卡的名字子控件叫 `text`（和 `face` 一起生成的），
    //    只有**其它**按钮才有 `label`。
    //    第一版我对所有按钮都建了 `label`，于是脚本按"先找 label"的优先级把名字写进 `label`，
    //    而 `textOf` 读的是 `text` ⇒ 测出来一直是规划里的静态文案（多关并集取最后一关的
    //    "值班保安"），看着像脚本坏了，其实是**模拟器多建了一个真机没有的控件**。
    //    ⇒ 教训：模拟器要**逐字段**对齐真机存档，多一个少一个都会造成假阳性/假阴性。
    if (!/^tray\./.test(n.id)) {
      addSub(n.id, 'bg', 'image', boxOf(n), { imageId: 100108 });
      addSub(n.id, 'label', 'textbox', { cx: n.cx, cy: n.cy, w: Math.max(20, n.w - 8), h: 20 },
        { text: '', fontSize: 16 });
    }
  }

  // ★★ 2026-09-28：**素材调色板**（真机上由用户在编辑器里建，模拟器里得自己补）。
  //
  // 不补的后果：`resolve_asset("portrait.A")` 找不到 → 打警告
  //   「调色板里没有素材「portrait.A」」→ 三个关卡的通关测试各挂 1 条
  //   （`✗ 运行期没有错误日志`）。
  // 那**不是代码错**，是模拟器环境缺件 —— 但"缺件"这件事本身值得被测出来，
  // 所以这里补上，让模拟器与真机一致：真机缺了就是真缺，模拟器缺了就不再误报。
  //
  // ⚠️ 结构必须和真机一致：容器名 `assets`，`portrait.*` 是它的**直接子控件**，
  //    且每个都得有数字 `imageId`（`read_palette` 有 `type(id)=="number"` 这道门）。
  {
    const pal = add('assets', 'container', canvasRoot.id, { cx: 3000, cy: 3000, w: 10, h: 10 });
    if (pal) {
      // ⚠️ 必须把容器自己也登记进 `idOf` —— `addSub` 是靠 `idOf[parentName]` 找父控件的。
      //    第一版漏了这步，结果只有第一个子控件建上（后面找不到父级），
      //    真机/模拟器就报「调色板里没有素材 portrait.B / portrait.C」。
      idOf.assets = pal;
      // ⚠️ **必须和用户真机存档里的调色板逐项一致** ——
      //    这里的值是 2026-09-28 用 `readGil` 从 `完整界面14-9图.gil` 里读出来的真实值。
      //    少一项会误报"调色板里没有素材"，多一项又会**掩盖真机缺图**的问题。
      //
      //    ★ 特别注意 `portrait.F`：**真机上它没配图**（`imageId` 为 null），
      //      而 `read_palette` 有一道 `type(id) == "number"` 的门 ⇒ 它会被跳过。
      //      这里**照实镜像**（建控件但不给 imageId），模拟器才能提前暴露"某张图忘了配"。
      const PAL = [
        ['A', 112003], ['B', 112001], ['C', 112005], ['D', 112007], ['E', 112009],
        ['F', 112011],                      // ← 2026-09-28 用户补上了图（原来漏配，已修）
        ['G', 112013], ['H', 112060], ['V', 112053],
      ];
      let n = 0;
      for (const [k, id] of PAL) {
        n++;
        addSub('assets', 'portrait.' + k, 'image', { cx: 3000 + n * 20, cy: 3000, w: 80, h: 80 },
          id === null ? {} : { imageId: id });
      }
    }
  }

  // ── 4. 不要给容器加底图：占位图元 100005 是「白色五角星」，会盖住整屏。
  //       真实面板底图请在编辑器里配。

  const planIds = new Set(plan.nodes.map((n) => n.id));
  return { planIds, errs, made, subs, tplRoot, canvasRootId: canvasRoot.id };
}

// 把 inspect 结果里的运行树摊平成 { name → node } 便于查询
export function indexTree(ri) {
  const byName = new Map();
  const walk = (x) => {
    if (!byName.has(x.name)) byName.set(x.name, x);
    for (const k of (x.children || [])) walk(k);
  };
  for (const x of (ri.tree || [])) walk(x);
  return byName;
}

// 控件上「看得见」的文字：自己带 text 就用，否则找子控件 text
export function textOf(ri, name) {
  const n = indexTree(ri).get(name);
  if (!n) return null;
  if (n.text != null && n.text !== '') return String(n.text);
  for (const k of (n.children || [])) {
    if (k.name === 'text' && k.text != null) return String(k.text);
  }
  return n.text != null ? String(n.text) : null;
}

// 取某个控件的直接子控件（子控件名是 "face" / "note" / "x" / "text"，
// 不是 "cell.1.1.note" —— 适配层用 parent:GetChild("note") 找它们）
export function childOf(ri, parentName, childName) {
  const p = indexTree(ri).get(parentName);
  if (!p) return null;
  return (p.children || []).find((c) => c.name === childName) || null;
}

export function childText(ri, parentName, childName) {
  const c = childOf(ri, parentName, childName);
  return c == null ? null : c.text;
}

// 控件现在是否可见（编辑器里它们一直存在，靠 visible 开关）
export function visibleOf(ri, name) {
  const n = indexTree(ri).get(name);
  return n ? n.visible !== false : null;
}

export function dumpJson(file, obj) {
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, file), JSON.stringify(obj, null, 2));
}

export async function shot(c, file) {
  const s = await c.requestScreenshot();
  const data = s && (s.png || s.data || s.base64 || s.image);
  if (!data) return null;
  const out = path.join(OUT, file);
  fs.writeFileSync(out, Buffer.from(data, 'base64'));
  return out;
}

// ★★★ 2026-09-29：**从主页走进第一关**（测试用）。
//
// 为什么需要：游戏现在开机进**主页**（用户要求的流程），
// 而 `OnStart()` 是官方生命周期、**不接受参数** ——
// 所以"从外面传个 flag 跳过主页"是做不到的（我为此白改了三轮）。
// ⇒ 正确做法就是**真的走一遍主页流程**：点「选关」→ 点第 1 张卡片。
// 顺带把新流程本身测了。
export async function enterLevel(c, tick = async (dt) => { await c.play('step', { dt }); }, card = 1) {
  await c.play('click', { name: 'home.select' }); await tick(0.1);
  await c.play('click', { name: 'select.card.' + card }); await tick(0.2);
}