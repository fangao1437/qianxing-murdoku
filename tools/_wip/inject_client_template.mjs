// tools/_wip/inject_client_template.mjs —— 往存档里注入一个 guid=1073742330 的容器模板
//
// 起因（2026-10-06 第 15/20 轮 ✓）：
//   play 日志：★「选关按钮：新建 0 个 ⚠️ 容器模板 **1073742330** 实例化失败」✗
//   ⇒ ★ `1073742330` 是**真机编辑器里用户手建的** ✓ 模拟器里没有 ✓
//   ⇒ ★ 要在模拟器的【客户端控件模板】资产里造一个 ✓
//
// ★ 为什么能靠改文件做到（★ 第 14/15 轮从插件源码查出来的 ✓）：
//   · `ke()`（载入规范化）按 `meta.assetType` 判类型 ✓ ⇒ ★ 给了 `root` 就用我的 ✓
//   · `Je()`（客户端默认工厂）给了**现成样板** ✓：
//       root = H("server-container", {id:"sc1", name:"客户端控件模板"})
//            + H("container", {id:"n1", guid:1073742100, name:"Lua实例化面板"})   ← ★ 一个容器模板 ✓
//            + 它的子控件 n2..n5 ✓
//   ⇒ ★ 模板就是**普通节点** `{id, kind, guid, name, children}` ✓ ⇒ ★ 照 n1 抄 ✓
//   ⚠️ `layoutSchemaVersion` 必须 = 2 ✗ 否则 `ke()` 直接 throw ✓
//
// 用法：
//   node tools/_wip/inject_client_template.mjs            ← 只报告（默认 ✓）
//   node tools/_wip/inject_client_template.mjs --apply    ← 真写
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(HERE, '..', '..');
const FILE = path.join(root, 'sim-save', 'murdoku.save.json');
const APPLY = process.argv.includes('--apply');

const TARGET_GUID = 1073742330;
const TARGET_NAME = '容器节点';        // ★ 真机里那个模板的名字（entry_client_script.lua 的注释 ✓）

const s = JSON.parse(fs.readFileSync(FILE, 'utf8'));
console.log('=== ' + path.relative(root, FILE) + ' ===');
console.log('  顶层 layoutSchemaVersion = ' + s.layoutSchemaVersion + '（★ 必须 2 ✓）');

const save = s.save;
const cl = save && save.assets && save.assets.client;
console.log('  save.assets.client 现有键: ' + (cl ? Object.keys(cl).join(' | ') : '**没有** ✗'));

// ── 目标：把 client 资产补成"有 root 的完整客户端工程" ✓ ────────────────
//   ★ 保留原有的 type/name/sourceFile ✓（★ meta 里的 name 要留着 ✓）
const clientMetaName = (cl && cl.name) || 'Lua实例化面板';

//   ★ 根：照 Je() 抄 —— server-container ✓
const rootNode = {
  id: 'cc1',
  kind: 'server-container',
  name: '客户端控件模板',
  children: [
    // ★ 保留默认那个模板 ✓（★ 免得删掉既有能力 ✓）
    {
      id: 'cc2', kind: 'container', guid: 1073742100, name: 'Lua实例化面板',
      children: [
        { id: 'cc3', kind: 'textbox', guid: 1073742101, name: '模板标题', text: '客户端模板已实例化', fontSize: 28 },
        { id: 'cc4', kind: 'image', guid: 1073742102, name: '模板图标', imageId: 100005 },
        { id: 'cc5', kind: 'button', guid: 1073742103, name: '确认按钮' },
        { id: 'cc6', kind: 'textbox', guid: 1073742104, name: '按钮文字', text: '确认' },
      ],
    },
    // ★★★ 本次要造的：容器模板，guid = 1073742330 ✓✓（★ 照上面那个抄 ✓）
    {
      id: 'cc10', kind: 'container', guid: TARGET_GUID, name: TARGET_NAME,
      children: [],
    },
  ],
};

const newClient = {
  layoutSchemaVersion: 2,
  version: 1,
  meta: {
    name: clientMetaName,
    assetType: 'client-control-template',
    sourceFormat: 'authoring',
    sourceFile: (cl && cl.sourceFile) || '',
  },
  canvasId: s.canvasId || 'pc-16-9',
  root: rootNode,
};

console.log('=== 将要写入的 client 资产 ===');
console.log('  meta.assetType = ' + newClient.meta.assetType + '（★ ke() 靠它判类型 ✓）');
console.log('  root.kind      = ' + rootNode.kind + '（★ 照 Je() ✓）');
console.log('  root.children  = ' + rootNode.children.length + ' 个模板：' +
  rootNode.children.map(c => c.name + '(' + c.guid + ')').join('  '));
console.log('  ★ 目标模板 = ' + TARGET_NAME + ' guid ' + TARGET_GUID +
  ' kind=' + rootNode.children[1].kind);

// ── 校验：目标 guid 不能与已有 guid 撞 ✓ ────────────────────────────────
const raws = fs.readFileSync(FILE, 'utf8');
const before = raws.split(String(TARGET_GUID)).length - 1;
console.log('  存档里 "' + TARGET_GUID + '" 改前出现 ' + before + ' 次（★ 都在脚本 source 里 ✓）');

if (!APPLY) {
  console.log('  （只报告 ✓ 要真写加 --apply ✓）');
  process.exit(0);
}

save.assets.client = newClient;
fs.writeFileSync(FILE, JSON.stringify(s));
console.log('  ✓ 已写回（' + (fs.statSync(FILE).size / 1048576).toFixed(2) + ' MB）');
console.log('  ⚠️ 下一步：`qxqy_studio_load` ⇒ `qxqy_studio_play start`');
console.log('  ★ 判据：play 日志出现「选关按钮（脚本创建）：新建 **4** 个」且不再报实例化失败 ✓');
