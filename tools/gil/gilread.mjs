// tools/gil/gilread.mjs —— `.gil` 读写公共模块
//
// 为什么要抽出来：gen.mjs / gen_bulk.mjs / who.mjs / check_names.mjs 各自抄了一份
// protobuf 解析，既容易不一致，也让"生成清单"要靠 PowerShell 重定向中转
// （实测被写成 UTF-16，JSON.parse 直接炸）。统一到这一个模块。
//
// ★★★★ 2026-10-07 血的教训（同类坑第三次发生）：**本文件不是唯一实现** ★★★★
//
//   `tools/gil/` 下共 40 个工具，**12 个不 import 本模块**，其中
//   `gen_bulk.mjs` / `gen.mjs` 各自**完整抄了一套**：
//     parse / encode / geomPairs / stateBlocks / bigIds / texts / asIdList /
//     findChildList / setChildList / findChildListTop / ensureChildListTop /
//     cloneField / setPair
//   （`roundtrip.mjs` 的独立实现是**故意**的 —— 闸门不得复用被检对象，别去"统一"它。）
//
//   ⇒ **改本文件任何一个公共函数之后，必须 grep 一遍"谁有自己的副本"**：
//        node tools/gil/check_childlist_top.mjs     # 自动比对 gen_bulk 的副本 + 扫旧写法
//        Select-String -Path tools/gil/*.mjs -Pattern 'function <你改的函数名>'
//
//   实测代价：`gen_bulk.mjs` 自带的 `ensureChildListTop` 停在旧版（`#502` 的判定条件写成
//   `wt === 0`，而记录顶层 `#502` 是**消息** ⇒ 永不命中 ⇒ 退化成 `unshift` ⇒ `#503` 落到
//   位置 0）—— 同一类"文件导不进去"因此又发生了一次。
//
// 这里的所有判据都是真机验证过的（见 docs/千星存档-gil格式.md）：
//   · 体是单个 protobuf 消息；外层头 5 个大端 u32；末尾 4 字节尾必须保留；
//   · 控件记录 = 含"≥2 组两浮点对"且含"合法控件 ID"的最小节点；
//   · 状态块 = 同时含 #504(位置) 与 #505(尺寸，两浮点) 的节点，共 4 个；
//   · 实例名 = 记录里第一个"不是已知类型名"的短字符串；
//   · 父控件 ID = 记录里第一个 varint 形式的 #504；
//   · 子控件 ID 列表 = payload 完全由"合法 ID 范围 varint"组成的字段。

import fs from 'node:fs';

export const ID_LO = 1073000000n;
export const ID_HI = 1074200000n;
export const KNOWN_TYPES = new Set(['容器节点', '客户端控件容器', '预设按钮', '交互按钮',
  '文本框', '文本视窗', '图片', '光标检测区域', '网格视窗', '按键提示',
  '模板引用控件', '界面动效', '全屏动效']);

// ── varint ────────────────────────────────────────────────────────────────
export function readVarint(b, p, lim) {
  let r = 0n, s = 0n, n = 0;
  const e = lim === undefined ? b.length : lim;
  while (p < e) {
    const x = b[p++]; n++;
    r |= BigInt(x & 0x7f) << s;
    if ((x & 0x80) === 0) return { v: r, p };
    s += 7n;
    if (n > 10) return null;
  }
  return null;
}
export function writeVarint(v) {
  const out = [];
  let x = BigInt(v);
  do { let b = Number(x & 0x7fn); x >>= 7n; if (x > 0n) b |= 0x80; out.push(b); } while (x > 0n);
  return Buffer.from(out);
}

