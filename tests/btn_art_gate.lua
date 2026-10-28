--[[----------------------------------------------------------------------------
  tests/btn_art_gate.lua —— ★「按钮底图上色」的 opt-in 开关回归（2026-10-18 · 优化组 · 缺陷 1）

  背景（用户 2026-09-28 的决定，写在 `engine_adapter_qianxing.lua:2837-2841`）：
    `.gil` 里每个按钮的 `bg` 已经带好正确的 (source, id) 对 ⇒ **运行时不改**。
    当年实测：运行时再 `SetImage(bg.imageSource, 100108)` 反而把它**覆盖成紫色**
    ⇒ 所以这段被降级成 **opt-in**（`cfg.btn_art = true` 才跑）。

  真因（2026-10-18 优化组审计发现）：
    Round 45 把上色循环抽成顶层 helper `Adapter:_tray_btn_art` 时，
    调用点被留在了 `if self.cfg.btn_art == true …` 的 `end` **之外**
    ⇒ 开关从来没起过作用：**每局**把 `cfg.btn_list` 里每个按钮的 `bg` 重设成 100108。

  本用例钉四条（★ 双向）：
    ① 默认（`cfg.btn_art` 为 nil）⇒ 底图的 `imageId` **一个都不许变**
    ② 默认 ⇒ 连 `SetImage` 都**不该被调用**（不能"改了又改回来"）
    ③ 反向：`cfg.btn_art = true` ⇒ 真的重设成 `cfg.bg_image_id or 100108`（功能没被删）
    ④ 反向：`bg` 不存在的按钮 ⇒ 不许抛错、不许把别的按钮算进来

  跑法：lua tests/btn_art_gate.lua
----------------------------------------------------------------------------]]--

local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
local root = HERE .. "/.."
package.path = table.concat({
  root .. "/lua/?.lua", root .. "/lua/?/init.lua", root .. "/?.lua", package.path,
}, ";")

local Ad = require("engine_adapter_qianxing")

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  FAIL  " .. msg) end
end

-- ── 假控件（与 tests/card_fit_gate.lua 同一套写法）────────────────────────
local function ctrl(name, kids, fields)
  local x = { name = name, _kids = kids or {} }
  for k, v in pairs(fields or {}) do x[k] = v end
  x.GetChildren = function() return x._kids end
  x.GetChild = function(_, n)
    for _, k in ipairs(x._kids) do if k.name == n then return k end end
    return nil
  end
  x.FindChild = x.GetChild
  x.SetVisible = function(_, v) x.visible = v end
  x.SetActive = function(_, v) x.active = v end
  -- ★ 记调用次数：判据②"连 SetImage 都不该被调用"靠它，不看最终值（会被覆盖）
  x.SetImage = function(_, src, id)
    x.setimage_calls = (x.setimage_calls or 0) + 1
    x.imageSource, x.imageId = src, id
  end
  x.SetLocalScale = function() end
  x.GetSizeDelta = function() return x.sizeDeltaX, x.sizeDeltaY end
  x.SetSizeDelta = function(_, w, h) x.sizeDeltaX, x.sizeDeltaY = w, h end
  x.SetAnchoredPosition = function(_, px, py) x.anchoredPositionX, x.anchoredPositionY = px, py end
  x.SetAnchorMin = function() end
  x.SetAnchorMax = function() end
  x.SetPivot = function() end
  x.SetAsLastSibling = function() end
  if x.visible == nil then x.visible = true end
  if x.active == nil then x.active = true end
  return x
end

-- ── 树：root → { tray, hex.undo → bg, hex.submit → (无 bg) } ──────────────
local BG_ID, BG_SRC = 999, 7          -- 编辑器里配好的那一对（刻意不是 100108）
local undoBg = ctrl("bg", {}, { imageId = BG_ID, imageSource = BG_SRC })
local undoBtn = ctrl("hex.undo", { undoBg }, { kind = "button" })
local submitBtn = ctrl("hex.submit", {}, { kind = "button" })   -- ★ 没有 bg 子控件
local tray = ctrl("tray", {})
local rootCtl = ctrl("root", { tray, undoBtn, submitBtn })

_G.game = { GetClientUIRoots = function() return { rootCtl } end }

-- ★ 必须在 `Ad.new` **之前**建树（适配层的 `find()` 会缓存树）
local a = Ad.new({ btn_list = { "hex.undo", "hex.submit" } })


-- ── 前提：树是通的（否则下面全是"空过"）────────────────────────────────
ok(a:find("hex.undo") ~= nil, "（前提）find('hex.undo') 能找到")
ok(a:find("hex.undo") ~= nil and a:sub("hex.undo", "bg") == undoBg, "（前提）它的 bg 子控件在")

--------------------------------------------------------------------------------
-- ① + ② 默认关闭 ⇒ 底图一个字节都不动、SetImage 一次都没调
--------------------------------------------------------------------------------
ok(a.cfg.btn_art == nil, "（前提）cfg.btn_art 默认没开（实测 " .. tostring(a.cfg.btn_art) .. "）")
a:apply_btn_art()
ok(undoBg.imageId == BG_ID,
  "① 默认关闭 ⇒ 底图 imageId 没被改（实测 " .. tostring(undoBg.imageId) .. "，期望 " .. tostring(BG_ID) .. "）")
ok(undoBg.imageSource == BG_SRC,
  "① 默认关闭 ⇒ 底图 imageSource 也没被改（实测 " .. tostring(undoBg.imageSource) .. "）")
ok((undoBg.setimage_calls or 0) == 0,
  "② 默认关闭 ⇒ SetImage 一次都没被调用（实测 " .. tostring(undoBg.setimage_calls or 0) .. " 次）")

--------------------------------------------------------------------------------
-- ③ 反向：打开开关 ⇒ 真的重设（功能没被删掉）
--------------------------------------------------------------------------------
a.cfg.btn_art = true
a:apply_btn_art()
local want = a.cfg.bg_image_id or 100108
ok(undoBg.imageId == want,
  "③ 打开后底图被重设成 " .. tostring(want) .. "（实测 " .. tostring(undoBg.imageId) .. "）")
ok((undoBg.setimage_calls or 0) == 1,
  "③ 打开后 SetImage 恰好被调 1 次（实测 " .. tostring(undoBg.setimage_calls or 0) .. "）")

--------------------------------------------------------------------------------
-- ④ 反向：没有 `bg` 子控件的按钮 ⇒ 不许抛错、也不许被别人顶上
--------------------------------------------------------------------------------
local okCall, errCall = pcall(function() a:apply_btn_art() end)
ok(okCall, "④ 名单里有缺 `bg` 的按钮时不抛错", errCall)
ok(undoBg.imageId == want, "④ 缺 `bg` 的按钮不影响另一个按钮（实测 " .. tostring(undoBg.imageId) .. "）")

-- 收尾：关掉开关，避免影响同进程后续用例（本文件独立进程，稳妥起见）
a.cfg.btn_art = nil
a:apply_btn_art()
ok((undoBg.setimage_calls or 0) == 2,
  "⑤ 再关掉开关 ⇒ 不再新增 SetImage（实测 " .. tostring(undoBg.setimage_calls or 0) .. "，期望 2）")

print(string.format("\nbtn_art_gate: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
