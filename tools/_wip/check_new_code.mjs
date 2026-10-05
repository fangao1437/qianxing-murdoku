// tools/_wip/check_new_code.mjs —— 临时：确认新代码到底在不在 lua/main.lua 里
import fs from 'node:fs';
const s = fs.readFileSync('lua/main.lua', 'utf8');
const keys = ['_vis_memo', '_vis_force_to', '_vis_wrote', 'if (not forcing) and',
              'local forcing =', '在这里关掉上面那个', 'vis_memo == nil'];
for (const k of keys) {
  const n = s.split(k).length - 1;
  console.log('  ' + k.padEnd(26) + ' 出现 ' + n + ' 次');
}
const lines = s.split('\n');
console.log('总行数 = ' + lines.length);
console.log('\n== 含 _vis_ 的行号 ==');
lines.forEach((L, i) => { if (L.includes('_vis_')) console.log('  ' + (i + 1) + ': ' + L.trim()); });