// ── 解析 / 编码 ───────────────────────────────────────────────────────────
export function parseMsg(b, from, to, depth) {
  const out = [];
  let p = from;
  while (p < to) {
    const s0 = p;
    const t = readVarint(b, p, to);
    if (!t || t.v === 0n) return null;
    const field = Number(t.v >> 3n), wt = Number(t.v & 7n);
    if (!field) return null;
    p = t.p;
    if (wt === 0) {
      const v = readVarint(b, p, to); if (!v) return null; p = v.p;
      out.push({ field, wt, num: v.v, s0, s1: p });
    } else if (wt === 2) {
      const l = readVarint(b, p, to); if (!l) return null;
      const bs = l.p, be = bs + Number(l.v);
      if (be > to) return null;
      p = be;
      const pay = b.subarray(bs, be);
      let bad = 0;
      for (let i = 0; i < pay.length; i++) { const c = pay[i]; if (c < 9 || (c > 13 && c < 32)) bad++; }
      const isText = bad === 0 && pay.length > 0 && !pay.toString('utf8').includes('\ufffd');
      let sub = null;
      if (!isText && depth < 18 && pay.length >= 2) sub = parseMsg(b, bs, be, depth + 1);
      out.push({ field, wt, len: Number(l.v), payload: pay, isText, sub, s0, s1: p, bs, be });
    } else if (wt === 5) {
      if (p + 4 > to) return null;
      out.push({ field, wt, f: b.readFloatLE(p), s0, s1: p + 4 }); p += 4;
    } else if (wt === 1) {
      if (p + 8 > to) return null;
      // ★★★★★★ 2026-10-10 **wt1 必须留原始 8 字节** ✗✓✓
      //   ★ 原来这里**不存值**，而 `encodeMsg` 对 wt1 写的是 `Buffer.alloc(8)`（**8 个零**）✗
      //   ★ 后果：**凡是被递归到的 wt1 字段，值全部被清零** ✗ —— 静默数据损坏 ✓
      //   ★ 实测 `290.gil` 里有 **2 个** wt1 字段，**原始 8 字节非零** ✓：
      //       depth 3  #134217824  c786808004c68680
      //       depth 3  #134217829  af86808004ad8680
      //   ★ 它们**当时没被清掉**，只因它们正好住在 `#503` 子树里（见下面 `encodeMsg` 的旧 bug）
      //     ⇒ ★ 那个 bug 把整棵子树冻结了，**"因祸得福"地挡掉了这次清零** ✓
      //   ⇒ ★★ 修 `#503` 的**同时必须**修这里 ✗，否则一改 `#503`，这 16 字节立刻被清零 ✓
      //   ★ 独立闸门 `roundtrip.mjs:114` 的做法就是"回写 raw 尾部 8 字节" ✓ —— 与这里对齐 ✓
      out.push({ field, wt, raw: Buffer.from(b.subarray(p, p + 8)), s0, s1: p + 8 }); p += 8;
    } else return null;
  }
  return p === to ? out : null;
}
export function encodeMsg(fields) {
  const parts = [];
  for (const f of fields) {
    parts.push(writeVarint(BigInt(f.field) * 8n + BigInt(f.wt)));
    if (f.wt === 0) parts.push(writeVarint(f.num));
    else if (f.wt === 5) { const b = Buffer.alloc(4); b.writeFloatLE(f.f); parts.push(b); }
    else if (f.wt === 1) parts.push((f.raw && f.raw.length === 8) ? f.raw : Buffer.alloc(8));
    else {
      // ★★★★★★ 2026-10-10（二修）**`#503` 不是"一律用 payload"** ✗✓✓ —— ★ 这是"改了写不进去"的真因 ✓
      //
      //   ★ 上一版（2026-10-10 第一次修）写的是：
      //       const body = (f.sub !== null && f.field !== 503) ? encodeMsg(f.sub) : payload;
      //     ★ 它的**前提**是「`#503` 全是裸 varint 子控件 ID 列表」✗ —— ★ **这个前提是错的** ✓
      //
      //   ★ 全量实测（`_probe_503.mjs` ✓）—— ★ **`#503` 的绝大多数【是普通嵌套消息】** ✓：
      //       存档             #503(wt2) 总数    裸 ID 列表     真消息
      //       249-…-v111.gil        1640            52          1588
      //       251-…-v112.gil        1640            52          1588
      //       290.gil               2785            65          2720
      //     ⇒ ★ **96% 的 `#503` 被那条规则当成了"ID 列表"** ✗
      //     ⇒ ★★ **它们底下的整棵子树被【冻结】** ✗ —— ★ 因为 `payload` 是解析时的快照 ✓
      //     ⇒ ★★★ **在冻结子树里的任何内存修改，都会被原样丢弃** ✗✓
      //
      //   ★ 实测受害路径（`_probe_writepath.mjs` ✓，`249` 的 `clue` 模板）：
      //       tree[#9] → #502 → #505 → **#503** → #13 → #12 → #501 → #502 → #504(位置对)
      //     ★ 位置对**正好住在一个真消息 `#503` 下面** ✓
      //     ⇒ ★ `encodeMsg(g.tree)` **走到那个 `#503` 就不再往下递归** ✗
      //     ⇒ ★ 只编码那个 `#504` 对 ⇒ **字节确实变** ✓；编码整棵树 ⇒ **0 字节变化** ✗✓
      //     ⇒ ★★ 这就是"内存里改了、单独编码也对、**写出去却逐字节不变**"的全部原因 ✓✓
      //
      //   ★ 为什么以前是对的（★ 回溯 ✓）：
      //     `251-模板归零+关后两项-v112.gil`（20:49 产出）里 `clue` 的 blk[0] **确实是 (0,0)** ✓
      //     ⇒ ★ 那时 `encodeMsg` 还是 `f.sub !== null ? …` ✓ ⇒ 递归没断 ✓
      //     ★ 02:07 的这次"修 `#503`"把它改成了现在的样子 ⇒ **回归** ✗
      //
      //   ⇒ ★★ 正确判据（★ 按【类型定义】而不是按字段号 ✗）：
      //     ★ **`#503` 是子控件 ID 列表 ⟺ 它的 payload 完全由合法 ID 范围 varint 组成** ✓
      //       （这正是 `gilread` 头部文档写的判据 ✓，也是 `asIdList` 干的事 ✓）
      //     ★ 是 ID 列表 ⇒ 用 `payload` ✓（★ 保住第一次修的成果：**假消息不会被烤进文件** ✓）
      //     ★ 不是 ID 列表 ⇒ 它就是个普通消息 ⇒ **递归进 `sub`** ✓（★ 修掉冻结 ✓）
      //
      //   ★ 反例核对 ✓：`249` 有 1 处、`290` 有 3 处 `#503` 的 payload 是 ID 列表**且**
      //     `sub` 是"碰巧解析成功"的假消息 ✓ ⇒ ★ 这几处仍走 `payload` ✓ **污染依旧被堵住** ✓
      //
      //   ★ 为什么不用"重编码与 payload 相同就回写 payload"来兜底 ✗：
      //     ★ 那会让"直接改 `payload` 但没同步 `sub`"的旧工具（`setChildList` 等）**丢改动** ✗
      //     ⇒ ★ 保持"有 `sub` 就以 `sub` 为准" ✓（`roundtrip.mjs` 的独立实现也是这个语义 ✓）
      const isPlainIdList = f.field === 503 && f.payload != null && asIdList(f.payload, true) !== null;
      const body = (f.sub !== null && !isPlainIdList) ? encodeMsg(f.sub) : (f.payload || Buffer.alloc(0));
      parts.push(writeVarint(BigInt(body.length)));
      parts.push(body);
    }
  }
  return Buffer.concat(parts);
}

