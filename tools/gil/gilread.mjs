// tools/gil/gilread.mjs —— `.gil` 读写公共模块
//
// 为什么要抽出来：gen.mjs / gen_bulk.mjs / who.mjs / check_names.mjs 各自抄了一份
// protobuf 解析，既容易不一致，也让"生成清单"要靠 PowerShell 重定向中转
// （实测被写成 UTF-16，JSON.parse 直接炸）。统一到这一个模块。
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
      out.push({ field, wt, s0, s1: p + 8 }); p += 8;
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
    else if (f.wt === 1) parts.push(Buffer.alloc(8));
    else {
      const body = f.sub !== null ? encodeMsg(f.sub) : (f.payload || Buffer.alloc(0));
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
export function setPair(pairField, x, y) {
  if (!pairField) return false;
  let a = null, b = null;
  if (pairField.sub) for (const g of pairField.sub) { if (g.field === 501 && g.wt === 5) a = g; if (g.field === 502 && g.wt === 5) b = g; }
  if (a && b) { a.f = x; b.f = y; return true; }
  pairField.sub = [{ field: 501, wt: 5, f: x }, { field: 502, wt: 5, f: y }];
  pairField.len = 12;
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
export function readGil(file) {
  const src = fs.readFileSync(file);
  const HEAD = 20;
  const hdr = []; for (let i = 0; i < 5; i++) hdr.push(src.readUInt32BE(i * 4));
  const bodyEnd = HEAD + hdr[4];
  const trailer = src.subarray(bodyEnd);
  const tree = parseMsg(src, HEAD, bodyEnd, 0);
  if (!tree) throw new Error('体解析失败：' + file);

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
            childList: findChildList(f.sub, false),
            nameField: strs.find((t) => t.payload.toString('utf8') === name) || null,
          });
          continue;
        }
      }
      walk(f.sub);
    }
  })(tree);

  return {
    file, src, hdr, bodyEnd, trailer, tree, recs,
    byName: new Map(recs.filter((r) => r.name).map((r) => [r.name, r])),
    maxId: recs.length ? Math.max(...recs.map((r) => r.id)) : 0,
    names: new Set(recs.map((r) => r.name).filter(Boolean)),
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
