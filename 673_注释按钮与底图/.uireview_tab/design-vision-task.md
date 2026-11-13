# 设计图区域识别任务（交给多模态模型执行）

当设计源只有图片（截图 / 压缩包 / 墨刀导出图）时，需要先把图片"翻译"成可比对的结构化区域列表。
本文件由 `ingest.mjs` 自动生成，agent 按下面步骤执行后，把结果写回 `design.json` 的 `elements` 字段。

## 待识别的设计图

1. `C:\Users\18182\.workbuddy\clipboard-images\clipboard-2026-11-12T00-38-15-262Z-1bd702c9.png`

## 你要做的事

逐张阅读设计图，产出该页面（或该屏）的**可见元素区域列表**。要求：

1. **只列肉眼可辨的独立元素**：按钮、标题、正文段落、图标、图片、卡片、输入框、标签、分割线、导航栏、底部栏。
2. 每个元素给出尽量准确的 **bbox**（相对该图左上角的像素坐标），单位 px。
3. 属性值是从图上"看"出来的，**必须标注为估计值**（写入时会带 `estimated: true`，报告里会标"需人工确认"）。
4. 看不清或不确定的属性填 `null`，**不要编造**。
5. 不要列出你无法定位的装饰性元素；宁可少列，不要错列。

## 输出格式（严格 JSON 数组）

```json
[
  {
    "id": "d1",
    "name": "主标题",
    "tag": "h1",
    "type": "heading",
    "text": "森林便利店",
    "rect": { "x": 24, "y": 120, "w": 240, "h": 36 },
    "styles": {
      "color": "#1F2328",
      "backgroundColor": null,
      "fontSize": 28,
      "fontWeight": 600,
      "radiusTL": 0, "radiusTR": 0, "radiusBR": 0, "radiusBL": 0,
      "borderTopWidth": 0,
      "paddingTop": 0, "paddingRight": 0, "paddingBottom": 0, "paddingLeft": 0,
      "gap": 0
    },
    "estimated": true
  }
]
```

字段说明：

| 字段 | 说明 |
|---|---|
| `type` | `text` / `heading` / `button` / `image` / `input` / `container` / `region` / `item` 之一 |
| `rect` | 相对设计图左上角的像素坐标，整数 |
| `styles.color` | 文字颜色（hex）；无文字填 `null` |
| `styles.backgroundColor` | 填充色（hex）；无填充填 `null` |
| `styles.fontSize` | 估计字号（px）；容器填 `null` |
| `styles.radius*` | 四角圆角（px），无圆角填 `0` |
| `styles.borderTopWidth` | 描边宽度（px），无描边填 `0` |
| `estimated` | **恒为 `true`**，表示这是视觉推断值而非设计文件真实值 |

## 写回

把 JSON 数组写入 `design.json` 的 `elements` 字段，并把 `tier` 改为 `A`、`estimated` 保持 `true`：

```json
{ "kind": "image", "tier": "A", "elements": [ ... ], "images": [...], "estimated": true }
```

然后重新运行：

```bash
node ui-review/scripts/align.mjs --design .uireview/design.json --capture .uireview/capture.json --out .uireview/align.json
node ui-review/scripts/detect.mjs --capture .uireview/capture.json --design .uireview/design.json --align .uireview/align.json --out .uireview/issues.json
node ui-review/scripts/report.mjs --issues .uireview/issues.json --capture .uireview/capture.json --design .uireview/design.json --align .uireview/align.json --out .uireview/report.html
```

> 档位 A 的结论属于"推断值"，报告中会标注【未能确定还原度】或"推断值，需人工确认"。
> 若要验收级硬判定，请改用 HTML 原型或 Figma / MasterGo 图层树作为设计源（档位 S）。


## 设计图主色板（脚本从图片确定性提取，填写颜色时请优先取用）

| 色值 | 占比 |
|---|---|
| `#E6B43B` | 17.8% |
| `#AF3200` | 10.1% |
| `#8C2800` | 8.4% |
| `#E8BB3D` | 7.7% |
| `#DC652A` | 6.6% |
| `#FDFDE5` | 5.2% |
| `#8C3B25` | 4.8% |
| `#FEFDF1` | 4.4% |

> 颜色请优先从以上色板取用，不要凭感觉编造色值；其余属性按图估计并标 estimated:true。