// ── 记录判别辅助 ──────────────────────────────────────────────────────────
export function geomPairs(fields, out) {
  for (const f of fields) {
    if (f.sub && f.sub.length === 2 && f.sub[0].wt === 5 && f.sub[1].wt === 5) out.push(f);
    if (f.sub) geomPairs(f.sub, out);
  }
  return out;
}
export function stateBlocks(fields, out) {
  for (const f of fields) {
    if (!f.sub) continue;
    const p504 = f.sub.find((g) => g.field === 504);
    const p505 = f.sub.find((g) => g.field === 505);
    if (p504 && p505 && p505.sub) {
      const fl = p505.sub.filter((x) => x.wt === 5);
      if (fl.length === 2 && f.sub.length >= 5) { out.push(f); continue; }
    }
    stateBlocks(f.sub, out);
  }
  return out;
}
export function bigIds(fields, out) {
  for (const f of fields) {
    if (f.wt === 0 && f.field === 501 && f.num > ID_LO && f.num < ID_HI) out.push(f);
    if (f.sub) bigIds(f.sub, out);
  }
  return out;
}
export function textsOf(fields, out) {
  for (const f of fields) {
    if (f.wt === 2 && f.isText && f.len <= 64) out.push(f);
    if (f.sub) textsOf(f.sub, out);
  }
  return out;
}
export function asIdList(pay, allowEmpty) {
  if (pay.length === 0) return allowEmpty ? [] : null;
  const ids = []; let p = 0;
  while (p < pay.length) {
    const v = readVarint(pay, p, pay.length);
    if (!v) return null;
    if (v.v < ID_LO || v.v > ID_HI) return null;
    ids.push(Number(v.v)); p = v.p;
  }
  return ids;
}
/**
 * ⚠️⚠️ **递归**版查找 —— 只给"读 / 诊断 / 统计"用。
 *
 *   **绝对不要**用它来决定"该往哪个字段写子控件 ID"，一律用 `findChildListTop`。
 *   `allowEmpty=true` 时更危险：连**任何空的 wt2 字段**都算命中（例如空的 `#502`），
 *   于是它会"清空"一个无关字段，而不是原型自己的子列表 ⇒ 副本认领原型子控件。
 *
 *   ★ 2026-10-07：`readGil()` 的 `rec.childList` 已经从本函数**切到 `findChildListTop`**。
 *     之前那行是 `findChildList(f.sub, false)`：因为 `allowEmpty=false`，"顶层列表存在但为空"
 *     的记录会被**跳过顶层**、继续往嵌套里钻，命中一个碰巧长得像 ID 列表的字段。
 *     实测 `223-批量.gil` 408 条记录里 **329 条有顶层列表、其中 282 条 payload 为空**，
 *     于是 `rec.childList` 有 **4 条**指向了错误字段（`cell.1.1` / `clue` 顶层存在但空，
 *     `tpl-container` / `hex` 根本无顶层列表却被"假命中"）。切到顶层版后为 **0 条**。
 */
