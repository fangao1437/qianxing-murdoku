// tools/_wip/guard_state.mjs —— 临时：记录/比对 lua/main.lua 的状态指纹（防并发改写）
import fs from 'node:fs';
import crypto from 'node:crypto';

const P = 'lua/main.lua';
const buf = fs.readFileSync(P);
const st = fs.statSync(P);
const h = crypto.createHash('sha256').update(buf).digest('hex').slice(0, 16);
const s = buf.toString('utf8');
const src = process.argv[2];
if (src === '--write') {
  fs.writeFileSync('tools/_wip/guard_state.json', JSON.stringify(
    { sha: h, size: buf.length, mtime: st.mtime.toISOString(), lines: s.split('\n').length }, null, 2));
  console.log('  已记录指纹：' + h);
} else if (src === '--check') {
  let prev = null;
  try { prev = JSON.parse(fs.readFileSync('tools/_wip/guard_state.json', 'utf8')); } catch (e) {}
  console.log('  现在：sha=' + h + '  size=' + buf.length + '  lines=' + s.split('\n').length
    + '  mtime=' + st.mtime.toISOString());
  if (prev) {
    console.log('  上次：sha=' + prev.sha + '  size=' + prev.size + '  lines=' + prev.lines
      + '  mtime=' + prev.mtime);
    console.log(prev.sha === h ? '  ★ 未变（没有别的写入者动过）' : '  ✗✗ 变了 —— 有别的写入者！');
  } else {
    console.log('  （没有基线）');
  }
}
// 结构检查：关键锚点是否都在
const anchors = [
  'if (current.frames or 0) % 300 == 0 then',
  'if scr_now == "level" and ((current.frames or 0) % 30) == 0 then',
  'if murdoku_vis_memo == nil then murdoku_vis_memo = {} end',
  'murdoku_vis_force_to = (tonumber(rawget(current, "frames")) or 0) + 60',
  'if (not forcing) and murdoku_vis_memo[nm] == want then return end',
  'current._vis_wrote = wrote',
];
console.log('\n  == 关键锚点 ==');
for (const a of anchors) {
  const n = s.split(a).length - 1;
  console.log('    ' + (n >= 1 ? '✓' : '✗') + ' ×' + n + '  ' + a.slice(0, 64));
}
// 找每个锚点的行号
console.log('\n  == 锚点行号 ==');
s.split('\n').forEach((L, i) => {
  for (const a of anchors) if (L.includes(a)) console.log('    L' + (i + 1) + ': ' + a.slice(0, 56));
});
