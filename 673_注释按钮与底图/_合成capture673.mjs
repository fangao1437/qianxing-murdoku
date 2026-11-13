// 本机 Windows 上 ui-review 的 capture.mjs CLI 入口判断失效（静默 exit 0、不写 capture.json）。
// 按技能「分步执行」口径手工合成 image-kind capture.json，使 detect/report 可继续跑 B 档图像层对照。
import fs from 'node:fs';
const DIR = 'D:/新建文件夹/miHoYo Launcher/qianxing-murdoku/673_注释按钮与底图';
const ITEMS = [
  { tag: 'tab', impl: DIR + '/673_预览_tab.png', w: 240, h: 160, label: '673 注释票券（离线渲染）' },
  { tag: 'wax', impl: DIR + '/673_预览_wax.png', w: 200, h: 160, label: '673 底图火漆（离线渲染）' },
  { tag: 'tab_base', impl: DIR + '/673_基线_tab.png', w: 240, h: 160, label: '672 基线 注释票券' },
  { tag: 'wax_base', impl: DIR + '/673_基线_wax.png', w: 200, h: 160, label: '672 基线 底图火漆' },
];
for (const it of ITEMS) {
  const out = `${DIR}/.uireview_${it.tag}`;
  fs.mkdirSync(out, { recursive: true });
  const shot = `${out}/shot-impl.png`;
  fs.copyFileSync(it.impl, shot);
  const vp = String(it.w);
  const result = {
    meta: {
      target: it.impl, localFile: it.impl, resolved: it.impl,
      generatedAt: new Date().toISOString(), label: it.label,
      click: null, clickChain: [], viewports: [it.w], primary: vp, scale: 1, kind: 'image',
      note: '实现侧为 .gil 静态层离线渲染截图，无 DOM：元素级结论不可得，只有图像层对照结论有效',
    },
    views: {
      [vp]: {
        width: it.w, height: it.h, docWidth: it.w, docHeight: it.h,
        shot, full: shot, elements: [], truncated: false, hasHScroll: false, kind: 'image',
      },
    },
  };
  fs.writeFileSync(`${out}/capture.json`, JSON.stringify(result, null, 2));
  console.log('capture.json 已合成：', out, `${it.w}x${it.h}`);
}