export function findChildList(fields, allowEmpty) {
  let hit = null;
  (function scan(fs2) {
    for (const f of fs2) {
      if (hit) return;
      if (f.wt === 2 && f.sub === null && !f.isText && f.payload && asIdList(f.payload, !!allowEmpty) !== null) { hit = f; return; }
      if (f.sub) scan(f.sub);
    }
  })(fields);
  return hit;
}

/**
 * ★★★ 2026-09-30：**只找记录「顶层」的子列表字段** —— 这是修掉"导不进去"的关键。
 *
 *   出的事：`findChildList` 是**递归**的。给一个**原本没有子控件**的容器
 *   （用户手建的 `home`/`select`）挂子控件时，顶层没有 `#503`，
 *   于是它**递归到嵌套的 `#505` 块里**，找到一个"碰巧能解析成 ID 列表"的字段，
 *   就把子控件 ID 写进了那个**无关的嵌套字段**上 —— 两个后果：
 *     · 容器顶层仍然没有 `#503` ⇒ 编辑器眼里它是**空容器**（子控件全部不见）
 *     · 那个无辜的嵌套字段被覆写成 ID 数据 ⇒ **文件直接导不进去**
 *   （`board`/`action.undo` 天生有顶层 `#503`，递归"先撞上正确的那个"，
 *     所以只有我新建的容器中招 —— 这就是为什么症状只出现在新控件上。）
 *
 *   ⇒ 规则：**子列表只在记录顶层找**，找不到就新建一个，并**插在 `#502` 之后**
 *     （与 `board` 的字段顺序一致：`#501 #502 #503 #504 #505…`）。
 */
