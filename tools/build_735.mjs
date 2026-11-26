// 从编辑器最后导出的 734.1 构建，保留原生货币和背包配置。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
const workspace = fileURLToPath(new URL('../../', import.meta.url));
const game = loadTree(path.join(workspace, '构建存档/734/734.1.gil'));
const out = path.join(workspace, '构建存档/735/735_调查币图标与双券存档.gil');
assert(!fs.existsSync(out), '735 已存在');
assert.equal(createHash('sha256').update(game.src).digest('hex'), '74e9982d20cc9530ae3d698b1de4e7318f07d8896c8affc4ab5e09a2901bc379');
function fields(nodes, ...steps) {
  let found = [{sub: nodes}];
  for (const step of steps) found = found.flatMap(f => (f.sub || []).filter(child => child.field === step));
  return found;
}
function only(list) { assert.equal(list.length, 1); return list[0]; }
const currency = only(fields(game.tree, 15, 1).filter(f => fields(f.sub, 1).some(id => Number(id.num) === 1115684865)));
const image = only(fields(currency.sub, 4, 54, 1, 1)).num;
assert.equal(Number(image), 100007);
const names = ['econ.shop.coin','econ.bag.coin'];
function imageField(g, name) {
  const rec = only(g.recs.filter(r => r.name === name));
  assert.equal(g.recs.find(r => r.id === rec.parentId)?.name, 'root');
  return only(fields(rec.field.sub, 505, 503, 84, 503));
}
for (const name of names) { const field = imageField(game,name); assert.equal(Number(field.num),100120); field.num = image; }
const leaf = findScriptLeaf(game);
let lua = leaf.buf.toString('utf8').replace(/\r\n/g,'\n');
function patch(before,after) { assert.equal(lua.split(before).length,2,before); lua=lua.replace(before,()=>after); }
lua=lua.replaceAll('构建标记 v734 / 双道具商城与背包','构建标记 v735 / 调查币图标与双券存档');
patch("      label('wallet','调查币  '..count(coins),rect(740,335,440,56),'modal.body')",`      push({id=prefix..'coin',parent='root',kind='image',visible=true,rect=rect(815,339,48,48),raycast=false})
      label('wallet','调查币  '..count(coins),rect(870,335,265,56),'modal.body')`);
patch('  a._archive_ready=true\n  local c=current.controller','  a._archive_ready=true\n  local c=current.controller\n  c.dirty=true');
patch('      a._confirmed=p; a._save_pending=nil','      a._confirmed=p; a._save_pending=nil\n      current.controller.dirty=true');
// New writers preserve hint limits. Old seven-part checkpoints default to zero.
patch('  return table.concat({"M723",core:encode_state()', '  local hints=core.hint635_used or {position=0,clue=0}\n  return table.concat({"M723",core:encode_state()');
patch('failed_accusations or 0),accused},"|")','failed_accusations or 0),accused, string.format("H%d%d",hints.position,hints.clue)},"|")');
patch('  if #parts~=7 or parts[1]~="M723" then', '  if (#parts~=7 and #parts~=8) or parts[1]~="M723" then');
patch('  core._saved_moves=moves',`  if parts[8] then
    local pos,clue=parts[8]:match('^H([01])([012])$')
    if not pos then return nil,'提示次数无效' end
    core.hint635_used={position=tonumber(pos),clue=tonumber(clue)}
  end
  core._saved_moves=moves`);
patch('local ARCHIVE_VERSION = "M734"','local ARCHIVE_VERSION = "M735"');
patch('parts[1]~=ARCHIVE_VERSION and parts[1]~="M730"','parts[1]~=ARCHIVE_VERSION and parts[1]~="M734" and parts[1]~="M730"');
patch("if parts[1]==ARCHIVE_VERSION or parts[1]=='M730' then","if parts[1]==ARCHIVE_VERSION or parts[1]=='M734' or parts[1]=='M730' then");
patch('    wallet = function() return Murdoku.wallet() end,','    on_hint_saved = function() Murdoku.save_now() end,\n    wallet = function() return Murdoku.wallet() end,');
for (const k of ['position','clue']) { const line=`    used.${k}=used.${k}+1`;patch(line,line+'\n    if self.opts.on_hint_saved then self.opts.on_hint_saved() end'); }
leaf.field.payload=Buffer.from(lua);
fs.mkdirSync(path.dirname(out),{recursive:true});
writeGil(game,out,{label:'735',expectMarker:'v735',expectDiffs:3,assert:g=>findScriptLeaf(g).buf.equals(leaf.field.payload) && names.every(name=>imageField(g,name).num===image)});