export function findChildListTop(fields) {
  // ★★★★★ 2026-10-10 **绑字段号 503** ✗✓ —— ★ 原来的判据 `f.sub === null` 会漏判 ✓
  //   ★ 被 `parseMsg` 误判的记录 `sub` **不是 null** ✗ ⇒ 原判据直接跳过 ⇒ 返回 null ✓
  //     ⇒ ★ 写入端 `if (clc)` **静默跳过** ⇒ 那几条的 `#503` 没被更新 ✓
  //     ⇒ ★★ **用户说的"控件依然丢"** ✓
  //   ★ 依据（资料员全量实测 ✓）：★ **63 处 `#503` 全是子列表** ✓、★ **候选不唯一 = 0** ✓ ⇒ 绑号安全 ✓
  for (const f of fields) {
    if (f.field !== 503) continue;
    if (f.wt !== 2 || f.isText) continue;
    if (!f.payload) continue;
    if (asIdList(f.payload, true) === null) continue;
    return f;
  }
  return null;
}

/** 顶层子列表；没有就**新建**（插在 `#502` 之后，和 `board` 同构） */
export function ensureChildListTop(rec, proto) {
  let l = findChildListTop(rec.field.sub);
  if (l) return l;
  // 用一个现成的 `#503` 当模板（字段号/类型照抄），没有就用最小结构
  const src = proto || { field: 503, wt: 2 };
  l = { field: src.field || 503, wt: 2, sub: null, num: 0n, payload: Buffer.alloc(0), len: 0, isText: false };
  // ⚠️ 插入位置必须和 `board` 同构：`#501  #502  #503  #504  #505…`
  //    注意 `#502` 在记录顶层是个**消息**（不是 varint），所以**不能**加 `wt === 0` 条件
  //    —— 我第一版就是加了它，结果匹配不上、退化成 `unshift`，`#503` 跑到了第一位。
  const at = rec.field.sub.findIndex((f) => f.field === 502);
  if (at >= 0) rec.field.sub.splice(at + 1, 0, l);
  else {
    const at501 = rec.field.sub.findIndex((f) => f.field === 501);
    rec.field.sub.splice(at501 + 1, 0, l);
  }
  return l;
}
export function setChildList(f, ids) {
  f.payload = ids.length ? Buffer.concat(ids.map((i) => writeVarint(i))) : Buffer.alloc(0);
  f.len = f.payload.length;
}
export function cloneField(f) {
  const c = { ...f };
  if (f.payload) c.payload = Buffer.from(f.payload);
  if (f.sub) c.sub = f.sub.map(cloneField);
  return c;
}
/**
 * 写"两浮点对"（位置 / 尺寸）。
 *
 * ★★★ 2026-09-30：**必须跟引擎一样做稀疏编码 —— 0 分量不写**。
 *
 *   之前的实现是：找不到现成的 `#501`/`#502` 就**重建两个分量**、并把 `len` 硬写成 12。
 *   而引擎编码时**值为 0 的字段根本不写**（见下面 `pairValue` 的注释）：
 *   原始位置 (0,0) 在文件里是**一个空的 `#504` 消息**（长度 0，一个字节 `00`）。
 *   于是"把 (0,0) 改成 (1,1)"这一步，我的版本凭空多出 12 字节（`#501`+`#502` 各 4 字节
 *   + 两个标签 + 长度前缀）—— 4 组坐标就多 48 字节。
 *   虽然那样也是**合法 protobuf**（读回来一样），但**和引擎的写法不一致**；
 *   而用户反馈"我生成的文件导不进去"，所以这里改成**尽量贴近引擎的写法**：
 *     · 值为 0 的分量 → **删掉该分量**（而不是写一个 0）
 *     · 两个分量都为 0 → 整个对字段**留空**（长度 0）
 *   这样"改坐标"产出的字节形态和引擎自己重存的一模一样。
 */
export function setPair(pairField, x, y) {
  if (!pairField) return false;
  const keep = [];
  if (x !== 0) keep.push({ field: 501, wt: 5, f: x });
  if (y !== 0) keep.push({ field: 502, wt: 5, f: y });
  pairField.sub = keep;
  pairField.len = keep.length * 4 + keep.length;   // 标签 1 字节 + float 4 字节（值都很小，标签一定单字节）
  return true;
}
export const pairOf = (block, fieldNo) => block.sub.find((g) => g.field === fieldNo) || null;
/**
 * 取"两浮点对"里第 i 个分量（0=x / 1=y）。
 *
 * ⚠️ **零值要当成 0，不能当成"没有"**（2026-09-27 踩到）：
 *    protobuf 稀疏编码里**值为 0 的字段不写**。引擎重存 `test.label` 时，
 *    位置 (0,−60) 只写了 `#502 = −60`，把 `#501 = 0` 省掉了；
 *    而 `#501 = 0` 恰好是 `#504` **唯一**的子字段时，整个 `#504` 就变成空消息。
 *    第一版要求"必须恰好 2 个浮点"，于是把 (0,−60) 读成"空" → **误报引擎丢了位置**。
 *
 * 规则：`#501`/`#502` 缺哪个，哪个就是 0；整个对字段缺失也是 (0,0)。
 */
export function pairValue(p, i) {
  if (!p || !p.sub) return 0;                     // 字段缺失 = (0,0)
  const want = i === 0 ? 501 : 502;
  const hit = p.sub.find((x) => x.field === want && x.wt === 5);
  return hit ? hit.f : 0;                          // 分量缺失 = 0
}

// ── 读一个 .gil ───────────────────────────────────────────────────────────

/**
 * ★ 从一棵**已解析好的**字段树里挑出控件记录 —— `readGil` 与 `diff_fields.mjs` 共用这一份。
 *
 *   ★ 为什么抽成导出函数：`diff_fields.mjs` 需要"这个叶子属于哪个控件" ✓，
 *     而它自己已经 `parseMsg` 过一次 ✓ ⇒ ★ 若它再调一次 `readGil`（**重新解析** ✗），
 *     拿到的会是**另一套对象** ⇒ ★ 身份 `Map` **永远匹配不上** ✗
 *     （★ 2026-10-10 实测踩到：归属全打成"(非控件记录)" ✗）
 *   ⇒ ★ 判据**只有一份** ✓：把树交给它，它返回和 `readGil().recs` 同构的记录数组 ✓
 */
export function recordsOf(tree) {
  const recs = [];
  (function walk(fields) {
    for (let i = 0; i < fields.length; i++) {
      const f = fields[i];
      if (!f.sub) continue;
      if (geomPairs(f.sub, []).length >= 2 && bigIds(f.sub, []).length >= 1) {
        let deeper = 0;
        for (const c of f.sub) if (c.sub && geomPairs(c.sub, []).length >= 2 && bigIds(c.sub, []).length >= 1) deeper++;
        if (deeper === 0) {
          let parentId = null;
          (function s2(fs2) {
            for (const g of fs2) {
              if (g.wt === 0 && g.field === 504 && parentId === null) parentId = Number(g.num);
              if (g.sub) s2(g.sub);
            }
          })(f.sub);
          const strs = textsOf(f.sub, []);
          let name = null;
          for (const t of strs) {
            const s = t.payload.toString('utf8');
            if (!KNOWN_TYPES.has(s)) { name = s; break; }
          }
          recs.push({
            field: f, holder: fields, index: i,
            id: Number(bigIds(f.sub, [])[0].num),
            parentId, name,
            names: strs.map((t) => t.payload.toString('utf8')),
            states: stateBlocks(f.sub, []),
            // ★ 2026-10-07 修正：**只认记录顶层**（原来是递归 findChildList(f.sub,false)，
            //   会因为"顶层列表为空"而往嵌套里钻 ⇒ 4 条记录指向错误字段）。
            //   注意 findChildListTop 不绑字段号，只看"顶层 + payload 能整段解析成 ID 列表"，
            //   所以编辑器自己写的 pos3/4/5 的 #503（cell.1.1 / content / murdoku-* / clue）照样命中。
            childList: findChildListTop(f.sub),
            nameField: strs.find((t) => t.payload.toString('utf8') === name) || null,
          });
          continue;
        }
      }
      walk(f.sub);
    }
  })(tree);
  return recs;
}

export function readGil(file) {
  const src = fs.readFileSync(file);
  const HEAD = 20;
  const hdr = []; for (let i = 0; i < 5; i++) hdr.push(src.readUInt32BE(i * 4));
  const bodyEnd = HEAD + hdr[4];
  const trailer = src.subarray(bodyEnd);
  const tree = parseMsg(src, HEAD, bodyEnd, 0);
  if (!tree) throw new Error('体解析失败：' + file);

  const recs = recordsOf(tree);

  return {
    file, src, hdr, bodyEnd, trailer, tree, recs,
    byName: new Map(recs.filter((r) => r.name).map((r) => [r.name, r])),
    maxId: recs.length ? Math.max(...recs.map((r) => r.id)) : 0,
    names: new Set(recs.map((r) => r.name).filter(Boolean)),
    /**
     * ★★★ 2026-09-30：**控件记录真正的"家"** —— 新增记录必须加到这里，不能加到 `tree`。
     *
     *   血的教训（查了整整一轮才找到）：我原来写 `g.tree.push(新记录)`，
     *   而 `.gil` 里**所有真实控件都住在某个子消息里**（本工程是 `/#9`），
     *   `tree` 只是最外层字段列表。后果：
     *     · 编辑器**根本读不到**我加的记录 ⇒ 每次导入后它们全部消失
     *       （用户反复反馈"home/select 没有子控件"，记录数永远是导出前的 199 条）
     *     · 顶层多出格式不符的记录 ⇒ **整个文件导不进去**
     *   ⇒ 取"多数记录所在的容器"作为规范位置。新增记录一律 push 到这里。
     */
    recHolder: (() => {
      const count = new Map();
      for (const r of recs) count.set(r.holder, (count.get(r.holder) || 0) + 1);
      let best = null, n = -1;
      for (const [h, c] of count) if (c > n) { best = h; n = c; }
      return best || tree;
    })(),
    /** 用原头里的参数 + 新体重新打包，尾原样保留 */
    pack(body) {
      const head = Buffer.alloc(20);
      head.writeUInt32BE(20 + body.length + trailer.length - 4, 0);
      head.writeUInt32BE(hdr[1], 4); head.writeUInt32BE(hdr[2], 8); head.writeUInt32BE(hdr[3], 12);
      head.writeUInt32BE(body.length, 16);
      return Buffer.concat([head, body, trailer]);
    },
    /** 从一个已写出的 .gil 里收集控件名（用于对账） */
    staticNames(buf) {
      const h = buf.readUInt32BE(16);
      const t = parseMsg(buf, 20, 20 + h, 0);
      if (!t) return null;
      const out = [];
      (function walk(fields) {
        for (const f of fields) {
          if (!f.sub) continue;
          if (geomPairs(f.sub, []).length >= 2 && bigIds(f.sub, []).length >= 1) {
            let deeper = 0;
            for (const c of f.sub) if (c.sub && geomPairs(c.sub, []).length >= 2 && bigIds(c.sub, []).length >= 1) deeper++;
            if (deeper === 0) {
              for (const s of textsOf(f.sub, [])) {
                const v = s.payload.toString('utf8');
                if (!KNOWN_TYPES.has(v)) { out.push(v); break; }
              }
              continue;
            }
          }
          walk(f.sub);
        }
      })(t);
      return out;
    },
  };
}
