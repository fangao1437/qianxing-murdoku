--[[----------------------------------------------------------------------------
  engine_adapter_qianxing.lua —— 千星奇域 7.1 客户端脚本绑定层（按官方 API 实现）

  依据：官方《客户端控件API文档》 mhtakr07vej4 与《客户端控件和客户端脚本》 mhbgxf0nynww
        速查见 docs/7.1-脚本API速查.md

  交互约定（重要）：官方**只有** CursorDown/Up/Click/Drag，**没有长按事件**。
  本工程因此不用长按，改为「**单击 = 铅笔笔记 / 双击 = 放置**」：
    · 适配层只负责把 CursorClick 转成 {action="click"} 事件
    · 双击判定与"待定单击延后落地"由 ui_controller 用累加时钟处理
  这样也省掉了自造长按阈值带来的手感问题。

  与官方 API 的对应关系（全部是文档里存在的接口，没有猜的名字）：
    控件查找   game.GetClientUIRoots() + ctrl:GetChildren()/GetChild(name)
    动态创建   game.InstantiateClientUIControl(prefabIndex, parent)
    销毁       game.DestroyClientUIControl(ctrl)
    文本       textBox.text = "..."
    图片       img:SetImage(img.imageSource, imageId)   -- 沿用编辑器里配的来源
    显隐       ctrl:SetVisible(bool) / SetActive(bool)
    可用       button.interactable = bool
    点击       button:AddCursorEventListener(Enum.CursorEventType.CursorClick, cb)
    动画       game.Tween(ctrl, {localScaleX=…, localScaleY=…}, 时长):Play()
    发信号     game.ServerSignal(name) → AddInt/AddString/AddBool → SendSignal()
    收信号     script:RegisterServerSignalHandler(name, cb)
    计时       OnUpdate(dt) 自行累加（沙箱没有 os 库）
    音效       game.PlayAudio2D(id)      本地化  game.GetText(textMapId)

  控件命名约定（编辑器里照这个命名，脚本按名字找）：
    root / topbar / left / tray / clues / legend / board / actions / right / modal / intro
    cell.<行>.<列>   及可选子控件：face / note / x / wall.up|down|left|right / door.up|down|left|right
    tray.<角色id>    clue.<序号>    action.* / tool.* / action.q.*
    hud.title / hud.subtitle / hud.timer / hud.moves / hud.violations / hud.toast / hud.share
--]]--

local M = {}

M.VERSION = "1.0.0"

-- 框架约定的信号名（节点图侧按同名接线）
M.SIGNALS = {
  READY      = "murdoku/ready",
  PLACE      = "murdoku/place",
  CLEAR      = "murdoku/clear",
  SUBMIT     = "murdoku/submit",
  ACCUSE     = "murdoku/accuse",
  SOLVED     = "murdoku/solved",
  SAVE       = "murdoku/save",
  RESTORE    = "murdoku/restore",
  SYNC_STATE = "murdoku/sync",
}

-- 信号参数按顺序添加；这里给出"信号名 → 字段顺序"，收信号时按它还原成字典
M.SIGNAL_SCHEMA = {
  [M.SIGNALS.READY]      = { "level_id", "rows", "cols", "piece_count" },
  [M.SIGNALS.PLACE]      = { "who", "r", "c" },
  [M.SIGNALS.CLEAR]      = { "who" },
  [M.SIGNALS.SUBMIT]     = { "ok" },
  [M.SIGNALS.ACCUSE]     = { "thief", "has_accomplice", "correct" },
  [M.SIGNALS.SOLVED]     = { "level_id", "elapsed", "moves", "failed_accusations" },
  [M.SIGNALS.SAVE]       = { "level_id", "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.RESTORE]    = { "state_code", "moves", "elapsed", "solved" },
  [M.SIGNALS.SYNC_STATE] = { "who", "r", "c" },
}

----------------------------------------------------------------------------
-- 官方枚举的安全取值（缺失时返回 nil，调用点全部降级而不是崩）
----------------------------------------------------------------------------

local function E(path, default)
  local cur = Enum
  if cur == nil then return default end
  for name in tostring(path):gmatch("[^%.]+") do
    cur = cur[name]
    if cur == nil then return default end
  end
  if cur == nil then return default end
  return cur
end

----------------------------------------------------------------------------
-- 适配器
----------------------------------------------------------------------------

local Adapter = {}
Adapter.__index = Adapter
M.Adapter = Adapter

function M.new(cfg)
  cfg = cfg or {}
  -- ★★ 防呆：把 `cfg.cells.<调试开关>` 上提到顶层。
  --
  -- 2026-09-27 踩过：`debug_key` / `debug_image` 被加进了 `cfg.cells = {…}` 里
  -- （挨着本来就属于 cells 的 `debug_signal`），而读取处写的是 `self.cfg.debug_key`
  -- → 永远 nil → **诊断一行都不打，白白多跑了一轮真机**。
  -- 这类"开关加了但没生效"的错最难查（日志里什么都没有，看着像功能没触发）。
  -- 所以这里统一兜一层：cells 里有、顶层没有的就上提；再把生效值打出来。
  if type(cfg.cells) == "table" then
    for _, k in ipairs({ "debug_key", "debug_image", "debug_event" }) do
      if cfg[k] == nil and cfg.cells[k] ~= nil then cfg[k] = cfg.cells[k] end
    end
  end
  local self = setmetatable({}, Adapter)
  self.cfg = cfg
  if print then
    -- ⚠️ 这里必须用字面量：`PREFIX` 是在**本函数之后**才 `local` 的，
    --    在这里引用它拿到的是全局 nil，`nil .. str` 会抛错。
    print("[murdoku] 调试开关：debug_key=" .. tostring(cfg.debug_key)
      .. " debug_image=" .. tostring(cfg.debug_image)
      .. " debug_event=" .. tostring(cfg.debug_event)
      .. " debug_click=" .. tostring(cfg.debug_click)
      .. "（nil = 关；debug_event/debug_click 为 nil 时按「开」处理）")
  end
  self.signals = M.SIGNALS
  if cfg.signals then
    for k, v in pairs(cfg.signals) do self.signals[k] = v end
  end
  self.controls = {}       -- 节点 id -> 引擎控件（**只记命中**，见 find）
  -- ★★★★★ 2026-10-05 **未命中也要记**（负缓存）—— 见 `Adapter:find` 上面那段大注释。
  --   实测（`tests/grid_cost.lua`）：不记未命中时，**本关根本没有的名字**每帧都要重走一遍
  --   深树 ⇒ 300 帧里 `action.back` 白跑 3000 次（每次约 470 个 `GetChildren`）。
  --   这里只放"这一代确实不在树上"的名字；任何"树变了"的事件都会整代作废
  --   （`Adapter:invalidate_lookups`）。
  self._misses = nil       -- name -> 过期时间戳（self.clock）｜ false = 本代内不再重搜
  self._lookup_hits = 0    -- 累计"真的搜到过东西"的次数（= 树已经有控件了；见 find 里的启动期规则）
  self._lookup_gen = 0     -- 第几代（只用于日志/诊断）
  -- ★★★ `enforce_hidden_subtrees` 的开关：**事件驱动**，不再每帧跑。
  --   第一帧必须跑一次（那时树刚就绪，模板子控件可能还没实例化出来）。
  self._subtree_dirty = true
  -- ★★★★★ 2026-10-05 `enable_raycast` 的**收敛/放弃**账（第 (3) 条每帧成本）。
  --   见 `Adapter:enable_raycast` 上面那段注释：它原来每 20 帧无条件整树 walk 一遍，
  --   实测 300 帧 = 15 趟 = 7020 次 `GetChildren`（23.4/帧），而这件事是**幂等**的。
  self._ray = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
  self.handlers = {}       -- 控件 id -> **规划节点**（只做 parent/rect 反查；一个 id = 一个引擎控件）
  -- ★★★★★ 2026-10-05 **事件表按「规划节点」记，不按控件 id。**
  --
  --   为什么（可复现，`tests/_wip/probe_event_table.lua`）：
  --     `build_layout` 里**同一个 id 会出现在两个节点上**（最典型：`action.back` ——
  --     一个挂 `topbar`（「返回菜单」/ `back_confirm`）、一个挂 `right`（「返回列表」/ `back`），
  --     见 ui_controller 的 L1759 与 L2411）。
  --     而事件表原来是 `self.handlers[id]`、`set_property` 的 event 分支直接
  --     `h.event = value` ⇒ **一份表、两个节点轮流写** ⇒ 后写的把先写的吃掉：
  --     实测两个节点都发过（`back_confirm` → `back`），表里最后只剩 `back`，
  --     `topbar` 那一份**静默丢失**（不报错、看不出来）✗
  --   ⇒ 键改用**规划节点**（`id \1 父容器 \1 同(id,父容器)的第几次出现`）——
  --     这就是 `ui_controller` 属性账本**已经在用的同一把 `node_key`**（见那里的
  --     `local function node_key(n)`），由渲染循环算好后传进来，**不在这里另造一套**。
  --     「一条规则两个权威」是本项目刚在 BOM 上栽过的坑。
  --   ⚠️ `self.handlers`（按 id 的节点登记表）**保持不变**：`rect` 分支要用
  --      `handlers[pid]` 反查**父控件**（`pid` 是控件 id，不是规划节点键），
  --      那里本来就该按 id —— 一个 id 只有一个引擎控件。
  self.events = {}         -- 规划节点键 -> 事件表
  -- ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：派发改用「认领者」** ——
  --   控件 id -> **第一个**为这个 id 写 event 的规划节点键（= 这颗控件的语义归属者）。
  --
  --   为什么不是"最后写的那个赢"（三条硬证据，全部在同一份源码里，可现场核对 ✓）：
  --     · `ui_controller.lua:1389` 左上那颗 ↰ 图标按钮（`hex.back`）声明的是 `back_confirm`
  --       ⇒ 点它 **先弹 ✓/✗**（`ui_controller.lua:854`：`a == "back_confirm"` ⇒
  --       `self.pending = { action = "back" }` ⇒ 进确认状态机）。
  --     · `ui_controller.lua:1761` **topbar** 节点声明的同样是 `back_confirm`（「返回菜单」↰）。
  --     · `ui_controller.lua:2412` **right** 节点声明的是 `back`（「返回列表」，`tab` 样式）。
  --   ⇒ 现状**自相矛盾** ✗：左上那颗 ↰ 图标（`hex.back`）**先弹 ✓/✗**，
  --     而这颗 `action.back` 按钮却**直接跳列表**（因为派发取的是"最后写的"= `right` 的 `back`）
  --     ⇒ **同 id 的两颗按钮两种语义**，差别只取决于你点的是哪一颗。
  --     ⚠️ 别把键盘那条混进来：`KB_ACTIONS` 里 Key42 → `"back"`，走的是
  --        `close_modal` / `level_list`（`ui_controller.lua:766-771`），**不是** `back_confirm`。
  --   ⇒ B2：派发给**认领这颗控件的那个节点**（先写的那个 = `topbar`）⇒ **点击与 ↰ 一致**（都先弹 ✓/✗）。
  --
  --   ⚠️ 规则：**只认第一次**（见 `set_property` 的 `key == "event"` 分支里那行 `== nil` 判断）
  --      ⇒ 后续任何节点再写都不换人 ⇒ 派发**稳定、可预测**，不受"这一帧谁后渲染"影响。
  --   ⚠️ `forget_events_of(id)` 必须**连它一起清**：控件销毁重建后，新控件要能重新认领
  --      （否则会认领到那个**已经不存在**的旧规划节点 ⇒ 派发读到 nil）。
  self.event_claim = {}
  -- ⚠️⚠️ `event_latest` **保留，但已不是派发依据**（**纯诊断记录** ✓）：
  --   id -> **最近一次**写 event 的节点键。留着它是为了排查"这颗控件上谁后写过事件"
  --   （例如回答"属性/文字实际是哪个节点的"—— `right` 与 `topbar` 写的是**同一个控件**）。
  --   ★ **任何人都不许再拿它做派发** ✗ —— 那正是 B2 要修掉的行为（"最后写的赢"）。
  self.event_latest = {}
  self.subs = {}           -- "id.child" -> 子控件（或 false）
  self.timers = {}
  self.clock = 0
  self.state = {}          -- 脚本内本地状态（跨场景要靠信号+服务器）
  self.warned = {}
  self.on_input = nil
  self.apply_rect = cfg.apply_rect == true   -- 默认不动位置（布局在编辑器里定）
  return self
end

----------------------------------------------------------------------------
-- 日志
----------------------------------------------------------------------------

local PREFIX = "[murdoku] "

function Adapter:log(msg)
  if print then print(PREFIX .. tostring(msg)) end
end

function Adapter:err(msg)
  if printerr then printerr(PREFIX .. tostring(msg)) end
end

function Adapter:warn_once(key, msg)
  if self.warned[key] then return end
  self.warned[key] = true
  self:err(msg)
end

-- ════════════════════════════════════════════════════════════════════════
-- 「控件未找到」—— 收集 + **分组汇总**，不再逐个刷屏
--
-- 为什么改：真机首次开局会缺 80+ 个控件（界面还没搭完），原来每个控件打一行，
-- 结果 80 多行把真正有用的信息（**缺的是哪几类**）淹没了，而且每行都是同一句话。
-- 2026-09-26 12:20 的真机日志就是这么一大坨。
--
-- 现在：缺谁只记账，等第一次渲染完由 `report_missing()` 打一次分组汇总，例如
--   [murdoku] 这些控件还没建（共 86 个，按类分组）：
--   [murdoku]   cell.*       ×24   cell.1.2 / cell.1.3 …
--   [murdoku]   clue.N       ×7    clue.1 / clue.2 …
-- 完整名单与坐标在 docs/控件坐标表-1600x900.md，日志里不必重复 150 行。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:_note_missing(id)
  if id == nil then return end
  self.missing = self.missing or {}
  if self.missing[id] == nil then
    self.missing[id] = true
    self.missing_count = (self.missing_count or 0) + 1
  end
end

-- 把一个控件 id 归到"类"：cell.1.2 → cell.* ／ clue.7 → clue.N ／ hud.title → hud.*
local function missing_group(id)
  local s = tostring(id)
  if s:match("^cell%.[%d]+%.[%d]+$")  then return "cell.*"  end
  if s:match("^clue%.[%d]+$")         then return "clue.N"  end
  if s:match("^tray%.[%w_]+$")        then return "tray.*"  end
  if s:match("^ruler%.[cr]%.[%d]+$")  then return "ruler.*" end
  if s:match("^modal%.")              then return "modal.*" end
  if s:match("^intro%.")              then return "intro.*" end
  if s:match("^action%.")             then return "action.*"
  end
  local head = s:match("^([%w_]+)%.")
  if head ~= nil then return head .. ".*" end
  return s
end

-- 打一次分组汇总。`force=true` 可以再打一次（清单有变化时用）。
function Adapter:report_missing(force)
  if self.missing == nil then return 0 end
  if self.missing_reported and not force then return 0 end
  self.missing_reported = true

  local groups, order = {}, {}
  for id in pairs(self.missing) do
    local g = missing_group(id)
    if groups[g] == nil then
      groups[g] = { n = 0, sample = {} }
      order[#order + 1] = g
    end
    groups[g].n = groups[g].n + 1
    if #groups[g].sample < 3 then groups[g].sample[#groups[g].sample + 1] = id end
  end
  table.sort(order, function(a, b)
    if groups[a].n ~= groups[b].n then return groups[a].n > groups[b].n end
    return a < b
  end)

  if printerr then
    printerr("[murdoku] 这些控件还没建（共 " .. tostring(self.missing_count or 0)
      .. " 个，按类分组）：")
    for i = 1, #order do
      local g = order[i]
      local gd = groups[g]
      local samp = table.concat(gd.sample, " ")
      if gd.n > #gd.sample then samp = samp .. " …" end
      printerr("[murdoku]   " .. g .. "  ×" .. gd.n .. "   " .. samp)
    end
    printerr("[murdoku] 完整 150 个控件的名字/坐标/父子关系：docs/控件坐标表-1600x900.md")
  end
  return self.missing_count or 0
end

----------------------------------------------------------------------------
-- 控件查找（只用文档里的接口）
----------------------------------------------------------------------------

local function find_in(ctrl, name, depth)
  if ctrl == nil or depth > 16 then return nil end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname == name then return ctrl end
  -- ⚠️ GetChildren 一定要包 pcall：真机上万一某个节点不提供这个方法，
  --    不包的话 find 会整个抛错，被上层 pcall 吞掉后表现成"控件未找到" ——
  --    那种误判极难查（明明建了却说找不到）。
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do
      local hit = find_in(children[i], name, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end

-- 收集"名字差一点"的候选。
-- 用途：真机上最常见的失败是名字不完全一致（多一个 `(1)` 后缀、大小写不同、
-- 前后有空格）。光说"找不到"没用，把这个名字的近似者列出来就一目了然了。
local function collect_names_in(ctrl, depth, out, limit)
  if ctrl == nil or depth > 16 or #out >= limit then return end
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and type(cname) == "string" and cname ~= "" then out[#out + 1] = cname end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do collect_names_in(children[i], depth + 1, out, limit) end
  end
end

local function norm_name(s)
  s = tostring(s or ""):lower()
  s = s:gsub("%s+", "")
  return s
end

-- 返回与 name "近似"的现有控件名（去掉空格/大小写后相等，或互为子串）
function Adapter:near_names(name, limit)
  limit = limit or 8
  local out = {}
  if game == nil or game.GetClientUIRoots == nil then return out end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then return out end
  local all = {}
  for i = 1, #roots do collect_names_in(roots[i], 0, all, 2000) end
  local want = norm_name(name)
  if want == "" then return out end
  for i = 1, #all do
    local have = norm_name(all[i])
    if have == want or have:find(want, 1, true) or want:find(have, 1, true) then
      out[#out + 1] = all[i]
      if #out >= limit then break end
    end
  end
  return out
end

-- 兜底一：按"结构路径"找控件（当编辑器里改不了控件名称时用）
--   路径写法：从 UI 根算起的一串 1-based 子节点序号，例如 "1/2/3"
--             = 第 1 个根 → 它的第 2 个子控件 → 再它的第 3 个子控件
local function control_by_path(roots, path)
  local idx = {}
  for seg in tostring(path):gmatch("%d+") do idx[#idx + 1] = tonumber(seg) end
  if #idx == 0 then return nil end
  local cur = roots[idx[1]]
  for i = 2, #idx do
    if cur == nil then return nil end
    local kids = cur:GetChildren()
    if kids == nil then return nil end
    cur = kids[idx[i]]
  end
  return cur
end

-- ════════════════════════════════════════════════════════════════════════
-- ★★★★★ 2026-10-05 **控件名缓存的两半**：命中缓存（`self.controls`）+ **未命中缓存**（`self._misses`）
--
--   为什么要加"未命中"这一半（不是猜的，是量出来的）：
--     `tests/grid_cost.lua` 在**关卡里 300 帧**（dt=1/60，网格视窗在跑）测到：
--       · `GetChildren` 被访问 **1,565,043** 次 ≈ **5217/帧**
--       · 其中 `action.back` 一个名字就占 **280,800** 次 = **936/帧**（搜空×10/帧）
--       · 另外 9 个"本关根本没建"的容器名（board/left/right/topbar/tray/actions/
--         intro/modal/select）各 468 次/帧 —— 全是**每帧重走一遍深树**换来的同一个 nil
--     ⇒ 一次搜空的代价 = 把整棵控件树（真机约 150 个控件）走完，而结果**永远是 nil**，
--       下一帧还会一模一样地再走一遍。这正是用户说的"对比之前还是略有卡顿"里
--       占比最大的那一项（`tests/grid_cost.lua` 的 [E] 口径）。
--
--   为什么以前不敢缓存未命中：`main.lua` / `entry_client_script.lua` 里写着
--     「`find` 未命中会**永久缓存 false** ⇒ 万一此刻树还没就绪，就把后面那条路也一起弄死」
--     —— 那是**真的**（旧实现把 false 写进 `self.controls`）。所以这里三条规矩缺一不可：
--       ① **命中缓存优先**：任何 `self.controls[name] = ctrl`（新建/改名/找回）都天然
--          让这个名字的负缓存失效 —— 不需要调用方记得去清。
--       ② **树还没"见过活控件"就一律不记负缓存**：`self._lookup_hits == 0` 时
--          （OnInit/OnStart 阶段树是空的，这是真机日志里写明的正常现象）
--          未命中**照旧每帧重搜** —— 启动期那条"等控件就绪再开局"的重试一个字都不变。
--          代价为零：树是空的时候，搜空本来就几乎不花时间。
--       ③ **未命中会自己过期一次**：第一次记下 `clock + ttl`，过了这一刻若还没出现，
--          再真搜一次；还是不在 ⇒ 记成 `false`（本代内不再重搜，直到事件作废）。
--          ⇒ 即使"树是分两批加载的"这种没被我们观测到的情况发生了，
--            最多晚 `ttl`（默认 1 秒）也能自己恢复，**不可能永久卡死**。
--   ③ 的账：每个缺失名字每代最多多走 **1** 遍树（≈470 个节点），
--          对比现在**每帧** 5217 个节点 —— 三个数量级的差别。
--
--   什么时候整代作废：`Adapter:invalidate_lookups(why)` —— 切屏 / 换关 / 新建或销毁控件 /
--     网格视窗 RefreshItems（引擎那时才实例化列表项）。和第 2 项改造
--     （`enforce_hidden_subtrees`）共用**同一批事件**，一处定义、处处触发。
-- ════════════════════════════════════════════════════════════════════════

-- 把"这一代的名字缓存"整代扔掉（含负缓存），并让兜底隐藏重跑一次。
-- 触发时机全都是**控件树真的变了**的事件，不是每帧。
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._subtree_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end

-- 只扔一个名字的两半缓存（改名/换绑这种"一个控件换了身份"的场合）
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
end

function Adapter:find(name)
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  -- ★ 负缓存命中：这一代里已经确认"不在树上" ⇒ 直接返回 nil，**不再走深树**。
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      -- `false` = 已经重搜过一次还是不在（本代内不再重搜）；
      -- 数字 = 过期时刻，没到点就认账。
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    -- 主路径：按「控件名称」深度优先搜索
    for i = 1, #roots do
      local hit = find_in(roots[i], name, 0)
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    end
    -- 兜底：cfg.path_map[name] = "1/2/3"
    local pm = self.cfg.path_map
    local path = pm and pm[name]
    if path then
      local hit = control_by_path(roots, path)
      if hit then
        self.controls[name] = hit
        self:_note_lookup_hit(name)
        return hit
      end
    end
  end
  -- ★ 搜空 ⇒ 记进负缓存（规矩 ②：树还没"见过活控件"时一律不记 —— 启动期的重试不能被打断）
  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil then
      self._misses[name] = self.clock + ttl     -- 第一次：给一次"过一会儿再看"的机会
    elseif old ~= false and self.clock >= old then
      self._misses[name] = false                -- 已经重搜过还是不在 ⇒ 本代内不再重搜
    end
  else
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
    -- ★★ 2026-10-06 **启动期也记负缓存，但只记【短 TTL】且【绝不记 `false`】** ✗✓
    --
    --   ★ 起因（★ 用户实测 ✓）：★「开局前后**稳定 5 秒内**卡一下」✗ ✗
    --     ★★ 而★ 五套诊断**已经关掉了** ✗ ★ 卡顿**还在** ✓ ⇒ ★ 说明是**启动期特有的东西** ✓
    --   ★★★ 就是这条 `if` ✗：★ **启动期整段跳过 ⇒ 每次都深搜全树** ✗✗
    --     ★ 而★ 「这些控件还没建（共 **93 个**）」✓ ⇒ ★ **93 个名字 × 每个属性 ×
    --       每次重试（★ `PROP_RETRY` = 3 ✓）× 每次全树深搜（★ 470+ 控件 ✓）** ✓✓
    --       ★★★★ **⇒ 开局那几秒几百上千次全树遍历** ✓✓ —— ★ **与"5 秒内"完全吻合** ✓
    --     ★★ 这也解释了 ✓：★ 我把 `lookup_miss_ttl` 从 1 秒改成 30 秒**没有效果** ✗
    --       —— ★ **因为启动期压根不走那条路** ✓✓（★ 我那次改错了地方 ✓）
    --
    --   ★ 为什么【不能】照抄上面那条（★ 记 `false`）✗：
    --     ★ `false` = ★ **本代内不再重搜** ✗ ⇒ ★ 启动期正是"控件陆续进树"的时候 ✓
    --       ★★ 一旦记 `false` ⇒ ★ **那个控件本代就永远找不到了** ✗✗（★ 真·永久卡死 ✓）
    --   ★ 所以这里 ✓：★ **只记数字（★ 会过期 ✓）** ✗ ★ **绝不写 `false`** ✓
    --     ★★ TTL 用 **0.25 秒** ✓（★ 很短 ✓）⇒ ★ 晚进树的控件最多等 0.25 秒 ✓
    --       ★★★ 而★ **同一小段时间里的几百次重复深搜全部省掉** ✓✓
    --   ⚠️ 与 `find` 上面那条负缓存命中检查**天然兼容** ✓（★ 它只认"没过期"✓）
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
    if self._misses == nil then self._misses = {} end
    local boot_ttl = (self.cfg and self.cfg.lookup_boot_miss_ttl) or 0.25
    if self._misses[name] == nil then
      self._misses[name] = self.clock + boot_ttl
    end
  end
  return nil
end

-- 搜到东西之后的两件小事（都很便宜，别省）：
--   ① 记下"树里已经有控件了" ⇒ 从这一刻起未命中才允许进负缓存（见 find 的规矩 ②）。
--   ② **安全网**：如果这个名字在"应当被隐藏"的名单里 ⇒ 它刚刚才进树
--      ⇒ 兜底隐藏必须重跑一次（原来靠每帧扫一遍才发现，现在靠这一下）。
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty = true
  end
end

-- 子控件（cell.1.1 下的 face / note / x / door.up ...）
--
-- ★ 2026-09-25 修正：**只缓存命中，绝不缓存未命中**。
--   旧实现在查不到时写 self.subs[key] = false，于是"UI 就绪前查过一次"就会
--   让这个子控件**永远取不到** —— 直接导致 image / notes / x_mark 这些表现层
--   静默失效（我们为此排查了一整天）。现在未命中只返回 nil，下次还会重试。
function Adapter:sub(parent_id, child_name)
  -- ★ 2026-09-26 扩展：支持「子控件装在一个中间容器里」的配法。
  --
  -- 为什么需要：官方《预设按钮的功能》写着
  --   「预设按钮可以**引用子层级中的客户端控件，作为不同状态节点的外显样式**」，
  --   也就是**预设按钮自己的图不显示，显示的是状态节点引用的那些子控件**（真机也印证过：
  --   "只改按钮自己的图片/尺寸，画面上完全看不出来"）。
  --   而脚本**既读不到也改不了状态节点的引用关系** ——
  --   `ClientUIPresetButtonControl` 在官方 API 里只有 3 个字段
  --   （`interactable` / `clickAudioId` / `raycastTarget`），**没有任何 *ChildId**。
  --
  --   所以最省事的配法是：**「默认」状态只引用一个容器**（例如 `content`），
  --   所有可见元素（face/note/x/wall.*/door.*/obj）都装在那个容器里 ——
  --   引用一次就够，**不用赌"一个状态节点能不能引用多个控件"**。
  --
  --   代价是脚本要能按 `cell.content.face` 找到东西，所以这里三级尝试：
  --     ① 直接子控件（扁平配法，零成本）
  --     ② cfg.cells.sub_roots（默认 content/root/body）下面的同名子控件
  --     ③ 官方 `FindChild(path)`（文档：「按路径查找子控件」）
  --   两种布局都能用，**不用改配置**。
  local key = parent_id .. "." .. child_name
  local cached = self.subs[key]
  if cached ~= nil and cached ~= false then return cached end
  local parent = self:find(parent_id)
  if parent == nil then return nil end

  local hit = nil
  if parent.GetChild ~= nil then
    pcall(function() hit = parent:GetChild(child_name) end)
  end

  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }

  if hit == nil then
    for i = 1, #roots do
      local mid = nil
      if parent.GetChild ~= nil then
        pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
      end
      if mid ~= nil and mid.GetChild ~= nil then
        pcall(function() hit = mid:GetChild(child_name) end)
        if hit ~= nil then break end
      end
    end
  end

  if hit == nil and parent.FindChild ~= nil then
    for i = 1, #roots do
      for _, sep in ipairs({ "/", "." }) do
        local p = tostring(roots[i]) .. sep .. tostring(child_name)
        pcall(function() hit = parent:FindChild(p) end)
        if hit ~= nil then break end
      end
      if hit ~= nil then break end
    end
  end

  if hit ~= nil then self.subs[key] = hit end
  return hit
end

----------------------------------------------------------------------------
-- 控件生命周期
----------------------------------------------------------------------------

function Adapter:create_control(node)
  -- ★★★★★ 2026-10-05 **这里登记的是「这个引擎控件是谁建的」，不是「事件表」。**
  --
  --   为什么仍然按 `node.id`：一个 id 只对应**一个**引擎控件（`_created[id]` 保证
  --   `create_control` 只跑一次），而后面 `rect` 分支要用 `handlers[pid]` 反查
  --   **父控件**的 `rect` —— `pid` 是**控件 id**，那里只能按 id 查。
  --   ⚠️ 事件**不在这里**：它已经搬到 `self.events[规划节点键]`（见 `set_property` 的
  --      `key == "event"` 分支）。旧写法把"节点登记"和"事件表"挤在同一张表上，
  --      于是第二个同 id 节点一写就把第一个的事件吃掉了 ✗
  --      （这就是 `handlers[node.id] = node` 那一行曾经的病根；登记本身没错，兼任才有错）。
  self.handlers[node.id] = node
  local ctrl = self:find(node.id)

  -- ★★★★★ 2026-10-02 **重建之后：所有界面控件都由脚本创建**。
  --
  --   背景：用户把编辑器里的 `select`/`board`/`left`/`right`/`topbar`/`toolbar`/
  --   `modal`/`intro`/`assets` **全部删掉**（只留 `home` + `stage` + 三个模板引用），
  --   于是 `ui_controller` 里规划的那些控件**全都不存在了**（真机日志：
  --   "这些控件还没建（共 108 个，按类分组）"）。
  --
  --   ⇒ 这里加一条**按 kind 自动选模板**的规则，把"显式 prefab_of"变成可选：
  --       · 容器类 kind  → 容器模板 `cfg.stage.prefab`（1073742330）
  --       · 其它 kind    → 通用控件模板 `cfg.cells.prefab`（1073741876，带 face/text 子控件）
  --     父级仍按 `cfg.parent_of[id]`（没有就用 `stage`）。
  --
  --   ⚠️ 与 `ensure_cells` / `ensure_widgets` 同一套路：改名 + 读回核对 + 记录 + 允许销毁。
  local AUTO_CONTAINER_KINDS = {
    container = true, panel = true, layer = true, list = true, box = true,
  }
  local function auto_prefab(ad, nd)
    if AUTO_CONTAINER_KINDS[nd.kind] then
      return ad.cfg.stage and ad.cfg.stage.prefab
    end
    -- ★ 2026-10-03 **图标用专用模板**（用户提供的干净客户端模板 `cfg.prefab_icon`）。
    --   原来七个 hex.* 走的是 `cells.prefab`（格子模板），那会**连带一整套格子子控件**
    --   （content / wall.* / door.* / note / x）⇒ 真机表现：画面上多出 7 个"迷你格子"
    --   把棋盘搅乱，而且 SetImage 打不到图片节点（只能落到 content 容器上）。
    if nd.icon_template == true and ad.cfg.prefab_icon ~= nil then
      return ad.cfg.prefab_icon
    end
    return ad.cfg.cells and ad.cfg.cells.prefab
  end
  -- ★★★★★ 2026-10-03 **`auto_create` 的粒度问题**：
  --   原来是 `if ctrl == nil and self.cfg.auto_create ~= false and ...`，
  --   而 `entry_client_script.lua` 里 `auto_create = false` ⇒ **整个分支被跳过**
  --   ⇒ 我新加的七个 `hex.*` 图标（以及一直存在的 `obj.*`）**根本建不出来**
  --   —— 真机日志里它们出现在"这些控件还没建"清单，就是这条造成的。
  --
  --   但**不能**简单把 `auto_create` 改成 true：那会一次性去建规划里缺的 96 个控件
  --   （`clue.*` `ruler.*` `room.*` `obj.*` …），副作用不可控。
  --
  --   ⇒ 加一层**按 id 的白名单** `cfg.auto_create_only`：
  --     只有名单里的节点才走自动创建，其它一律照旧。这一轮名单 = 七个 `hex.*`。
  local allow_auto = (self.cfg.auto_create == true)
    or (self.cfg.auto_create_only ~= nil and self.cfg.auto_create_only[node.id] == true)
  if ctrl == nil and allow_auto and game and game.InstantiateClientUIControl then
    local prefab = (self.cfg.prefab_of and self.cfg.prefab_of[node.id]) or nil
    if prefab == nil then prefab = auto_prefab(self, node) end
    if prefab ~= nil then
      local pname = (self.cfg.parent_of and self.cfg.parent_of[node.id]) or "stage"
      local parent = self:find(pname)
      if parent == nil and pname ~= "stage" then parent = self:find("stage") end
      if parent == nil then parent = self:find("root") end
      if parent then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = node.id end)
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= node.id then
            self:warn_once("auto:name:" .. tostring(node.id),
              "自动创建的控件改名没生效：想要 `" .. tostring(node.id) .. "`，读回来 `" .. tostring(got) .. "`。")
          end
          ctrl = obj
          self.controls[node.id] = ctrl
          self.instantiated = self.instantiated or {}
          -- ★★★★★ 2026-10-05 **新控件进树 = 控件名缓存作废 + 兜底隐藏重跑一次。**
          --   两件事必须同时做（见 `Adapter:invalidate_lookups` 与 `find` 的两段注释）：
          --     · 名字缓存：这一代里"没搜到"的判定不再成立（树多了一个节点）；
          --     · 兜底隐藏：新控件挂在**被隐藏的容器**下面时，它自己是 visible=true 的
          --       （模板带的），必须靠 enforce_hidden_subtrees 压下去 ——
          --       原来靠每帧扫一遍才发现，现在靠这个事件。
          self:invalidate_lookups("create:" .. tostring(node.id))
          -- ★★★★★ 2026-10-05 **新控件 = 重新武装射线开关那一趟**（每帧成本第 (3) 条）。
          --
          --   为什么必须补这一条：`enable_raycast` 收敛/放弃之后**不再整树重扫**了，
          --   而"新控件"完全可能是**按钮**（有 `raycastTarget` 字段）—— 漏掉它
          --   ⇒ 新按钮**点不动**（这个项目里"点不动"是反复发作的头号病）。
          --   ⚠️ "重新武装"**不等于"立刻扫"**：扫描本身仍被 `main.lua` 的
          --      "每 20 帧最多一趟"限着（见 `Adapter:enable_raycast` 那段注释）。
          --   ⚠️ 而且**只在这里**重新武装，**不挂进 `invalidate_lookups`** ——
          --      那个函数还被"网格滚动重进回调"调用（`tests/grid_cost.lua` 专门有一段
          --      `reenter()` 模拟"引擎每帧重进"）⇒ 挂那儿等于每帧重扫，白跑比改之前还多。
          --   ⚠️ 建控件的次数是**有界**的（`_created` 记过就不再建）⇒ 不会退化成每帧负载。
          self:rearm_raycast("create:" .. tostring(node.id))

          -- ★★★★★ 2026-10-03 **把规划里的 `image_id` 真正设到控件上**。
          --
          --   为什么必须在这里做：在这之前，整个适配器**没有任何一处消费 `node.image_id`**
          --   （我 grep 过 `.image_id`，结果为空）。而 `build_layout` 里一直有节点带着
          --   `image_id`（`obj.shelf` 那批 OBJECT_PALETTE，以及本轮新加的七个 `hex.*` 图标）
          --   ⇒ **控件建出来了、却是没有图的空白** ⇒ 真机表现就是**"控件不可见"**。
          --   这也正是 `obj.*` 自始至终没出现过的原因。
          --
          --   做法照抄已经跑通的格子那条路（`_cells_stamp`）：
          --   先看控件自己有没有 SetImage，没有就往下找第一个带 SetImage 的子控件
          --   （客户端控件模板通常把图片放在 `img` / `icon` / `face` 这类子节点上）。
          if node.image_id ~= nil then
            -- ★ 2026-10-03 **递归找**：真机日志证明"只找直接子控件"是不够的 ——
            --   `ClientUIPresetButtonControl`（格子模板建出来的那个）的直接子控件只有一个
            --   `content`，而图片 `face` 在 `content` 的**里面**（日志原文：
            --   `格子子控件实况（cell.1.1）：content(vis=true,124x124,img=nil)`）。
            --   所以这里往下递归最多 4 层：先按常见名字（face/img/icon/bg/image/content）钻，
            --   再兜底遍历全部子控件。
            local function has_setimage(c)
              local has = false
              pcall(function() has = (c.SetImage ~= nil) end)
              return has
            end
            local found_name = nil
            local function find_target(c, depth)
              if c == nil or depth > 4 then return nil end
              -- ★★ 2026-10-03 **顺序很关键**：先"按名字往下钻"，**钻完再考虑自己**。
              --
              --   上一轮我把"自己有没有 SetImage"放在最前面，结果首个命中就是 `content`
              --   （它是中间容器，也有 SetImage）⇒ 把图设到了容器上，并把 7 个用格子模板
              --   建出来的图标控件变成了"迷你格子"（自带 wall.* / door.* / face），
              --   真机表现就是**棋盘跟着一起变样/不见**。
              --
              --   而格子自己的做法是给 **`content/face`** 设图（日志：
              --   `子控件 face 存在（visible=true）imageId=106053`）⇒ **face 才是图片控件**。
              for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
                local kid = nil
                pcall(function() kid = c:GetChild(cn) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then found_name = cn return r end
                end
              end
              if has_setimage(c) then return c end
              local n = 0
              pcall(function() n = c:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = c:GetChild(i) end)
                if kid ~= nil then
                  local r = find_target(kid, depth + 1)
                  if r ~= nil then return r end
                end
              end
              return nil
            end
            local target = find_target(ctrl, 0)

            if target ~= nil then
              local src = nil
              pcall(function() src = target.imageSource end)
              local ok2 = pcall(function() target:SetImage(src, node.image_id) end)
              if not ok2 then pcall(function() target:SetImage(node.image_id) end) end
              if node.imageColor ~= nil then
                pcall(function() target.imageColor = node.imageColor end)
              end
              if node.imageType ~= nil then
                pcall(function() target.imageType = node.imageType end)
              end
              pcall(function() target:SetVisible(true) end)
              local readback = "?"
              pcall(function() readback = tostring(target.imageId) end)
              if print then
                print("[murdoku] 图标设图 " .. tostring(node.id)
                  .. "  imageId=" .. tostring(node.image_id)
                  .. " → 回读 " .. readback
                  .. "  经 " .. tostring(found_name or "子控件")
                  .. "  调用成功=" .. tostring(ok2))
              end
            else
              -- 一个都没找到：把子控件清单打出来，方便下一次直接看出结构
              local desc = {}
              local n = 0
              pcall(function() n = ctrl:GetChildCount() end)
              for i = 0, n - 1 do
                local kid = nil
                pcall(function() kid = ctrl:GetChild(i) end)
                if kid ~= nil then
                  local nm, cnt = "?", 0
                  pcall(function() nm = tostring(kid.name) end)
                  pcall(function() cnt = kid:GetChildCount() end)
                  desc[#desc + 1] = nm .. "(" .. cnt .. ")"
                end
              end
              self:warn_once("icon:target:" .. tostring(node.id),
                "控件 `" .. tostring(node.id) .. "` 建好了，但递归 4 层也没找到带 SetImage 的控件。"
                .. "它的子控件：" .. (table.concat(desc, " ") ~= "" and table.concat(desc, " ") or "（一个都没有）"))
            end
          end
          -- ★★★★★ 2026-10-04 **再走一遍 `_cells_paint`** —— 这条才是**真能渲染出来**的那条路。
          --
          --   上面那段"递归找带 SetImage 的子控件"只做了两件事：设图 + SetVisible(true)，
          --   **没设尺寸**。而格子模板建出来的 `face` **默认尺寸是 0** ⇒ 图设上了、
          --   `visible=true`，**画面上什么都没有** —— 真机日志"图标设图 … 调用成功=true"
          --   却看不见，就是这个。
          --   对照证据：v044（纯图片模板）下同样这段代码是**看得见**的，因为纯图片模板的
          --   图片子节点自带尺寸；v045 换成格子模板后就消失了。
          --   `_cells_paint` 是 25 个格子正在用的那条路（`格子底图已点亮：25 个 face`），
          --   它多做两件事：`face:SetSizeDelta(size)` + `face:SetAnchoredPosition(0,0)`。
          --   第 4 个参数传该图标自己的素材；`size` 传 nil ⇒ 它按控件实际尺寸算。
          pcall(function() self:_cells_paint(ctrl, nil, node.id, node.image_id) end)

          self.instantiated[node.id] = true
          self._auto_made = (self._auto_made or 0) + 1
        else
          self:warn_once("auto:fail:" .. tostring(node.id),
            "自动创建 `" .. tostring(node.id) .. "` 失败（模板 " .. tostring(prefab) .. "）"
            .. "err=" .. tostring(obj))
        end
      end
    end
  end

  if ctrl == nil then
    self:_note_missing(node.id)
    return nil
  end

  -- ★★★★ 2026-10-01 **真机"卡死"修复：全屏容器必须关掉射线。**
  --
  --   症状（用户实测）：点「选关」能进去，但**退不出来、进不了关卡，
  --   连奇域本身的退出按钮都点不动** —— 整个界面像卡死。
  --
  --   根因：我为了修"界面空白"把 `home` / `select` 两个容器从 150x150
  --   改成了**铺满整屏 1600x900**（inherit_pos_runtime 那一轮）。
  --   容器一旦铺满 + 又吃射线（`raycastTarget` 默认就是 true），
  --   它就**把整个屏幕盖住** —— 包括**游戏自己的 UI**（退出按钮）。
  --   => "退出按钮点不了"正是这个，不是脚本自己的按钮坏了。
  --      （我第一反应怀疑 `seal_containers` —— 翻了一眼实现，
  --        它只把 `disableKeyEventPassthrough` 设 true，点击那条早就设成 false 了，
  --        所以不是它。**先看代码再下结论**，这次差点又误判。）
  --
  --   => 容器**本来就不需要被点到**（要点的永远是里面的按钮），
  --      所以给这两个全屏容器显式关掉射线。
  if node.id == "home" or node.id == "select" then
    -- 真机上才问清楚的事实：日志打出
    --   容器 home 关射线：原=nil  字段写=没有这个字段  passthru字段存在
    -- => 这个引擎**根本没有 raycastTarget 字段**，我前两版都在改一个不存在的属性。
    -- 真正存在的是 disableCursorEventPassthrough（项目里 open_click_passthrough
    -- 就是靠它让格子的点击到达按钮）。这里把相关字段全列一遍、并回读，一次问清。
    local has = {}
    for _, k in ipairs({ "raycastTarget", "disableCursorEventPassthrough",
                          "disableKeyEventPassthrough", "interactable",
                          "blockRaycast", "showCursor" }) do
      local v = nil
      pcall(function() v = ctrl[k] end)
      has[#has + 1] = k .. "=" .. tostring(v)
    end
    print("[murdoku] 容器 " .. node.id .. " 字段： " .. table.concat(has, "  "))
    if ctrl.disableCursorEventPassthrough ~= nil then
      local o1 = pcall(function() ctrl.disableCursorEventPassthrough = false end)
      local r1 = "?"
      pcall(function() r1 = tostring(ctrl.disableCursorEventPassthrough) end)
      print("[murdoku]   容器 " .. node.id .. " 写 disableCursorEventPassthrough=false 成功="
        .. tostring(o1) .. " 回读=" .. r1)
    end  end
  -- ★ 2026-09-26 修的严重 bug：bind_input 以前**定义了但从没被调用**，
  --   于是没有任何控件挂上光标监听 —— 整个界面点哪儿都没反应（模拟器和真机一样）。
  --   绑定放在这里（每个 id 只 create 一次），并让 bind_input 自己防重复。
  --
  -- 只给「按钮 / 光标检测区域」绑：文本框即使带了 event 也不支持光标事件，
  -- 硬绑只会刷一屏「不支持光标事件」。
  if node.event ~= nil and (node.kind == "button" or node.kind == "cursor") then
    self:bind_input(node.id, node)
  end
  return ctrl
end

----------------------------------------------------------------------------
-- 运行时光栅：用「控件模板索引」批量生成 cell.<r>.<c>
--
-- 为什么需要它：编辑器的「位置」是两套规则混用的（官方 API 文档 1317~1322 行）——
--   · 无父层级：以**画布左下角**为原点的绝对坐标
--   · 有父层级：与**父层级中心**的相对偏移
-- 手摆 25 格既枯燥、又很容易把两套规则搞混导致错位。
-- 这里只要求你在编辑器里把 **1 个** 格子做对，另存为模板后把「控件模板索引」
-- 填进 cfg.cells.prefab，剩下 24 个交给运行时生成 —— 以后换 6×6 / 7×7 关卡也不用重摆。
--
-- cfg.cells = {
--   prefab   = 1073741961,   -- 控件模板索引（编辑器里点客户端控件可以看到）
--   parent   = "board",      -- 生成到哪个控件下
--   size     = 124,          -- 格子边长
--   pitch    = 132,          -- 相邻格子的步距（边长 + 间距）
--   margin   = 14,           -- 左上角距父级的边距
--   parent_w = 680,          -- 父控件宽（用来算"相对父级中心"的偏移）
--   parent_h = 680,          -- 父控件高
-- }
----------------------------------------------------------------------------

function Adapter:cell_id(r, c) return string.format("cell.%d.%d", r, c) end

-- 算格子的几何。**优先用父控件的实际尺寸**，这样 5×5 / 6×6 / 7×7 自动适配 ——
-- 编辑器只要按**最大的 N** 把格子建够，小棋盘多出来的格子由界面层隐藏、
-- 大小与位置由这里在运行时摆正，不需要为每个尺寸重摆一次布局。
-- 拿不到实际尺寸时退回 cfg.cells 里的固定值（老行为，保持兼容）。
--
-- 返回 size, pitch, margin, pw, ph
function Adapter:cell_geometry(n)
  local g = self.cfg.cells or {}
  n = math.max(1, tonumber(n) or 5)

  local pw = g.parent_w or 733
  local ph = g.parent_h or 733
  local parent = self:find(g.parent or "board")
  if parent ~= nil and parent.GetSizeDelta ~= nil then
    local ok, w, h = pcall(function() return parent:GetSizeDelta() end)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      pw, ph = w, h
    end
  end

  local avail = math.min(pw, ph)
  -- ★★★★★ 2026-10-04 **`ruler` 是"边框"，两边都有** —— 原来只扣一边（`avail - ruler`）是错的。
  --
  --   判据是 `docs/布局图-关卡内-v3.png` 的逐像素测量（1600×900，已经是画布空间）：
  --     棋盘外框 584×584，**边框四边均匀 12px**
  --     内区 = 584 − 2×12 = **560**
  --     图上画的是 **6×6**：pitch = 560/6 = **93.33**（实测格心间距 93/94 交替）
  --                       格 = pitch − 4 = **89.33**（实测 89/90 交替）
  --     ⇒ 同一个公式换成本项目在用的 N=5：pitch = 560/5 = **112**、格 = **108** ✅
  --   ⇒ 所以"棋盘外框固定、格子按关卡 N 自适应"这条设计是成立的，
  --     错的只是**边框只扣了一边**，导致格子偏右下一格。
  local ruler = g.ruler or math.floor(avail * 0.06)     -- 边框厚度（左/右、上/下各一份）
  local area  = avail - 2 * ruler
  local pitch = math.floor(area / n)
  local gap   = g.gap or math.max(2, math.floor(pitch * 0.03))
  local size  = math.max(8, pitch - gap)
  -- 居中：格子区域在"扣掉两边边框之后"的区域里居中
  local margin = ruler + math.floor((area - (n * pitch - gap)) / 2)

  -- 显式配置优先（想钉死某个值时用；不写就自动算）
  if g.size   then size   = g.size   end
  if g.pitch  then pitch  = g.pitch  end
  if g.margin then margin = g.margin end
  return size, pitch, margin, pw, ph
end

-- 第 (r,c) 格的中心相对「父控件中心」的偏移（Y 向上，跟官方嵌套控件的 SetAnchoredPosition 一致）
-- n 不传就用 g.rows/g.cols，再不行按 max(r,c) 兜底
function Adapter:cell_offset(r, c, n)
  local g = self.cfg.cells
  if g == nil then return nil end
  n = n or g.rows or g.cols or math.max(r, c)
  local size, pitch, margin, pw, ph = self:cell_geometry(n)
  -- x：从父级左边量 margin，第 c 格再加 (c-1)*pitch，取中心后减去父级中心
  local x = margin + (c - 1) * pitch + size / 2 - pw / 2
  -- y：第 1 行在最上面，所以从父级上边往下走，最后减父级中心
  local y = ph - margin - (r - 1) * pitch - size + size / 2 - ph / 2
  return x, y
end

-- ★★★★★ 2026-10-04 **「这张图到底该设在哪个控件上」** —— 从 `ensure_widgets` 里那段
--   已经跑通的 `find_target` 原样抽出来，供别处复用（目前是 main.lua 的棋盘底板）。
--
--   为什么必须抽出来：真机日志（2026-10-04 14:18）证明
--       `棋盘底板：board.bg 建=true 设图=false imageId=0`
--   ——**运行时新建的客户端控件，在"根节点"上 `SetImage` 直接返回 false、`imageId` 一直是 0**。
--   而同一批模板建出来的七个图标走「子控件」那条路就成功了
--   （日志：`图标设图 hex.back imageId=100109 → 回读 100109  经 子控件  调用成功=true`）。
--   ⇒ 结论：**图片挂在子控件上，模板的根只是个容器** —— 设图必须往下钻，不能设在根上。
--
--   ★ 顺序很关键（这条是上一轮踩出来的，不能改）：
--     **先按名字往下钻，钻完再考虑自己。**
--     反过来会让 `content` 这种"中间容器"抢先命中，把图设到容器上，
--     真机表现是控件变成"迷你格子"或整体不见。
--
--   ★ 2026-10-04 增加的判据：优先选 **`imageSource` 非 nil** 的那个控件。
--     原因：真机上 `SetImage(nil, id)` 会失败，而 `target:SetImage(src, id)`（src 取自
--     `target.imageSource`）才是验证过能成功的形式 ⇒ 没有 imageSource 的控件设不进图。
--     所以"有 SetImage"只是及格线，"有 SetImage 且 imageSource 非 nil"才算合格。
--
--   返回：target（找不到就是 nil）、命中的子控件名（自己命中时为 nil，调用方显示"根"）
function Adapter:image_target(ctrl)
  if ctrl == nil then return nil end
  local found_name = nil

  local function has_setimage(c)
    local has = false
    pcall(function() has = (c.SetImage ~= nil) end)
    return has
  end
  -- 「合格」= 有 SetImage 且 imageSource 读得到（否则 SetImage 会失败）
  local function usable(c)
    if c == nil or not has_setimage(c) then return false end
    local src = nil
    pcall(function() src = c.imageSource end)
    return src ~= nil
  end

  local function dive(c, depth)
    if c == nil or depth > 4 then return nil end
    -- ① 按名字往下钻（face/img/icon/... 是官方模板给图片子节点起的常见名字）
    for _, cn in ipairs({ "face", "img", "icon", "image", "bg", "content" }) do
      local kid = nil
      pcall(function() kid = c:GetChild(cn) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then found_name = cn return r end
      end
    end
    -- ② 自己：先看"合格"的，再看"只是有 SetImage"的（保持与旧行为一致，只是更好）
    if usable(c) then return c end
    if has_setimage(c) then return c end
    -- ③ 兜底：遍历全部子控件（模板里的图片节点不一定用上面那六个名字）
    local n = 0
    pcall(function() n = c:GetChildCount() end)
    for i = 0, n - 1 do
      local kid = nil
      pcall(function() kid = c:GetChild(i) end)
      if kid ~= nil then
        local r = dive(kid, depth + 1)
        if r ~= nil then return r end
      end
    end
    return nil
  end

  local t = dive(ctrl, 0)
  return t, found_name
end

-- 把图设到 `image_target` 找到的那个控件上，并把**回读**打出来。
--
--   为什么回读必须打：这个工程反复吃亏在"调了 API 就当成功了"。
--   真机上 `SetImage` 有的重载**静默失败**，只有 `imageId` 回读才能证明图真的设进去了。
--
--   image_type：一般给 "Stretch"（底板类素材才支持拉伸）。
--   image_color：32 位整数 ARGB（`Color()` 全局函数在真机上不存在，所以只能直接写整数）。
--                传 nil 就不动颜色。**乘算着色**：素材是白模时，染成什么色就是什么色。
--   label：日志前缀（传 nil 就不打日志）。
--
--   返回：hit(布尔：回读等于要设的 id 才算真成功)、命中描述(字符串)、回读 imageId(字符串)、
--         tint_ok(布尔/nil：没要求染色时是 nil；要求了就看回读**是不是真变成了那个色**)
--
--   ★★ 为什么要回读颜色而不是"调了就算成功"（2026-10-04）：
--     用户点名要"把底板换成**纯色图形**"，而官方素材库里**所有形状/底板都是白模**
--     （`100001` 纯白方块、`106xxx` 单色底板全是白的）⇒ 想要纯色就**必须靠染色**。
--     而 `imageColor` 能不能用**整数**写进去，本项目**至今没有真机证据**
--     （文档里只有"离线冒烟"验过 `face.imageColor.r=10`，真机只验过"没有全局函数 `Color`"）。
--     ⇒ 所以这里把"染色到底成没成"变成一个**可判定的事实**，调用方据此决定要不要回退。
function Adapter:set_image_deep(ctrl, image_id, image_type, image_color, label)
  if ctrl == nil then return false, "没有控件", "?" end
  local target, found = self:image_target(ctrl)
  if target == nil then
    return false, "找不到可设图的子控件", "?"
  end
  -- ★ 先试 (src, id) 两参形式 —— 这条路在真机上验通过；失败再试单参形式。
  local okcall = false
  local src = nil
  pcall(function() src = target.imageSource end)
  okcall = pcall(function() target:SetImage(src, image_id) end)
  if not okcall then
    okcall = pcall(function() target:SetImage(image_id) end)
  end
  if image_type  ~= nil then pcall(function() target.imageType  = image_type  end) end
  if image_color ~= nil then pcall(function() target.imageColor = image_color end) end

  local rid, rcol = "?", "?"
  pcall(function() rid  = tostring(target.imageId)   end)
  -- ★ 颜色回读**分两种形态**处理：真机 `fontColor` 读出来是整数，但 `imageColor`
  --   官方类型是 `ColorValue` ⇒ 也可能是"有 r/g/b/a 字段的对象"。两种都认。
  local tint_ok = nil
  if image_color ~= nil then
    local want = tonumber(image_color) or 0
    local wr = math.floor(want / 65536) % 256
    local wg = math.floor(want / 256) % 256
    local wb = want % 256
    local wa = math.floor(want / 16777216) % 256
    tint_ok = false
    local v = nil
    pcall(function() v = target.imageColor end)
    if type(v) == "number" then
      -- 形态①：整数（按 ARGB 解）
      local gr = math.floor(v / 65536) % 256
      local gg = math.floor(v / 256) % 256
      local gb = v % 256
      tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
      rcol = tostring(v)
    elseif v ~= nil then
      -- 形态②：ColorValue 对象（读 r/g/b/a 字段）
      local gr, gg, gb, ga = nil, nil, nil, nil
      pcall(function() gr = v.r end)
      pcall(function() gg = v.g end)
      pcall(function() gb = v.b end)
      pcall(function() ga = v.a end)
      rcol = "(" .. tostring(gr) .. "," .. tostring(gg) .. "," .. tostring(gb)
        .. "," .. tostring(ga) .. ")"
      if type(gr) == "number" and type(gg) == "number" and type(gb) == "number" then
        tint_ok = (math.abs(gr - wr) <= 2 and math.abs(gg - wg) <= 2 and math.abs(gb - wb) <= 2)
        if type(ga) == "number" and math.abs(ga - wa) > 2 then tint_ok = false end
      end
    else
      rcol = "nil（读不到 imageColor）"
    end
  else
    pcall(function() rcol = tostring(target.imageColor) end)
  end
  local hit = (rid == tostring(image_id))
  if print and label ~= nil then
    print("[murdoku] 设图 " .. tostring(label)
      .. "  imageId=" .. tostring(image_id)
      .. " → 回读 " .. rid
      .. "  imageColor 回读 " .. rcol
      .. "  染色成功=" .. tostring(tint_ok)
      .. "  经 " .. tostring(found or "根")
      .. "  调用成功=" .. tostring(okcall)
      .. "  真的设上了=" .. tostring(hit))
  end
  return hit, (found or "根"), rid, tint_ok
end

-- 「不用日志也能看出结果」的诊断信号。
-- 找一个"改了外观就会变"的控件，把它的边长设成 v（正方形），肉眼即可读数。
--
-- ★ 2026-09-25 血泪教训：**别改预设按钮本身**！
--   预设按钮的外观来自它「状态节点」引用的**子控件**，改按钮的 sizeDelta 在画面上
--   完全看不出来（我们为此白测了一整天）。一定要改**子控件**，比如 cell.1.1 的 `face`。
-- ★ 另一个坑：`Adapter:sub()` 未命中会**永久缓存 false**，UI 就绪前查过一次就再也拿不到。
--   所以这里**绕开 sub()**，直接用 GetChild 现查。
function Adapter:_cells_signal(v)
  local targets = {}
  local c = self:find("cell.1.1")
  if c ~= nil then
    if c.GetChild ~= nil then
      local ok, f = pcall(function() return c:GetChild("face") end)
      if ok and f ~= nil then targets[#targets + 1] = f end      -- ★ 首选：子控件（看得见）
    end
    targets[#targets + 1] = c                                     -- 兜底：按钮本身（多半看不见）
  end
  local t = self:find("tray.A")
  if t ~= nil and t.GetChild ~= nil then
    local ok, f = pcall(function() return t:GetChild("face") end)
    if ok and f ~= nil then targets[#targets + 1] = f end
  end
  if game ~= nil and game.GetClientUIRoots ~= nil then
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" and roots[1] ~= nil then
      targets[#targets + 1] = roots[1]
    end
  end
  for i = 1, #targets do
    local x = targets[i]
    if x.SetSizeDelta ~= nil then
      local ok = pcall(function() x:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end

-- 逐格自检：把 `board` 的**真实子控件**摊出来。
--
-- 为什么需要它：真机 2026-09-26 17:56 的日志出现了**对不上账**的情况 ——
--   缺 25 格 → 按理是"试造 1 + 循环 24 = 25 个新建"，可日志写的是**新建 23 个**，
--   而「25 / 25 存在」又说齐了。差的那 1 格既不是脚本建的、也不在预期路径上。
--   同时用户报告 **第一个格子的缺口仍在**。
--
-- 光靠"存在/不存在"这种二值信息已经查不下去了，所以这里直接摊开**实测数据**：
--   · `board` 在树上**实际**有哪些子控件（不走 find 的名字缓存，直接走树）；
--   · 每个格子的名字 / 屏幕位置 / 尺寸 / visible / active / 是不是脚本建的；
--   · 被"挪出画布"的那些引用控件现在在哪（用来确认它们真的挪走了）。
--
-- 读不到就打印 `?`，不猜。
function Adapter:diagnose_grid(rows, cols)
  if print == nil then return end
  local g = self.cfg.cells or {}
  local print_ = print

  print_("[murdoku] ===== 逐格自检（实测，不猜）=====")

  -- ① board 在树上到底有哪些子控件
  local parent = self:find(g.parent or "board")
  if parent == nil then
    print_("[murdoku] 找不到父控件 " .. tostring(g.parent or "board") .. " —— 后面的都查不了")
    print_("[murdoku] ===== 逐格自检结束 =====")
    return
  end
  local kids = nil
  pcall(function() kids = parent:GetChildren() end)
  local on_tree = {}
  local kid_names = {}
  if type(kids) == "table" then
    for i = 1, #kids do
      local nm = "?"
      pcall(function() nm = tostring(kids[i].name) end)
      on_tree[nm] = kids[i]
      kid_names[#kid_names + 1] = nm
    end
  end
  print_("[murdoku] " .. tostring(g.parent or "board") .. " 树上实际有 "
    .. #kid_names .. " 个子控件：" .. table.concat(kid_names, " "))

  -- ② 逐格：名字 / 位置 / 尺寸 / 可见 / 激活 / 来源
  local missing_on_tree, missing_as_ctrl = {}, {}
  local n_new, n_edit = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = on_tree[id]
      if ctrl == nil then
        missing_on_tree[#missing_on_tree + 1] = id
      end
      local via_find = self:find(id)
      if via_find == nil then missing_as_ctrl[#missing_as_ctrl + 1] = id end
      if self.instantiated and self.instantiated[id] then n_new = n_new + 1
      elseif ctrl ~= nil then n_edit = n_edit + 1 end
    end
  end

  -- 只列"有问题的"和第一行 —— 25 行全铺太吵
  local function describe(id)
    local ctrl = on_tree[id]
    local pos, size, vis, act = "?", "?", "?", "?"
    if ctrl ~= nil then
      -- ★ 读位置：官方给**控件**的接口是 `GetAnchoredPosition()` → x, y
      --   （`GetUIPos()` 在官方文档里**只属于 `CursorEventData`**，不是控件方法 ——
      --    我照着模拟器的方法表写成 `ctrl:GetUIPos()`，真机上必然读不到，日志里就是 `位置=?`。
      --    这是"模拟器有、文档没有"的案例之一。）
      --   兜底再试 `anchoredPositionX/Y` 字段。
      pcall(function()
        local a, b = ctrl:GetAnchoredPosition()
        if type(a) == "table" then pos = string.format("(%.0f,%.0f)", a.x or 0, a.y or 0)
        elseif a ~= nil then pos = string.format("(%.0f,%.0f)", a, b or 0) end
      end)
      if pos == "?" then
        pcall(function()
          local ax, ay = ctrl.anchoredPositionX, ctrl.anchoredPositionY
          if ax ~= nil then pos = string.format("(%.0f,%.0f)", ax, ay or 0) end
        end)
      end
      pcall(function()
        local w, h = ctrl:GetSizeDelta()
        if type(w) == "table" then size = string.format("%.0fx%.0f", w.x or 0, w.y or 0)
        elseif w ~= nil then size = string.format("%.0fx%.0f", w, h or 0) end
      end)
      pcall(function() vis = tostring(ctrl.visible) end)
      pcall(function() act = tostring(ctrl.active) end)
    end
    local origin = (self.instantiated and self.instantiated[id]) and "脚本建的" or "编辑器摆的"
    return "  " .. id .. "  " .. origin
      .. "  位置=" .. pos .. "  尺寸=" .. size
      .. "  visible=" .. vis .. "  active=" .. act
      .. (on_tree[id] == nil and "   ← **不在 " .. tostring(g.parent or "board") .. " 下**" or "")
  end

  if #missing_on_tree > 0 then
    print_("[murdoku] ⚠️ 这些格子在 " .. tostring(g.parent or "board") .. " 下**根本找不到**：" .. table.concat(missing_on_tree, " "))
  end
  if #missing_as_ctrl > 0 then
    print_("[murdoku] ⚠️ 这些格子 `find` 也取不到：" .. table.concat(missing_as_ctrl, " "))
  end
  print_("[murdoku] 来源统计：脚本建的 " .. n_new .. " 个，编辑器摆的 " .. n_edit
    .. " 个（合计 " .. (n_new + n_edit) .. " / " .. (rows * cols) .. "）")
  print_("[murdoku] 第一行逐格：")
  for c = 1, cols do print_(describe(self:cell_id(1, c))) end
  if #missing_on_tree > 0 or #missing_as_ctrl > 0 then
    print_("[murdoku] 其余有问题的格子：")
    local listed = {}
    for _, id in ipairs(missing_on_tree) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
    for _, id in ipairs(missing_as_ctrl) do
      if not listed[id] then listed[id] = true; print_(describe(id)) end
    end
  end

  -- ③b ★ 子控件清单：把格子（含中间容器）里的东西**逐个摊出来**
  --
  -- 为什么需要：用户 2026-09-27 04:08 报告"只有部分东西可见，且只有两行"，
  --   而当时日志里**看不到格子里到底配了什么**（有几个子控件？叫什么？
  --   visible 是什么？图片类型是基础还是拉伸？）。
  --   特别是「**静态引用大多不支持拉伸**」这条 —— 只有把每个图片子控件的
  --   `imageType` / `imageId` 打出来，才能一眼看出谁被拉伸、谁只能按原样画。
  do
    local want = {
      -- ⚠️ 2026-09-27：`text` 原来**不在这个清单里**，于是真机日志的"子控件清单"
      --    里看不到它 —— 而格子文字恰恰靠它（预设按钮没有 text 属性，
      --    `set_property(id,"text")` 只能走 `sub(id,"text")` 这条回退路径）。
      --    清单漏项会让人误判"text 没配好"，所以补进来。
      "face", "text", "note", "x", "obj",
      "wall.up", "wall.down", "wall.left", "wall.right",
      "door.up", "door.down", "door.left", "door.right",
    }
    -- ★★★★★ 2026-10-05 **内部格也必须列一遍，不能只看 cell.1.1**。
    --
    --   为什么：`cell.1.1` 是**角格** —— 按 core 的 `view()`
    --     `walls.up = (r == 1)`、`walls.left = (c == 1)` **本来就为真**
    --   ⇒ 日志里"up/left 亮着"既可能是**脚本下发的**、也可能是**模板默认**、
    --     甚至是上一关留下的状态 —— **这个格子分辨不了**，而用户的症状恰恰是
    --     "第一次进关墙/门没画出来、第二次正常"（要判的就是"脚本设的"有没有生效）。
    --   内部格（`cell.2.2`）四个方向都有邻居 ⇒ 四面墙该不该亮**只可能来自脚本**
    --   ⇒ 只有把两个格子并排看（角格亮 / 内部格不亮 = 脚本那条 `walls` 没送达），
    --     结论才站得住。
    local function list_cell(probe, why)
      local have, miss = {}, {}
      for i = 1, #want do
        local s = self:sub(probe, want[i])
        if s ~= nil then have[#have + 1] = s else miss[#miss + 1] = want[i] end
      end
      print_("[murdoku] --- 格子里的子控件清单（" .. probe .. "，" .. why .. "）---")
      if #have == 0 then
        print_("[murdoku]   ⚠️ 一个都没找到。若你把它们装进了中间容器，容器名必须是 "
          .. "content / root / body 之一（配置项 cfg.cells.sub_roots）。")
      end
      for i = 1, #have do
        local s = have[i]
        local nm, vis, it, iid = "?", "?", "?", "?"
        pcall(function() nm = tostring(s.name) end)
        pcall(function() vis = tostring(s.visible) end)
        pcall(function() it = tostring(s.imageType) end)
        pcall(function() iid = tostring(s.imageId) end)
        print_("  " .. string.format("%-12s", nm)
          .. " visible=" .. string.format("%-5s", vis)
          .. " imageType=" .. string.format("%-26s", it)
          .. " imageId=" .. iid)
      end
      if #miss > 0 then
        print_("[murdoku]   没有配的：" .. table.concat(miss, " "))
      end
    end
    list_cell("cell.1.1", "角格：up/left 本来就该亮，分不清是谁设的")
    if rows >= 2 and cols >= 2 then
      list_cell("cell.2.2", "内部格：四邻都有 ⇒ 四面墙只可能来自脚本")
    else
      print_("[murdoku]   （本关只有 " .. rows .. "×" .. cols .. " 格，没有内部格可对照 —— "
        .. "角格分不清「脚本设的」和「模板默认」，这一条判不了。）")
    end
    print_("[murdoku]   （**静态引用大多不支持拉伸** —— 需要拉伸的地方请选「底板」类素材；"
      .. "imageType 显示 Stretch 才说明这个素材支持，Basic 就只能按原样铺。）")

    -- ★★★★★ 2026-10-05 **层序 / 锚点实测 —— 判「白色 face 把墙盖住了」这个假设**。
    --
    --   为什么要单独读这一组数：
    --     引擎的层序规则是「**兄弟索引大的画在上面**」（见 `enforce_layers` 那段注释），
    --     而脚本的层序是**倒序逐个 `SetAsFirstSibling()`** 排出来的 —— 也就是
    --     "最后一次 SetAsFirstSibling 的那个，索引最小 = 最下面"。
    --     这一串有没有真的生效，光看 `visible` 是看不出来的：
    --     墙 `visible=true` 也可能**被上面的 face 挡住**（用户看到的就是"墙没画出来"）。
    --   ⇒ 所以直接把 `face` 和 `wall.up` 的**实测兄弟索引**并排打出来：
    --        face 索引 **大于** wall.up ⇒ face 盖住墙（就是被遮挡，不是没设）。
    --     顺带把 `wall.up` 的锚点/位置/尺寸打出来 —— "墙被贴到画布外面去了"这一假设
    --     （`_apply_edges` 里那段按 `cell_geometry` 算的贴边代码）也一并可判。
    do
      local probe = (rows >= 2 and cols >= 2) and "cell.2.2" or "cell.1.1"
      local function idx_of(c)
        local v = "?"
        if c ~= nil then pcall(function() v = c:GetSiblingIndex() end) end
        return tostring(v)
      end
      local function f0(v) return (type(v) == "number") and string.format("%.0f", v) or "?" end
      local function geom_of(c)
        if c == nil then return "（取不到这个子控件）" end
        local ax, ay, bx, by, x, y, w, h = nil, nil, nil, nil, nil, nil, nil, nil
        pcall(function() ax, ay = c.anchorMinX, c.anchorMinY end)
        pcall(function() bx, by = c.anchorMaxX, c.anchorMaxY end)
        pcall(function() x, y = c.anchoredPositionX, c.anchoredPositionY end)
        pcall(function() w, h = c.sizeDeltaX, c.sizeDeltaY end)
        if w == nil then pcall(function() w, h = c:GetSizeDelta() end) end
        if x == nil then
          pcall(function()
            local a, b = c:GetAnchoredPosition()
            if type(a) == "table" then x, y = a.x, a.y else x, y = a, b end
          end)
        end
        return "anchorMin=(" .. f0(ax) .. "," .. f0(ay) .. ")"
          .. " anchorMax=(" .. f0(bx) .. "," .. f0(by) .. ")"
          .. " 位置=(" .. f0(x) .. "," .. f0(y) .. ")"
          .. " 尺寸=" .. f0(w) .. "x" .. f0(h)
      end
      local face = self:sub(probe, "face")
      local wu = self:sub(probe, "wall.up")
      print_("[murdoku] --- 层序/锚点实测（" .. probe .. "，判「白色 face 是否盖住墙」）---")
      print_("[murdoku]   face     兄弟索引=" .. idx_of(face) .. "  " .. geom_of(face))
      print_("[murdoku]   wall.up  兄弟索引=" .. idx_of(wu) .. "  " .. geom_of(wu))
      print_("[murdoku]   （判读：引擎是「**索引大的画在上面**」⇒ face 的索引 **大于** wall.up"
        .. " ⇒ 白色 face 把墙**盖住**了（不是没设上）；若 wall.up 取不到或位置/尺寸是 0，"
        .. "则是墙**根本没摆上去**。两种症状长得一样，只能靠这三行分开。）")
    end

    -- ★★ 对账：**本关需要哪些边** vs **模板里配了哪些子控件**
    --
    -- 用户 2026-09-27 04:26 的实际场景：关卡 wall_set 里有 `v:4:3` / `v:5:3`（竖墙），
    --   但模板只配了 `wall.up` → 那两面竖墙**画不出来**，而日志当时什么都没说。
    --   这类"数据要、素材没有"的缺口必须自己报出来，不该靠人看截图发现。
    if type(self.edges_needed) == "table" then
      local lack = {}
      for edge in pairs(self.edges_needed) do
        if self:sub("cell.1.1", edge) == nil then lack[#lack + 1] = edge end
      end
      table.sort(lack)
      if #lack > 0 then
        print_("[murdoku] ⚠️ **本关需要这些边，但模板里没有对应的子控件**（所以画不出来）："
          .. table.concat(lack, " "))
        print_("[murdoku]    补法：在模板的 `content` 里加同名图片子控件（"
          .. "`wall.up`/`wall.down`/`wall.left`/`wall.right`、`door.*`），"
          .. "**四个方向的墙要各自一个子控件**，不能只配一个。")
      else
        local need = {}
        for edge in pairs(self.edges_needed) do need[#need + 1] = edge end
        table.sort(need)
        print_("[murdoku] ✅ 本关需要的墙/门边，模板里都配了对应子控件：" .. table.concat(need, " "))
      end
    end
  end

  -- ③ 被挪走的引用控件现在在哪（确认"挪出画布"真的生效了）
  --
  -- ★ 2026-10-05 账本按**控件身份**去重（见 `_note_parked`），所以这段**每关只打一次**。
  --   真机 v062 的日志里它是 1 行 → 2 行 → 3 行（同一个 `tpl.cell`），
  --   很容易被读成"每次进关多出一个模板引用控件"—— 离线探针实测：控件始终只有 1 个。
  --   重复登记的次数在这里明说，免得下次又看错。
  local parked = self.cells_parked
  if type(parked) == "table" and #parked > 0 then
    print_("[murdoku] 已挪出画布的引用控件（确认位置真的到 200000 了吗）：")
    for i = 1, #parked do print_(describe(parked[i])) end
    local again = self.cells_parked_again or 0
    if again > 0 then
      print_("[murdoku]   （另有 " .. again .. " 次「同一个控件」的重复登记，已按控件身份去重 —— "
        .. "进 N 次关卡不会多出 N 行，也**不会**多出控件）")
    end
  end



  print_("[murdoku] ===== 逐格自检结束 =====")
end

-- 按钮专用信标：改**预设按钮自身**的尺寸。
-- 按钮自己不一定画东西，但它的子控件（居中锚点）会**跟着位移** —— 这个位移
-- 在 2026-09-25 实测是肉眼可辨的（最小探针就是靠它证明脚本在跑）。
function Adapter:_cells_beacon_button(v)
  local names = { "cell.1.1", "tray.A", "board" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetSizeDelta ~= nil then
      local ok = pcall(function() c:SetSizeDelta(v, v) end)
      if ok then return true end
    end
  end
  return false
end

-- 兼容旧名
function Adapter:_cells_report(code)
  local map = { [1] = 80, [3] = 100, [4] = 40, [5] = 60 }
  self:_cells_signal(map[code] or (120 + code * 10))
end

-- 读一个控件的「引用控件模板索引」。
--
-- ★ 2026-09-26 用户纠正：`prefabIndex` 是**基类**字段（控件模板索引，即「这个控件本身
--   是哪个模板的实例」），而**模板引用控件**引用的是另一个字段
--   `referencedPrefabIndex`（官方原文：「引用控件模板索引」，只读）。
--   我一开始只读 `prefabIndex`，把 `tpl.cell` 的 `prefabIndex=1073741885` 误当成
--   "另一张模板的索引" —— 那其实是**控件自身的索引**。
--   所以判断"模板引用控件引用了哪张模板"必须优先读这个字段。
function Adapter:_ref_index_of(ctrl)
  if ctrl == nil then return nil end
  local r = nil
  pcall(function() r = ctrl.referencedPrefabIndex end)
  if type(r) == "number" and r > 0 then return r end
  return nil
end

-- 把控件「停到屏幕外」。
--
-- 为什么需要它：模板引用控件在棋盘上会占着一个格子位置，而真机上它渲染不出格子副本，
-- 于是那一格看着是空的。`SetVisible(false)` 不一定够 ——
-- 官方文档写着 `active` **只读**，且「true 时控件可见」，也就是**可见性由 active 参与决定**，
-- 脚本改不了 active。所以最稳的办法是**把它挪出画布**：不管可见性语义怎么算，
-- 它都不可能在屏幕上盖住任何东西。

-- 把"这个控件已经挪出画布了"记进诊断账本。
--
-- ★★★★★ 2026-10-05 **账本必须按控件身份去重**（真机 v062 日志的"每次进关多一行 tpl.cell"）。
--
--   现象（用户日志）：一次游玩里进 3 次关卡，`diagnose_grid` 那块打印的是
--       1 行 → 2 行 → 3 行，三行**一模一样**（都是 `tpl.cell  编辑器摆的 … 不在 stage 下`），
--     看着像"每进一次关就多出一个模板引用控件（ClientUIReferenceControl）"。
--
--   实测（离线探针进 3 次关卡，照 196-网格视窗兜底.gil 的树形：`tpl.cell` 挂在 `root` 下）：
--       · `root` 下名叫 `tpl.cell` 的子控件**始终是 1 个**；
--       · 账本里所有条目指向的是**同一个控件对象**；
--       · 它每次都停在 (200000,200000) —— `_park_control` 是幂等的。
--   ⇒ 多出来的**不是控件，是这本流水账**：`ensure_cells` 每次进关都会把同一个控件再登记一遍
--     （`hide_names` 那段每关都跑，而 `tpl.cell` 的名字不改，所以每关都命中）。
--
--   ⇒ 所以这里按**控件身份**去重（拿不到控件对象时才退回按名字），重复登记只累加计数，
--     由 `diagnose_grid` 用一句话说明"重复了几次" —— 账本仍然回答得了
--     "现在有哪些东西被挪走了"，但不会再让同一样东西看起来有 N 份。
function Adapter:_note_parked(name, ctrl)
  if name == nil then return false end
  self.cells_parked = self.cells_parked or {}
  self.cells_parked_seen = self.cells_parked_seen or {}
  local key = ctrl or name      -- ★ 有控件就用控件身份当键（"是不是同一个控件"才是这里的问题）
  if self.cells_parked_seen[key] then
    self.cells_parked_again = (self.cells_parked_again or 0) + 1
    return false
  end
  self.cells_parked_seen[key] = true
  self.cells_parked[#self.cells_parked + 1] = name
  return true
end

function Adapter:_park_control(ctrl)
  if ctrl == nil then return false end
  local ok = false
  -- ① 挪到画布外（画布 1600×900，挪到 200000 足够远）
  if ctrl.SetAnchoredPosition ~= nil then
    if pcall(function() ctrl:SetAnchoredPosition(200000, 200000) end) then ok = true end
  end
  -- ② 顺手缩成 0 尺寸（双保险；有些布局下位移会被锚点约束拉回来）
  if ctrl.SetSizeDelta ~= nil then
    pcall(function() ctrl:SetSizeDelta(0, 0) end)
  end
  -- ③ 再试一次隐藏
  if ctrl.SetVisible ~= nil then
    pcall(function() ctrl:SetVisible(false) end)
  end
  return ok
end

-- 取模板索引**候选列表**（按优先级）。
--
-- 官方 API：`prefabIndex` = 控件模板索引，只读（文档 1200~1203）。
--
-- ★ 为什么是"列表"而不是"一个索引"：
--   真机实测（2026-09-26）：`cell.1.1.prefabIndex` 读出来是 **1073741848**，
--   那是**「预设按钮」这个基础模板**的索引 —— 读得到，但拿去
--   `InstantiateClientUIControl` 会**静默返回 nil**（不报错）。
--   所以"读到就用"是错的，必须**真的试着造一个**才知道能不能用。
--
--   于是这里把所有能想到的来源排成候选，由 ensure_cells 逐个实测，
--   第一个造得出东西的才算数。这样你**不用把索引数字抄进代码**：
--   只要在编辑器里「另存为模板」，再从那个模板**新建一个控件**、命名为
--   `tpl.cell`（或保留已有的 cell.1.1），脚本就能自己找到可用索引。
--
--   候选来源（按顺序、自动去重）：
--     ① cfg.cells.prefab        —— 显式指定的数字，最优先
--     ② cfg.cells.probe         —— 默认 "cell.1.1"
--     ③ tpl.cell / cell.tpl / cell.prefab —— 约定名：从「另存为模板」新建的那个控件
--     ④ auto_scan（默认开）—— **扫全树**，把所有"与参照格子不同的 prefabIndex"
--        也当候选。为什么加这个：真机 15:46 日志里，用户新存的模板索引是 1073741876，
--        而 `tpl.cell` 还是**上一次**从旧模板建的（索引仍是 1073741864），
--        于是新索引没有任何控件引用它 → 脚本读不到 → 显式配置之外只能靠扫。
--        扫出来的候选排在最后，且**仍然逐个真试**，所以不会误用。
function Adapter:_cells_prefabs(g)
  local out, seen = {}, {}
  local function add(idx, from)
    if type(idx) ~= "number" or idx <= 0 then return end
    if seen[idx] then return end
    seen[idx] = true
    out[#out + 1] = { index = idx, from = from }
  end

  add(g.prefab, "cfg.cells.prefab")

  -- ★ 基准索引**只从「参照格子」(probe) 取**，不能从"第一个找到的控件"推。
  --
  -- 为什么：支持**纯模板模式** —— 编辑器里一个真格子都不建，只在 board 下放一个
  -- `tpl.cell`（模板引用控件）。这时 probe（默认 cell.1.1）不存在，
  -- 若还按"第一个找到的"当基准，基准就会变成 `tpl.cell` 自己的索引，
  -- 于是后面的判断变成"和它自己不同才算可用" → 恒为假 → 又打出
  -- "没有可用的自定义模板"那种误导结论。
  --
  -- probe 不存在时基准保持 nil，任何能读到正整数的候选都算"可能可用"。
  local probe_id = g.probe or "cell.1.1"
  local base_idx = nil
  do
    local c = self:find(probe_id)
    if c ~= nil then
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok and type(p) == "number" and p > 0 then base_idx = p end
    end
  end
  -- ★ 把"这一刻参照格子在不在"**记下来**，给体检用。
  --
  -- 为什么必须记：`_cells_prefabs` 是在**生成之前**跑的，那时纯模板模式下
  -- 参照格子确实不存在；而体检（diagnose_template）是在**生成之后**跑的 ——
  -- 那时 `cell.1.1` 已经被脚本造出来了，现场再查就查得到，于是"纯模板模式"
  -- 这个事实会被**生成的副作用掩盖掉**，报不出来。
  -- 教训同前：要报**当时记录的实测事实**，不要过后现场重推。
  self.cells_probe_missing = (base_idx == nil)

  local names = g.prefab_from
    or { probe_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  for i = 1, #names do
    local c = self:find(tostring(names[i]))
    if c ~= nil then
      -- ★ 先读「引用控件模板索引」—— 模板引用控件引用的是它，不是 prefabIndex。
      --   两者都加进来（referenced 优先），因为：
      --     · 模板引用控件：referencedPrefabIndex 才是被引用的模板；
      --     · 普通控件 / 脚本生成的副本：只有 prefabIndex 可读。
      local r = self:_ref_index_of(c)
      if r ~= nil then add(r, tostring(names[i]) .. ".referencedPrefabIndex") end
      local ok, p = pcall(function() return c.prefabIndex end)
      if ok then add(p, tostring(names[i])) end
    end
  end

  -- ④ 扫全树
  if g.auto_scan ~= false and game ~= nil and game.GetClientUIRoots ~= nil then
    local found = {}
    local ok, roots = pcall(game.GetClientUIRoots)
    if ok and type(roots) == "table" then
      local function walk(c, depth)
        if c == nil or depth > 8 or #found > 400 then return end
        local p = nil
        pcall(function() p = c.prefabIndex end)
        if type(p) == "number" and p > 0 and p ~= base_idx and not seen[p] then
          local nm = "?"
          pcall(function() nm = tostring(c.name) end)
          found[#found + 1] = { index = p, name = nm }
        end
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do walk(kids[i], depth + 1) end
        end
      end
      for i = 1, #roots do walk(roots[i], 0) end
    end
    for i = 1, #found do
      add(found[i].index, "扫描到 " .. found[i].name)
    end
  end

  return out
end

-- 兼容旧名（别处还在用）
function Adapter:_cells_prefab(g)
  local list = self:_cells_prefabs(g)
  if list[1] ~= nil then return list[1].index end
  return nil
end

-- ★★★★★ 2026-10-02 **给脚本生成的格子"上底图"**（纯模板模式专用，不依赖参照格子）。
--
--   真机症状（用户 16:51）：格子在树上 `visible=true`、位置尺寸都对，但画面上
--   **只有两条细边框**（`wall.up` / `wall.left`），看起来像"棋盘没出现"。
--   日志里 `face visible=false` ⇒ 底图是关的。
--
--   为什么关着：`_cells_stamp` 需要**参照格子**才能"照抄图片"；重建后是纯模板模式
--   （没有 `cell.1.1`）⇒ 那条路不执行 ⇒ 副本保留模板快照的状态（模板里 `face` 就是关的）。
--
--   ⇒ 这里自己来：打开 `face`、按格子几何铺满、塞一张底图（默认 106053 白色底）。
--     每一步都 pcall + 可选日志，失败也不会中断生成。
function Adapter:_cells_paint(ctrl, size, cell_id, img)
  if ctrl == nil then return false end
  -- ★★★★★ 2026-10-02 **必须用 `self:sub()`，不能用裸 `GetChild("face")`**。
  --
  --   真机日志自己写着：「ℹ️ 子控件装在中间容器 `content` 里（方案 A）—— 按路径查找」。
  --   也就是说 `face` **不是格子的直接子控件**，而是 `cell.content.face`。
  --   `GetChild("face")` 直接返回 nil ⇒ 我的第一版 `_cells_paint` 什么都没做、
  --   连日志都没打（因为提前 return 了）⇒ 17:05 / 17:24 两次都没生效。
  --   项目自己的 `sub()` 会依次尝试：直接子控件 → `content`/`root`/`body` → 深一层。
  local face = nil
  if cell_id ~= nil then
    pcall(function() face = self:sub(cell_id, "face") end)
  end
  if face == nil and ctrl.GetChild ~= nil then
    pcall(function() face = ctrl:GetChild("face") end)      -- 兜底：扁平配法
  end
  if face == nil then return false end
  if face.SetVisible then pcall(function() face:SetVisible(true) end) end


  -- ★★★★★ 2026-10-05 **每帧重放墙/门的可见性** ✗✓ —— 这是本轮的定案修法 ✓
  --
  --   真机日志给出的对照（同一份日志里 ✓）：
  --     · 「格子底图已点亮：25 个 face（**每帧保持**）」✓ —— ★ `face` 走的就是这条路 ✓
  --     · 而墙/门只在属性下发那趟设一次 ✗ ⇒ ★★ 被覆盖后**没人救**✗ ⇒ 看不见 ✓
  --     · 而那一刻读回 `wall.up(vis=true)` ✓ ⇒ ★★ 读回 true 与屏幕空白**同时成立** ✓✓
  --   ⇒ 在这里（每帧都会跑 ✓）把 `_apply_edges` 记下的意图重放一遍 ✓
  --   ⚠️ 只重放**已经记录过**的格子 ✗ —— 没下发过就什么都不做（不越权 ✓）
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  -- ★★ 性能待办 ★ 标签 **PERF-1**（★ 2026-10-06 标记 ✓ **先不动** ✗ 等框架稳定再回来 ✓）
  --
  --   ★ 用户 2026-10-06 指示：★「3 标记好字段位置，先不动，★ 等框架稳定了再回来弄」✓
  --
  --   ★ **三处字段（★ 改这里要一起看 ✓）**：
  --     · **记录**：`_apply_edges` 写 `self._edge_want[id][prefix.."."..side] = want`
  --       ⇒ ★ 本文件 **L3798~3800**（★ 另有一份同类写在 **L3775~3777** ✓）
  --     · **重放**：★ 就是下面 `for name, want in pairs(w)` 那段 ✓
  --       ⇒ ★ 每帧约 **200 次**「缓存查表 `self:sub` + `SetVisible`」✗
  --     · **触发**：`_cells_paint` 由 ★ **L2071** 每帧调用 ✓（★ 同一条路还负责点亮 `face` ✓）
  --     · **事件驱动那份**：★ 对称恢复分支 —— 本文件 **L4267** 读 `_edge_want` ✓
  --
  --   ★ 为什么当初要每帧重放 ✗：★ `hide_kids`（★ **L4230** ✓）会**递归藏子树** ✗
  --     且**只藏不显** ✗ ⇒ ★ 必须有东西**每帧把"该亮的"重新点亮** ✓
  --     ★ 否则真机症状：★「第一关的墙/门永远不画」✓（★ 那个 bug 的根因 ✓）
  --   ⇒ ★★ **要省成本，正确顺序** ✓：
  --     ★ ① 先确认 `L4267` 那条**对称恢复覆盖了所有 hide 路径** ✓
  --     ★ ② 再把这里从"每帧"改成"**脏标记驱动**" ✗
  --     ★ ③ ★ **不能直接删** ✗ —— ★ 删了会退回那个 bug ✓
  --   ★ 测量入口 ✓：`tests/grid_cost.lua`（13 项 ✓）· `tests/_wip/probe_*` 里那几条计数 ✓
  -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  if cell_id ~= nil and self._edge_want ~= nil then
    local w = self._edge_want[cell_id]
    if w ~= nil then
      for name, want in pairs(w) do
        local s2 = self:sub(cell_id, name)
        if s2 ~= nil and s2.SetVisible ~= nil then
          pcall(function() s2:SetVisible(want) end)
        end
      end
    end
  end
  -- 铺满格子（子控件默认可能比格子小，**甚至尺寸是 0** —— 两种都会让它"看不见"）
  --
  -- ★★★★★ 2026-10-04 **`size` 允许省略：不给就按控件自己的实际尺寸算。**
  --   为什么加这条：七个 `hex.*` 图标是**运行时按规划尺寸**建出来的，
  --   调用点手上没有"格子边长"这个量；但控件的 `sizeDelta` 就是答案。
  --   真机证据（17:02→17:31 两版对比）：同一条"深层设图"路径在 v044（纯图片模板）
  --   下图标是**看得见**的，换成格子模板后就看不见了 —— 差异正是**尺寸**：
  --   纯图片模板的图片子节点自带尺寸，格子模板的 `face` 默认尺寸是 0。
  if size == nil and ctrl.GetSizeDelta ~= nil then
    local w, h = nil, nil
    pcall(function() w, h = ctrl:GetSizeDelta() end)
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      size = math.min(w, h)
    end
  end
  if size ~= nil and face.SetSizeDelta then
    pcall(function() face:SetSizeDelta(size, size) end)
  end
  if face.SetAnchoredPosition then pcall(function() face:SetAnchoredPosition(0, 0) end) end
  -- 图片：第 4 个参数优先（七个图标各用各的素材），否则用格子的默认底图
  local use_img = img or (self.cfg.cells and self.cfg.cells.face_image) or 106053
  if face.SetImage then
    local ok = pcall(function() face:SetImage(nil, use_img) end)
    if not ok then pcall(function() face:SetImage(use_img) end) end      -- 两种签名都试
  end
  -- 读回，把结果说出来（否则又是"改了没生效"却看不出来）
  local vis, iid = "?", "?"
  pcall(function() vis = tostring(face.visible) end)
  pcall(function() iid = tostring(face.imageId) end)
  if self.cfg.cells and self.cfg.cells.debug_paint ~= false then
    self:warn_once("cells:paint",
      "格子底图已设置：face(visible=" .. vis .. ", imageId=" .. iid .. ")"
      .. "（如果画面上棋盘还是不出现，就把这行贴给我）")
  end
  return true
end

-- 把参照格子的 face 图片「盖章」到目标格子上。
-- 为什么要这一步：「另存为模板」存的是**当时的快照**。如果之后又给格子加了底图，
-- 用旧模板生成出来的副本会全是透明的（看起来像"没生成"）。
-- 图片控件的 imageSource / imageId 是只读可读的（API 文档 1427~1434），
-- SetImage(imageSource, imageId) 是写接口（1503），所以可以直接照抄。
function Adapter:_cells_stamp(target, ref)
  if target == nil or ref == nil then return false end
  if target.GetChild == nil or ref.GetChild == nil then return false end
  local my_face, ref_face
  pcall(function() my_face  = target:GetChild("face") end)
  pcall(function() ref_face = ref:GetChild("face") end)
  if my_face == nil or ref_face == nil then return false end
  if my_face.SetImage == nil then return false end

  local src, id, col
  pcall(function() src = ref_face.imageSource end)
  pcall(function() id  = ref_face.imageId end)
  if id == nil then return false end
  local ok = pcall(function() my_face:SetImage(src, id) end)
  pcall(function() col = ref_face.imageColor end)
  if col ~= nil then pcall(function() my_face.imageColor = col end) end
  return ok
end

-- 确保 board 下有全部 cell.<r>.<c>：编辑器里已摆好的不动，缺的按模板生成。
-- 返回"新建了几个"。没有配置 cfg.cells 时直接返回 0（不影响纯手摆的用法）。
-- ★★★★★ 2026-10-02 **用"脚本创建"重做选关按钮**（用户指定的另一条路线）。
--
--   为什么：真机证明**只有脚本创建的控件能收到点击** ——
--     关卡里的 25 个格子（脚本用 `game.InstantiateClientUIControl` 建）**能点**；
--     而编辑器里摆的 `select.card.*` / `select.back` **点了没反应**。
--   用户决定：**先用脚本创建把选关页做出来**，成功后再回头查"编辑器控件为什么不行"。
--
--   实现要点（照抄 `ensure_cells` 那条**已验证可行**的路）：
--     · 用**同一个模板索引** `cfg.cells.prefab`（真机验证过它能实例化）
--     · 父级挂在 **`board`** 下 —— 因为真机证明"`board` 下的脚本控件能收到点击"
--     · 改名 + **读回核对**（改名不生效会让 `find` 找不到，这个坑格子那轮踩过）
--     · 记进 `self.instantiated`（只有脚本生成的才允许销毁）
--
--   按钮 id：`selbtn.1` … `selbtn.N`（N = 关卡数，由调用方传）
function Adapter:ensure_widgets(count)
  count = count or 8
  if game == nil or game.InstantiateClientUIControl == nil then
    return 0, "环境没有 game.InstantiateClientUIControl"
  end
  -- ① 先建**容器**：容器模板来自 cfg.stage.prefab（用户 2026-10-02 给的 1073742330）
  local bar = self:find("selbar")
  if bar == nil then
    local cprefab = self.cfg.stage and self.cfg.stage.prefab
    if cprefab == nil then return 0, "没有 cfg.stage.prefab（没有容器模板）" end
    local cparent = self:find("stage")
    if cparent == nil then return 0, "找不到父容器 stage" end
    local ok, obj = pcall(game.InstantiateClientUIControl, cprefab, cparent)
    if not ok or obj == nil then
      return 0, "容器模板 " .. tostring(cprefab) .. " 实例化失败（它可能不是「客户端控件模板」）"
    end
    pcall(function() obj.name = "selbar" end)
    self.controls["selbar"] = obj
    self.instantiated = self.instantiated or {}
    self.instantiated["selbar"] = true
    bar = obj
  end
  -- ② 再在容器下建**按钮**（cell 模板 —— 真机验证过能实例化、能收到点击）
  local prefab = self.cfg.cells and self.cfg.cells.prefab
  if prefab == nil then return 0, "没有 cfg.cells.prefab（没有按钮模板）" end
  local made, existed = 0, 0
  for i = 1, count do
    local id = "selbtn." .. tostring(i)
    if self:find(id) ~= nil then
      existed = existed + 1
    else
      local ok, obj = pcall(game.InstantiateClientUIControl, prefab, bar)
      if ok and obj then
        pcall(function() obj.name = id end)
        local got = nil
        pcall(function() got = tostring(obj.name) end)
        if got ~= id then
          self:warn_once("selbtn:name:" .. id,
            "选关按钮改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。")
        end
        self.controls[id] = obj
        self.instantiated = self.instantiated or {}
        self.instantiated[id] = true
        made = made + 1
      end
    end
  end
  -- ★★★★★ 2026-10-03 **源头修 bug**：创建完 `selbar` 与 `selbtn.*` 后**立刻按当前屏幕设可见性**。
  --
  --   背景（真机 22:14 日志）：关卡界面里 `selbar`(1500x700) + 4 个 `selbtn.*` **一直可见**，
  --   压在棋盘第二行上；而 `selbtn` 绑的是 `pick_level` ⇒ 玩家点到就"返回选关"。
  --   我在 `main.lua` 的每帧同步里压过，但**压不住** ⇒ 说明源头（这里）每次开局都把它们
  --   设成可见，而且时机在我的同步之后 ⇒ 必须**在创建处**就设对。
  --
  --   ⚠️ 这里读不到 `Murdoku` 的 screen 状态（适配层不该依赖上层），
  --      所以用一个简单约定：**建好后一律先隐藏**；真正的显隐由 `main.lua` 的
  --      `apply_screen_hide` / 每帧同步按屏幕打开。若某处需要"建完就显示"，它会自己再打开。
  local hide_selbar = function(c)
    if c == nil then return end
    pcall(function() c:SetVisible(false) end)
  end
  if bar ~= nil then hide_selbar(bar) end
  for i = 1, count do
    local c = nil
    pcall(function() c = self:find("selbtn." .. tostring(i)) end)
    hide_selbar(c)
  end
  -- 诊断（每局一次）：把这三组的实际可见性读回来，方便真机核对
  if print then
    local rb = "?"
    pcall(function() rb = tostring(bar and bar.visible) end)
    local r1 = "?"
    pcall(function() local c = self:find("selbtn.1") if c then r1 = tostring(c.visible) end end)
    local rt = "?"
    pcall(function() local c = self:find("tpl-container") if c then rt = tostring(c.visible) end end)
    print("[murdoku] 选关条创建后已隐藏：selbar=" .. rb .. "  selbtn.1=" .. r1 .. "  tpl-container=" .. rt)
  end
  return made, nil, existed
end
function Adapter:ensure_cells(rows, cols)
  local g = self.cfg.cells
  if g == nil then return 0 end

  -- ★ 先把"实测结果"记成**失败**，后面任何一条成功路径再改写它。
  --
  -- 为什么在开头设：`ensure_cells` 有好几个早退分支（找不到父控件 / 没有 API /
  -- 没有索引 / 全部实例化失败），它们都是 `return 0`。若只在末尾的成功路径里写，
  -- 早退时 `self.cells_ok` 会停在 nil → `diagnose_template` 只能退回**猜**，
  -- 于是又会出现"生成失败了、体检却说可能是可用的"这种误导
  -- （2026-09-26 真机日志里就是这么被坑的）。
  self.cells_ok, self.cells_made, self.cells_total = false, 0, rows * cols
  -- 记下当前关卡的棋盘尺寸：逐格自检（diagnose_grid）要用它，
  -- 而且它比 cfg.cells.rows/cols 里那个"兜底值"准。
  self.cells_rows, self.cells_cols = rows, cols

  local parent = self:find(g.parent or "board")
  if parent == nil then
    self:warn_once("cells:parent",
      "生成格子失败：找不到父控件 " .. tostring(g.parent or "board"))
    self:_cells_report(5)
    return 0
  end

  -- ══════════════════════════════════════════════════════════════════════
  -- ★ 先把"占着格子名字的模板引用控件"请走
  --
  -- 真机 17:17 / 17:23 两张截图 + 日志：`cell.1.1` 的 `prefabIndex` **正好等于**
  -- `cfg.cells.prefab` —— 说明它**就是那个模板引用控件本身**，不是格子。
  -- 于是：
  --   · 它被算成"已存在" → missing 少 1 → **那一格永远不会被生成**；
  --   · 引用控件渲染不出格子副本 → 截图里 (1,1) 看着是空的（"第一个格子没造出来"）。
  --
  -- 用户提的解法方向对（"在那一格再生成一个覆盖它"），但**不能同名** ——
  -- 两个控件都叫 cell.1.1 的话 `find` 会取到编辑器那个，点击/渲染全打到错的对象上。
  -- 所以这里**先把它改名让位**，再由下面的循环在那一格**真的生成一个副本**。
  --
  -- ⚠️ 只改**编辑器里手摆的**（`self.instantiated` 里没有记录的），
  --    否则第二次调用（切关/重开）会把**脚本自己生成的**格子也改名重造，来回churn。
  -- ══════════════════════════════════════════════════════════════════════
  local moved = 0
  if type(g.prefab) == "number" and g.prefab > 0 then
    for r = 1, rows do
      for c = 1, cols do
        local id = self:cell_id(r, c)
        local ctrl = self:find(id)
        if ctrl ~= nil and not (self.instantiated and self.instantiated[id]) then
          -- 判定"它就是模板引用控件"：引用索引或自身索引命中配置的模板索引
          local hit = (self:_ref_index_of(ctrl) == g.prefab)
          if not hit then
            local p = nil
            pcall(function() p = ctrl.prefabIndex end)
            hit = (p == g.prefab)
          end
          if hit then
            local newname = "__tpl_ref_" .. id
            local ok = pcall(function() ctrl.name = newname end)
            if ok then
              self:drop_lookup(id)             -- 清掉旧名字的两半缓存，find 会重新走树
              self.controls[newname] = ctrl
              self:_park_control(ctrl)         -- ★ 挪出画布（不依赖 visible/active 语义）
              self:_note_parked(newname, ctrl) -- ★ 记账（按控件身份去重，进 N 次关也只记一次）
              moved = moved + 1
            end
          end
        end
      end
    end
  end
  if moved > 0 and print then
    print("[murdoku] 有 " .. moved .. " 个格子位置的控件其实是**模板引用控件本身**"
      .. "（索引 == cfg.cells.prefab）→ 已改名让位（__tpl_ref_*）并隐藏，"
      .. "脚本会在这些位置**真的生成格子副本**")
  end

  -- ★ 模板引用控件**不该出现在棋盘上**（它是"模板的引用"，不是格子）。
  --
  -- 为什么不只靠 `hide_unlisted`：那个函数只扫**受管容器的直接子控件**
  -- （MANAGED 列表里那 10 个）。真机截图显示 `tpl.cell` 仍然占着一个位置 ——
  -- 它可能不在受管容器的直接子层、或 `SetVisible` 对它没生效。这里**显式再藏一遍**，
  -- 按名字点名（`prefab_from` 里那些约定名 + 上面改名出来的 `__tpl_ref_*`）。
  do
    local hide_names = {}
    if type(g.prefab_from) == "table" then
      for i = 1, #g.prefab_from do hide_names[#hide_names + 1] = tostring(g.prefab_from[i]) end
    end
    -- 默认约定名（cfg.prefab_from 没配时也能生效）
    for _, n in ipairs({ "tpl.cell", "cell.tpl", "cell.prefab" }) do
      hide_names[#hide_names + 1] = n
    end
    local hid = 0
    for i = 1, #hide_names do
      local n = hide_names[i]
      if n ~= (g.probe or "cell.1.1") then          -- 别把真格子（参照格子）藏了
        local c = self:find(n)
        if c ~= nil then
          -- ★ 用 _park_control（挪出画布 + 缩 0 + 隐藏），不只用 SetVisible：
          --   真机截图证明 `tpl.cell` 仍然占着一个格子位置。
          if self:_park_control(c) then
            self:_note_parked(n, c)      -- ★ 记账（同一个控件进 N 次关也只登记一次）
            hid = hid + 1
          end
        end
      end
    end
    if hid > 0 and print then
      print("[murdoku] 已把 " .. hid .. " 个模板引用控件**挪出画布**"
        .. "（它们只是模板的引用，不该出现在棋盘上）")
    end
  end

  -- 先数一遍：**编辑器里已经摆好的格子根本不需要模板**。
  -- （旧实现无条件先要模板索引，导致「25 格都手摆好了」也直接 return，
  --   连摆正都不做 —— 2026-09-26 修。）
  --
  -- ★ 顺便记下"**生成前就存在**"的格子 —— 体检用它解释很容易看错的现象。
  local missing = 0
  self.cells_preexisting = {}
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      if self:find(id) == nil then
        missing = missing + 1
      else
        self.cells_preexisting[id] = true
      end
    end
  end

  if missing == 0 then
    -- 一格不缺 → 没生成也算"成功"，把这个实测结果记下来给体检用
    self.cells_ok = true
    self.cells_index = nil
    self.cells_made = 0
    self.cells_total = rows * cols
  end

  local prefab = nil
  local prefab_from = nil
  local tried = {}
  if missing > 0 then
    if game == nil or game.InstantiateClientUIControl == nil then
      self:_cells_report(4)          -- 没有那个 API
      return 0
    end
    -- ★ 候选 + **实测**：读到索引不算数，真的造得出一个才算数。
    --   基础模板（「预设按钮」那个 1073741848）读得到但实例化返回 nil，
    --   所以这里挨个试，第一个成功的就拿下 —— 你不需要抄任何数字。
    local cands = self:_cells_prefabs(g)
    if #cands == 0 then
      self:warn_once("cells:prefab",
        "缺 " .. missing .. " 个格子，但读不到任何控件模板索引。\n"
        .. "       两个办法任选：\n"
        .. "       ① 在编辑器里右键 cell.1.1 →【另存为模板】，"
        .. "再从那个模板**新建一个控件**放到 board 下、改名 `tpl.cell`（位置随意，脚本会藏起来）；\n"
        .. "       ② 照 docs/控件坐标表-1600x900.md 把格子手动摆齐（脚本就不再生成）。")
      self:_cells_report(1)          -- 读不到模板索引
      return 0
    end
    for i = 1, #cands do
      local c = cands[i]
      local ok, obj = pcall(game.InstantiateClientUIControl, c.index, parent)
      tried[#tried + 1] = tostring(c.index) .. "(" .. c.from .. ")"
      if ok and obj ~= nil then
        prefab, prefab_from = c.index, c.from
        -- ══════════════════════════════════════════════════════════════════
        -- ★★ 探针**用完立刻销毁，绝不复用**。
        --
        -- 曾经这里有个"聪明"的优化：既然为了验证索引已经造出来一个，那就别浪费，
        -- 直接把它改名成第一个缺的格子收下。
        --
        -- **真机 2026-09-26 18:13 的逐格自检证明这个优化是错的**：
        --   board 树上实际有 25 个子控件：tpl.cell cell.1.2 … cell.5.5
        --   ⚠️ 这些格子在树上根本找不到：**cell.1.1**
        -- 也就是——**循环里正常 Instantiate 出来的 24 个全都在树上**（尺寸 135×135、
        -- visible/active 都对），**唯独那个"试造"出来的没有**。
        -- 它虽然被改了名、也进了名字缓存（所以 `find` 找得到、计数说 25/25 齐全），
        -- 但**它不是 board 的子控件**，引擎不会画它、`GetChildren()` 也列不出它。
        --
        -- 教训：**引擎返回的对象未必已经挂到 parent 上** —— 至少"第一个/最早那个"
        -- 在真机上有这个差异。所以别对它做任何假设，验证完就销毁，让每个格子
        -- 都走**同一条**正常路径。
        -- ══════════════════════════════════════════════════════════════════
        if game.DestroyClientUIControl ~= nil then
          local dok = pcall(game.DestroyClientUIControl, obj)
          if print then
            print("[murdoku] 模板索引 " .. tostring(c.index) .. " 验证通过（试造成功），"
              .. "探针已" .. (dok and "销毁" or "**销毁失败**（不影响生成）")
              .. " —— 25 个格子都会走同一条正常路径")
          end
        end
        break
      end
    end
    if prefab == nil then
      self:warn_once("cells:inst",
        "有 " .. missing .. " 个格子还没建，试过 " .. #cands .. " 个模板索引"
        .. "（" .. table.concat(tried, "、") .. "）**全部实例化失败**（返回 nil）。\n"
        .. "       ⚠️ 注意：**右键「另存为模板」存出来的索引不算数**。\n"
        .. "       官方硬约束：除「客户端控件容器画布中的控件」和「**客户端控件模板**中的控件」外，\n"
        .. "       其他控件都是**服务器控件**，其模板索引**无法被客户端脚本调用**。\n"
        .. "       正确入口：界面控件组管理 → 界面控件组库 → **客户端控件模板**\n"
        .. "                 →【添加客户端控件】→ 加一个预设按钮、配好子控件 → **存为模板**\n"
        .. "       然后二选一：\n"
        .. "         ① 把该模板的「控件模板索引 ID」填进 cfg.cells.prefab（最稳，脚本会最先试它）；\n"
        .. "         ② 或把该模板放进容器画布、改名 tpl.cell（脚本会扫到它的索引）。")
      self:_cells_report(1)
      return 0
    end
    if print then
      print("[murdoku] 格子模板索引 " .. tostring(prefab)
        .. "（来自 " .. tostring(prefab_from) .. "）可用；缺 " .. missing .. " 个格子，开始补建")
    end
  end

  local first_err = nil
  local made = 0
  local ref = self:find(g.probe or "cell.1.1")   -- 参照格子：章它的图片
  if ref == nil and made > 0 then
    -- 纯模板模式下没有参照格子，`_cells_stamp` 这条"补图"保险就失效了 ——
    -- 生成的格子会**完全依赖模板快照里的美术**。这件事必须说出来：
    -- 否则以后副本透明，会不知道是"没生成"还是"生成时模板就没配图"。
    self:warn_once("cells:noref",
      "没有参照格子（" .. tostring(g.probe or "cell.1.1") .. "），"
      .. "所以**不做图片盖章** —— 生成的格子外观**完全取自模板快照**。\n"
      .. "       这是纯模板模式的正常代价。如果副本看不见，去模板里补底图后**重存一次模板**。")
  end
  local n = math.max(rows, cols)
  local cell_size = self:cell_geometry(n)
  -- ★ 图层顺序那一趟的实测账：排过几个格子、一共排上几个子控件（见 1889 行附近的说明）。
  local layer_cells, layer_subs = 0, 0
  for r = 1, rows do
    for c = 1, cols do
      local id = self:cell_id(r, c)
      local ctrl = self:find(id)
      if ctrl == nil then
        local ok, obj = pcall(game.InstantiateClientUIControl, prefab, parent)
        if ok and obj then
          pcall(function() obj.name = id end)
          -- ★ 改完名要**读回来核对**。
          --   18:13 那次就是"改了名 + 进了名字缓存"骗过了所有检查（find 找得到、
          --   计数 25/25 齐全），可树上其实没有它。所以这里显式读回一次，
          --   不一致就记一笔 —— 这样下次出问题在日志里立刻能看见。
          local got = nil
          pcall(function() got = tostring(obj.name) end)
          if got ~= id then
            self:warn_once("cells:name:" .. id,
              "改名字没生效：想要 `" .. id .. "`，读回来是 `" .. tostring(got) .. "`。\n"
              .. "       这个副本会**找不到**（也会挡住后面的同名格子），记下这一条备用。")
          end
          self.controls[id] = obj
          -- 同上面的"试造"：记下来这是我们生成的（改名让位那段靠它区分）
          self.instantiated = self.instantiated or {}
          self.instantiated[id] = true
          ctrl = obj
          made = made + 1
          self:_cells_stamp(ctrl, ref)     -- ★ 把参照格子的图片盖上去
          -- ★★★★★ 2026-10-02 **纯模板模式下必须自己给格子上底图** —— 这就是
          --   "棋盘没出现 / 只有一行一列"的真正原因。
          --
          --   真机日志（用户 16:51）：
          --       cell.1.1  visible=true  位置=(-237,237) 124x124    ← 格子本身可见
          --         face      visible=**false**  imageType=Stretch  imageId=106053
          --         wall.up   visible=true     ← 只有这两条边框是亮的
          --         wall.left visible=true
          --   ⇒ 格子"存在且可见"，但**底图 `face` 是关的** ⇒ 画面上只有两条细边框。
          --
          --   根因：`_cells_stamp` 只在**有参照格子**（`cell.1.1`）时才能"盖章"，
          --   而重建后是**纯模板模式**（没有参照格子）⇒ 整条补图路径不执行 ⇒
          --   副本的 `face` 保持"模板快照里的状态"（模板里它就是关的）。
          --
          --   ⇒ 所以这里**不依赖参照格子**，直接自己打开 `face` 并塞一张底图。
          --     图片 id 取 `cfg.cells.face_image`（默认 106053 —— 项目里已知的白色底），
          --     尺寸用格子自己算好的几何，保证铺满。
          self:_cells_paint(ctrl, cell_size, id)
        elseif first_err == nil then
          first_err = tostring(obj)
        end
      elseif g.stamp_existing == true then
        self:_cells_stamp(ctrl, ref)       -- 连编辑器里已摆的也一起盖章
      end

      -- force_position ~= false 时，把每个格子的锚点/中心/尺寸/位置都摆正。
      -- 这样棋盘永远是对的，不依赖编辑器里那个「位置」填得准不准，
      -- 也不再依赖 cfg 里的固定尺寸 —— 5×5 / 6×6 共用同一套编辑器控件。
      if ctrl ~= nil and g.force_position ~= false then
        -- ★ 先把中间容器的「屏蔽区域内点击事件穿透」关掉 ——
        --   否则点击到不了按钮，表现为"点格子没反应"而体检全绿。
        self:open_click_passthrough(id)
        -- ★ 再把图层顺序排定 —— 官方 `SetSiblingIndex`「数值越大越靠上」。
        --   用户提醒：层级**按模板里的位置**决定、不看生成顺序，且会互相覆盖，
        --   所以必须规划 + 显式排一遍（`cfg.cells.layer_order`，从下到上）。
        --
        -- ★★★★★ 2026-10-05 **返回值现在不当废物丢掉了**：它 = 这个格子里**真的排上了
        --   几个子控件**（`SetAsFirstSibling` 成功次数）。以前 `self:enforce_layers(id)`
        --   的结果没人看，于是"层序到底排没排上"在日志里**一个字都没有** ——
        --   而"白色 face 压住墙"（层序问题）和"墙根本没设"（属性问题）在画面上**长得一模一样**。
        --     · 每格 ≈ `#layer_order` ⇒ 层序确实排过；
        --     · =0 ⇒ 这个格子里**没有任何** `layer_order` 里的子控件名（模板没配/名字不同）
        --             ⇒ 层序**完全没动过**，遮挡就出在这里。
        --   累加后在关卡末尾**打一行**（放循环里会刷 25 行）。
        local n_layer = self:enforce_layers(id)
        layer_cells = layer_cells + 1
        layer_subs = layer_subs + (tonumber(n_layer) or 0)
        if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
        if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
        if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
        if ctrl.SetSizeDelta then
          pcall(function() ctrl:SetSizeDelta(cell_size, cell_size) end)
        end
        local x, y = self:cell_offset(r, c, n)
        if ctrl.SetAnchoredPosition and x ~= nil then
          pcall(function() ctrl:SetAnchoredPosition(x, y) end)
        end
        -- 格子里的 face/note/x 跟着格子一起缩放
        local kids = { "face", "x" }
        for i = 1, #kids do
          local k = self:sub(id, kids[i])
          if k ~= nil then
            if k.SetSizeDelta then pcall(function() k:SetSizeDelta(cell_size, cell_size) end) end
            if k.SetAnchoredPosition then pcall(function() k:SetAnchoredPosition(0, 0) end) end
            if k.SetPivot then pcall(function() k:SetPivot(0.5, 0.5) end) end
          end
        end
        local note = self:sub(id, "note")
        if note ~= nil and note.SetSizeDelta then
          pcall(function() note:SetSizeDelta(math.max(8, cell_size - 8), math.max(8, math.floor(cell_size * 0.28))) end)
          if note.SetAnchoredPosition then pcall(function() note:SetAnchoredPosition(0, 0) end) end
        end
      end
    end
  end

  if made == 0 and first_err ~= nil then    -- ★ 2026-09-26 真机实测：`cell.1.1.prefabIndex` 返回的往往是**「预设按钮」这个基础
    --   控件的索引**（这台机器上是 1073741848），拿它去 InstantiateClientUIControl
    --   会**返回 nil**（不报错，静默失败）—— 基础模板不允许这样实例化。
    --   所以这里要把"下一步做什么"讲清楚，否则只会看到一句没头没脑的 nil。
    self:warn_once("cells:inst",
      "有 " .. missing .. " 个格子还没建，想自动生成但失败了"
      .. "（模板索引 " .. tostring(prefab) .. "，接口返回 " .. first_err .. "）。\n"
      .. "       这通常是因为那个索引**不是客户端控件模板**，不能直接实例化。正确做法：\n"
      .. "       ① 界面控件组管理 → 界面控件组库 → **客户端控件模板** →【添加客户端控件】\n"
      .. "          → 加一个预设按钮、配好子控件 → **存为模板**；\n"
      .. "       ② **关键一步**：在容器画布里新建一个「**模板引用控件**」去**引用**那张模板\n"
      .. "          （**不能**用模板直接新建控件，那不算）；\n"
      .. "       ③ 把它的 `referencedPrefabIndex`（不是 `prefabIndex`！）填进\n"
      .. "          lua/entry_client_script.lua 的 cfg.cells.prefab，重新打包同步。\n"
      .. "       （也可以照 docs/控件坐标表-1600x900.md 把格子手动摆齐，脚本就不再生成。）")
    self:_cells_signal(100)        -- Instantiate 失败 → 100
  elseif g.debug_signal ~= false then
    -- ★ 无条件回报"到底建了几个"：边长 = 40 + made*8
    --   made=0  → 40（很小）        → 循环一次都没创建
    --   made=24 → 232（明显变大）   → 24 个都建了（若还看不见，就是副本没外观）
    if not self:_cells_signal(40 + made * 8) then
      self:warn_once("cells:signal", "诊断信号写入失败：一个可改尺寸的控件都没找到")
    end
  end
  -- ★ 唯一可靠的「到底成了没有」信号。
  --   副本可能因为**模板快照里没配美术**而完全透明 —— 光看画面根本分不出
  --   "没生成" 和 "生成了但看不见"。所以把实际存在数打进日志，一眼可判。
  if print then
    local have = 0
    for r = 1, rows do
      for c = 1, cols do
        if self:find(self:cell_id(r, c)) ~= nil then have = have + 1 end
      end
    end
    print("[murdoku] 棋盘格子：" .. have .. " / " .. (rows * cols) .. " 存在"
      .. "（本次新建 " .. made .. " 个，模板索引 " .. tostring(prefab) .. "）")
    -- 把**实测结果**存下来给 diagnose_template 用 —— 它必须报实际结果，
    -- 不能靠"索引看起来不同"猜（真机 16:07 就是这么被误导的）。
    self.cells_ok = (have >= rows * cols)
    self.cells_index = prefab
    self.cells_made = made
    self.cells_total = rows * cols
  end

  -- ★★★★★ 2026-10-05 **格子重建之后，必须清掉 `subs` 里的死句柄** ✗✓
  --
  --   这是"第一次进关墙/门不画、进别的关再回来就正常"的**真凶** ✓
  --   （★ 与素材无关 ✗ —— 素材是静态的，不会因为切一次关而变 ✓
  --     这条判据用户提过，我一度绕回素材，是错的 ✓）
  --
  --   机制（`Adapter:sub` 在 L502-504 ✓）：
  --     · 缓存键是 `parent_id .. "." .. child_name` ✓ —— ★ 键里有格子 id ✓
  --       ⇒ ★ 不跨格串号 ✓（这条先排除掉 ✓）
  --     · 但 `if cached ~= nil and cached ~= false then return cached end` ✗
  --       ⇒ ★★ **命中就永远返回旧句柄，从不失效、从不重查** ✗✓
  --     · 而 `ensure_widgets` 每次进关都会**把 25 个格子重新建一遍** ✗
  --       （真机日志：「本次新建 25 个」✓）
  --       ⇒ ★★ 旧格子对象已被销毁 ✗ 而 `self.subs` 里【还存着它们的子控件句柄】✓✓
  --       ⇒ ★★★ `SetVisible(true)` 调在死句柄上 ⇒ **静默 no-op** ⇒ 屏幕上不画 ✓
  --
  --   ★★ 这也解释了那个一直对不上的矛盾 ✓：
  --     · 我读回的 `sub.visible` = **true** ✗
  --       ⇒ ★ 因为我读的是**缓存里那个旧对象**的属性 ✓✓
  --       ⇒ ★★ "读回 true 但屏幕没有" 到此闭环 ✓
  --     · 而「进别的关再回来就正常」✓
  --       ⇒ ★ 因为那一趟 `find` 把键重新命中到**新建后的**子控件上 ✓
  --
  --   ★ 为什么在"重建完"这里清、而不是在 `sub` 里验活句柄 ✗：
  --     验活要每帧多一次探测 ✗ —— 移动端不划算 ✓
  --     建格是【每关一次】✓ 这里清 = 零常态开销 ✓
  do
    local cleared = 0
    for k in pairs(self.subs) do
      if type(k) == "string" and k:sub(1, 5) == "cell." then
        self.subs[k] = nil
        cleared = cleared + 1
      end
    end
  end

  -- ★★★★★ 2026-10-05 **图层顺序这一趟的实测结果 —— 每关一行**。
  --
  --   为什么必须打：`enforce_layers` 的返回值（= 真的排上了几个子控件）以前**被直接丢掉**，
  --   于是"层序到底动没动过"在日志里一个字都没有。而真机上"墙没画出来"有两个长得
  --   一模一样的成因：① 属性没送达；② 送达到了但**被上面的白色 face 盖住**（层序）。
  --   这一行 + 上面那两行"兄弟索引"合起来才能把 ① 和 ② 分开。
  --
  --   判读：
  --     · 每格 ≈ `#layer_order`（默认 12）⇒ 层序确实排过，遮挡不在这一步；
  --     · 平均 = 0 ⇒ 每个格子里都**没有任何** `layer_order` 里的子控件名
  --         ⇒ 层序**完全没动过**（`face` 就可能压在 `wall.*` 上面）；
  --     · 格子数 = 0 ⇒ 这一趟**根本没跑**（`cfg.cells.force_position = false`）。
  if print then
    if layer_cells == 0 then
      print("[murdoku] 图层顺序：本次进关**没有排过层序**（cfg.cells.force_position=false，"
        .. "或者这一关一个格子都没有）")
    elseif layer_subs == 0 then
      print("[murdoku] 图层顺序：对 " .. layer_cells .. " 个格子排过层序，"
        .. "但**一个子控件都没排上**（layer_order 里的名字一个都取不到）"
        .. " ⇒ 层序等于没动过，「白色 face 压住墙」这类遮挡就会长这样")
    else
      print(string.format("[murdoku] 图层顺序：对 %d 个格子排过层序，子控件成功置底 %d 个（平均 %.1f/格）",
        layer_cells, layer_subs, layer_subs / layer_cells))
    end
  end
  return made
end

-- 「把用不到的控件藏起来」。
--
-- 为什么必须在**适配层**做，而不是在界面层按 layout_plan 做：
--   编辑器里的控件是照着**所有关卡的最大并集**建的（6×6 关卡要 36 个格子、
--   角色多的一关要 tray.F），而界面层运行时只知道**当前这一关**的布局，
--   它压根不知道还有 cell.6.6 / clue.12 这些东西存在 —— 于是那些控件会一直
--   显示着别的关卡残留的文案和空格子。
--   所以这里直接在控件树上扫：**容器 → 直接子控件**，名字不在 keep 里的就藏。
--
-- 只扫一层是刻意的：face / note / x / text / bg 这些子控件在更深一层，
-- 它们不是界面层排布的，不能被误伤。
-- ★★★★★ 2026-10-02 **真机"点不动"的根因就在这里**：名单漏了 `home` / `select`。
--
--   引擎的点击派发条件是（见下面 `enable_cursor` 的注释）：
--     for i = t; i; i = i.parent do
--       if i.kind == "container" and i.showCursor then return true end
--     end
--   —— 一个控件要收到点击，**祖先链上必须有一个 kind=="container" 且 showCursor==true 的容器**。
--
--   脚本靠这份 `MANAGED` 名单去开那个开关（真机日志：`已由脚本打开 9 个容器的显示常驻光标`）。
--   而 **`home` / `select` 不在名单里** ⇒ 它们的子控件（主页四键 / 选关卡片 / 返回键）
--   全部落在门控②之外 ⇒ **点不动**。
--   这也解释了那个一直没解释的不对称：`home.*` 在主页能点（`root` 那条链当时是通的），
--   一切到选关就全废。
--
--   ⚠️ 这是本项目反复吃亏的"**门控②**"（docs/环境问题-诊断记录.md）：
--      加一个新容器就**必须**同步加进这份名单 —— 我加 `home`/`select` 时漏了。
local MANAGED = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal", "intro",
}

-- ★ 只有"开常驻光标"这件事需要额外覆盖 `home` / `select`。
--   `hide_unlisted` 用的是上面那份 MANAGED，语义不同，**不要混用**。
--   （第一版我直接加进 MANAGED，play_test 立刻从 3 红变 4 红。）
--   两份名单**分开**：MANAGED = "脚本托管的关卡内容器"；
--   CURSOR_CONTAINERS = "需要打开「显示常驻光标」的容器"（**必须包含每个屏幕容器**）。
local CURSOR_CONTAINERS = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal", "intro",
  "home", "select",
}

function Adapter:hide_unlisted(keep)
  local hidden = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil and parent.GetChildren ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local child = kids[k]
          local name = nil
          pcall(function() name = child.name end)
          if name ~= nil and name ~= "" and not keep[name] then
            if child.SetVisible ~= nil then
              local ok2 = pcall(function() child:SetVisible(false) end)
              if ok2 then hidden = hidden + 1 end
            end
          end
        end
      end
    end
  end
  return hidden
end

-- ════════════════════════════════════════════════════════════════════════
-- 头像卡归一化（只负责「应用」，几何由 ui_controller 算）
--
-- 为什么需要：头像卡的**列数按人数自适应**（保证永远只占 2 行，见 ui_controller），
-- 于是 5 人关是 3 列、7 人关是 4 列 —— 同一张 `tray.A` 在不同关卡里
-- **位置和尺寸都不一样**。但编辑器每个控件只能有一套几何，
-- 所有关卡共用一张界面布局。
--
-- 解决办法和棋盘格子一样：**编辑器按"最挤的情况"静态摆好，运行时由脚本按
-- 本关实际人数重新摆正**，一套布局通吃 5/6/7/8 人。
--
-- layout 由 `Controller:tray_layout_canvas()` 给出（画布绝对坐标），
-- 这里换算成「相对父级中心的偏移」（官方嵌套控件语义）再写下去。
-- ════════════════════════════════════════════════════════════════════════

-- ★★ 2026-09-28：**样式的缩放值只在这里定义一处**。
--
--   起因：用户报"已放置头像卡没有变小（0.72）"。查下来是 `style` 分支设了缩放，
--   但 `apply_tray_layout`（头像卡重排）随后把姿态重置了 ⇒ **设了又被覆盖**。
--   这和本工程里反复出现的"同一件事两处实现"是同一类问题
--   （前面吃过：`erases` 动效、运行时上色 vs 存档静态图、自动 ✗ 的三处还原）。
--   ⇒ 这次直接把缩放表抽成一个函数，**style 分支和重排函数都调它**，从根上不可能不一致。
function Adapter:scale_of_style(value)
  if value == "portrait" then return 0.86            -- 默认：比选中略小
  elseif value == "portrait.selected" then return 1.08
  elseif value == "portrait.placed" then return 0.72  -- 已放置：最小
  elseif value == "clue.focus" then return 1.03
  elseif value == "tab.active" then return 1.04 end
  return nil
end

-- ★★★ 2026-09-30：**样式的文字颜色也只在这里定义一处**（和 `scale_of_style` 同一套路）。
--
--   用途：参考《派蒙的执律庭实习》的线索卡 —— **人名/关键字是红色**、正文是白色。
--   官方**没有富文本**（查过 API 缓存），也没有文字宽度测量 ⇒ 一行里没法给某几个字换色，
--   只能"拆成两个控件"（`lua/ui_controller.lua` 的线索卡就是这么做的：
--   名字占固定宽度的第一列，正文从固定 x 起）。
--
--   ⚠️ 颜色是 **32 位整数**（真机日志 `fontColor=4294967295`），**没有 `Color()` 全局函数**
--   —— 所以这里直接写整数字面量。
--   ⚠️ `RED` 用的是**真机实测过的那个红**（就是 ✗ 标记用的 `4290453793`），
--   不自己调一个新色 —— 免得又变成"只在模拟器里好看"。
function Adapter:color_of_style(value)
  local WHITE = 4294967295            -- 0xFFFFFFFF：不透明白
  local RED   = 4290453793            -- 真机实测红（✗ 标记同款素材色）
  if value == "clue.who" then return RED end
  if value == "clue.what" or value == "clue" or value == "clue.ok" or value == "clue.focus" then
    return WHITE
  end
  return nil                          -- 其它样式不管颜色（保住各自现状）
end
-- 「按钮底图上色（运行时）」—— **顶层 helper**，由 `apply_tray_layout` 在末尾调用。
--
-- ⚠️ 2026-10-05 Round 45：它原来是 `apply_tray_layout` 函数体末尾的一整段循环。
--   为什么非搬出来不可：那段用 `names` / `done, miss`（`apply_tray_layout` 的局部变量），
--   而**两个本该顶层的方法**（`apply_ruler_layout` / `diagnose_overlap`）又必须在
--   `apply_tray_layout` **外面** ⇒ 只有把这段移出去，才可能让 `apply_tray_layout`
--   在方法**之前** `end` 掉 ⇒ 那两个方法才会在**加载时**就存在 ✓
--   （不搬的后果就是本 bug：方法被吞成子闭包 ⇒ `main.lua` 的 `~= nil` 守卫恒假
--     ⇒ 行标/列标对齐、相交诊断**从来没跑过**、零报错 ✗）
--
-- 等价性（与搬移前逐条对齐）：
--   · 同一段代码、同样顺序、同样计数、同样 `pcall` 兜底；
--   · 仍然只在 `cfg.btn_art == true` 时执行（由调用点判断，与搬移前的 `if` 一致 ✓）；
--   · 返回值与原来一致：`moved`（搬移前 `apply_tray_layout` 返回的就是搬移后的 `moved` ✓）；
--   · `names` / `done, miss` 改成**参数传入** —— 它们原来就在同一作用域，
--     直接传进来即可，**不读全局**（不传会 `#nil` 抛错 ✗）。
function Adapter:_tray_btn_art(moved, names, done, miss)
  names = names or {}
  done, miss = done or 0, miss or 0
  print("[murdoku] --- 按钮底图上色（运行时）---")
  for i = 1, #names do
    local cid = names[i]
    local c = self:find(cid)
    local bg = nil
    if c ~= nil then pcall(function() bg = self:sub(cid, "bg") end) end
    if bg ~= nil then
      if bg.SetAsLastSibling then pcall(function() bg:SetAsLastSibling() end) end
      local src = nil
      pcall(function() src = bg.imageSource end)
      -- ⚠️ 这个色号必须和**写进 .gil 的那个**一致！
      --   踩过的坑：我在 .gil 里把底图改成了浅蓝 100108，
      --   却忘了改这里硬编码的 100001 —— 于是**运行时又把它覆盖回深紫**。
      --   模拟器验证（tools/sim/verify_art.mjs）一眼看出来：`bg imageId=100001`。
      --   ⇒ 同一件事有两处实现，就必须同时改；这次靠"交付前验证外观"兜住了。
      local ok, err = pcall(function() bg:SetImage(src, self.cfg.bg_image_id or 100108) end)
      if ok then done = done + 1 else
        miss = miss + 1
        self:warn_once("bgset:" .. cid, "底图 SetImage 失败：" .. tostring(err))
      end
      if bg.SetVisible then pcall(function() bg:SetVisible(true) end) end
      if i <= 3 then
        local it, iid = "?", "?"
        pcall(function() it = tostring(bg.imageType) end)
        pcall(function() iid = tostring(bg.imageId) end)
        print(string.format("  %-16s bg：imageType=%s imageId=%s", cid, it, iid))
      end
      moved = moved + 1
    else
      miss = miss + 1
    end
  end
  print(string.format("  SetImage 成功 %d 个，缺失/失败 %d 个", done, miss))
  print("[murdoku] --- 按钮底图上色结束 ---")
  return moved
end

function Adapter:apply_tray_layout(layout)
  if layout == nil or layout.items == nil then return 0 end
  local parent = self:find(self.cfg.tray_parent or "tray")
  if parent == nil then
    self:warn_once("tray:parent", "找不到头像卡容器（cfg.tray_parent，默认 tray）")
    return 0
  end
  local moved = 0
  for i = 1, #layout.items do
    local it = layout.items[i]
    local ctrl = self:find(it.id)
    if ctrl ~= nil then
      local ox = it.cx - layout.tray_cx
      local oy = it.cy - layout.tray_cy
      if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
      if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
      if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
      if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(it.w, it.h) end) end
      if ctrl.SetAnchoredPosition then pcall(function() ctrl:SetAnchoredPosition(ox, oy) end) end
      -- ★★ 2026-09-28：**重排后必须把样式缩放重新施加一遍**。
      --
      --   这一行就是"已放置头像卡没变小"的修复点：
      --   原来 `style` 分支设了 0.72，但重排的 `SetSizeDelta`/`SetAnchoredPosition`
      --   会把姿态重置回 1.0，而重排发生在其后 ⇒ 玩家永远看不到那一档。
      --   缩放值取自 `scale_of_style`（与 style 分支**同一处定义**，不可能不一致）。
      local sty = self._style and self._style[it.id] or nil
      local sc2 = sty ~= nil and self:scale_of_style(sty) or nil
      if sc2 ~= nil and ctrl.SetLocalScale ~= nil then
        pcall(function() ctrl:SetLocalScale(sc2, sc2, 1) end)
      end
      -- 卡片里的 face / text 跟着一起变
      local kids = { "face", "text" }
      for k = 1, #kids do
        local sub = self:sub(it.id, kids[k])
        if sub ~= nil then
          if sub.SetSizeDelta then pcall(function() sub:SetSizeDelta(it.w, it.h) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(0, 0) end) end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
        end
      end
      moved = moved + 1
    end
  end

  -- ★ 头像卡体检（2026-09-27 新增）。
  --
  -- 为什么需要：用户问"tray 里的图我是不是也得补"。而按已真机确认的规则 ——
  --   **预设按钮只渲染"四个状态节点引用的"子控件**，未被引用的子控件**不显示**。
  --   用户往 tray.D 加了一个图片子控件，但**没动状态节点**，所以到底显不显示只有真机能答。
  -- 这条诊断把每张卡的"子控件清单 + visible + imageType + imageId"打出来：
  --   · 子控件**不在清单里** → 加子控件这步没生效（或没存进关卡）
  --   · 在清单里但 **visible=false** → 被脚本藏了
  --   · visible=true 但 imageId=nil → 没配图
  --   · 全都正常却看不见 → **就是状态节点没引用**（这条规则得到验证）
  if self.cfg.tray_diag ~= false and print then
    local names = { "A", "B", "C", "D", "E", "F", "V" }
    print("[murdoku] --- 头像卡体检（每张卡的子控件）---")
    for i = 1, #names do
      local cid = (self.cfg.tray_parent or "tray") .. "." .. names[i]
      local c = self:find(cid)
      if c ~= nil then
        local kids = nil
        pcall(function() if c.GetChildren then kids = c:GetChildren() end end)
        local n = (type(kids) == "table") and #kids or 0
        local parts = {}
        for k = 1, n do
          local kk = kids[k]
          local kn, kv, kt, ki = "?", "?", "?", "?"
          pcall(function() kn = tostring(kk.name) end)
          pcall(function() kv = tostring(kk.visible) end)
          pcall(function() kt = tostring(kk.imageType) end)
          pcall(function() ki = tostring(kk.imageId) end)
          parts[#parts + 1] = kn .. "(visible=" .. kv .. " type=" .. kt .. " id=" .. ki .. ")"
        end
        print(string.format("  %-9s 子控件 %d 个  %s", cid, n,
          (#parts > 0) and table.concat(parts, "  ") or "**（没有子控件）**"))
      else
        print(string.format("  %-9s **找不到这个控件**", cid))
      end
    end
    -- ★ 2026-09-28 扩展：**原来只查 7 张头像卡，按钮一个都没查** ——
    --   于是"按钮到底有没有子控件"在真机上完全看不出来，只能靠猜。
    --   按同一套判读法再查一批代表性按钮。
    local btns = { "tool.place", "tool.x", "tool.eraser", "action.submit", "action.undo",
                   "intro.next", "modal.suspect.A" }
    for i = 1, #btns do
      local cid = btns[i]
      local c = self:find(cid)
      if c ~= nil then
        local kids = nil
        pcall(function() if c.GetChildren then kids = c:GetChildren() end end)
        local n = (type(kids) == "table") and #kids or 0
        local parts = {}
        for k = 1, n do
          local kk = kids[k]
          local kn, kv, kt, ki = "?", "?", "?", "?"
          pcall(function() kn = tostring(kk.name) end)
          pcall(function() kv = tostring(kk.visible) end)
          pcall(function() kt = tostring(kk.imageType) end)
          pcall(function() ki = tostring(kk.imageId) end)
          parts[#parts + 1] = kn .. "(visible=" .. kv .. " type=" .. kt .. " id=" .. ki .. ")"
        end
        print(string.format("  %-18s 子控件 %d 个  %s", cid, n,
          (#parts > 0) and table.concat(parts, "  ") or "**（无子控件 → 完全透明看不见）**"))
      else
        print(string.format("  %-18s **找不到**", cid))
      end
    end
    print("[murdoku] --- 体检结束 ---")
  end
  -- ★★ 2026-09-28 新增：**运行时给按钮底图上色 + 提到最上层**。
  --
  -- 为什么必须走运行时：真机日志显示 `bg(visible=true type=Stretch id=100001)` ——
  --   存档里图片 ID **确实改成 100001 了**，但屏幕上**还是白块**。
  --   推断：那些白块是**按钮状态节点自带的白色底板**，盖在我的 `bg` 上面。
  --   ⇒ 两手一起上：
  --     ① 运行时 `SetImage`（这是已被证明能改图的路径）把底图设成有颜色的素材；
  --     ② `bg:SetAsLastSibling()` 把它提到最上层，压住状态节点那块白板。
  -- ★★ 2026-09-28：**改成默认关闭（opt-in）**。
    --
    -- 为什么：`.gil` 里每个按钮的 `bg` 已经带好了正确的 (source, id) 对
    --   （真机读出来 `src=4281536672 id=100108`，和棋盘上的浅蓝横墙一模一样）。
    --   而运行时再 `SetImage(bg.imageSource, 100108)` 反而把它**覆盖成了紫色** ——
    --   说明运行时读到的 `imageSource` 和我写进存档的**不是同一个值**，配错了图集。
    --   ⇒ 既然静态图已经对，就不该再动它。**同一件事有两处实现，就会有两处不一致** ——
    --     这一课我这个项目里已经吃了两次（另一次是 `erases` 动效）。
    --   想再实验运行时上色时，传 `cfg.btn_art = true` 打开。
    if self.cfg.btn_art == true and print then
    -- ⚠️ 名单**不能手写**！第一版我手写了 19 个，而实际有 35 个按钮 → 那 16 个
    --    （`action.q.*`、`modal.level.*` …）**从没被验证过**
    --    （真机日志 `SetImage 成功 19 个` 暴露的）。
    --    改成由调用方传入（`main.lua` 从规划里取 `kind == "button"`），有多少算多少。
    --
    -- ★★★★★ 2026-10-05 **这两个 local 必须提到这里**（Round 35 的结构性修复，最后一步）。
    --   原因：它们被**两个地方**用 —— 本 `btn_art` 块（函数末尾的上色循环，
    --   见下面 `--- 按钮底图上色（运行时）---` 那段），以及**两个彻底独立的功能**
    --   （`apply_ruler_layout` / `diagnose_overlap`，它们已挪到 `apply_tray_layout` 外面）。
    --   代价说明：现在 `cfg.btn_art ~= true` 时也会读一次 `cfg.btn_list`、建两个数 ——
    --   `apply_tray_layout` 只在开局摆一次，这点成本可忽略（不给每帧路径加负担）。
    local names = self.cfg.btn_list or {}
    local done, miss = 0, 0
    -- ★ ★ ★★★ 2026-10-05 **Round 35 收口**：块账在这里收平 ✓
    --
    --   历史（这条 bug 的形状很值得记）：
    --     L2371 的 `if self.cfg.btn_art == true and print then` 原来**一直没被关闭** ✗
    --     ⇒ 后面两个**顶层方法定义**被当成它的语句体吞了进去：
    --       `Adapter:apply_ruler_layout`（原 L2391）与 `Adapter:diagnose_overlap`（原 L2474）
    --     ⇒ Lua **不报错**（`end` 总数平衡），但这两个方法**只在 `apply_tray_layout`
    --       被调用过之后**才存在 ✗
    --     ⇒ `lua/main.lua` 的 `if a.apply_ruler_layout ~= nil then …` / `if diagnose_overlap then …`
    --       守卫**恒为假** ⇒「行标/列标对齐」与「相交诊断」**从来没跑过**（静默，零报错）✗
    --
    --   收口做法：两个方法整段**挪到本函数之后**（真正的文件顶层），
    --   上色循环留在本函数内（默认关闭）⇒ 本行的 `end` 关掉 `btn_art` 块 ✓
    --   ⇒ `node tools/audit/check_nesting.mjs` 的 `[嵌套]` 必须降到 **0 处** ✓
  end
  -- ★★★ 2026-10-05 Round 45：**上色循环已抽成顶层 helper** `Adapter:_tray_btn_art`
  --   （就定义在下面，`apply_tray_layout` **之前**）。
  --   为什么非抽不可：那段循环用 `names` / `done, miss`（本函数局部），
  --   而它**上面**那两个方法又必须在本函数**外面** ⇒ 只能把那段整段移出去 ✓
  --   等价性：同一段代码、同样顺序、同样计数、同样默认关闭（`cfg.btn_art`）✓
  -- ★★★★★ 2026-10-05 Round 48 修：下面这行调用用到了 `names` / `done` / `miss`，
  --   但抽 helper 时它们**没有跟着过来** ✗ ⇒ selene 报三条 `error[undefined_variable]` ✗
  --   （`names` / `done` / `miss` @L2461）⇒ 一旦 `cfg.btn_art = true` 就会**当场崩**（`#nil` 抛错 ✗）。
  --   该路径**默认关闭** ⇒ 离线测试测不到 ✗ ⇒ 只有静态检查能抓 ✓（这正是 selene 的价值 ✓）
  --   ⇒ 修法：在调用前就地声明（与 helper 内部那份等价 ✓ 传参用 ✓）
  local names = self.cfg.btn_list or {}
  local done, miss = 0, 0
  local moved_final = self:_tray_btn_art(moved, names, done, miss)
  -- ⚠️⚠️ 这个 `end` 关的就是 `apply_tray_layout`（`function` 在 2244 行）。
  --   它**必须**在下面两个方法之前 —— 否则那两个方法又会被吞成它的**子闭包**
  --   ⇒ 加载时不存在 ⇒ `main.lua` 的 `~= nil` 守卫恒假
  --   ⇒ 行标/列标对齐、相交诊断**静默失效**（零报错）✗ —— 就是本 bug 的原形。
  --   判据：`node tools/audit/check_nesting.mjs` ⇒ 这两个方法的 `深度` 必须是 **0** ✓
  return moved_final
end

-- 行标 / 列标按**格子的实际位置**对齐（顶层方法，加载时即存在）。
--
-- ⚠️ 曾被吞进 `apply_tray_layout` 体内 ⇒ `main.lua` 的守卫恒假 ⇒ **从未运行过**。
--    挪出来后 `main.lua:75/532` 的守卫才成立：`render()` 每次都调（见「新开销」说明）。
function Adapter:apply_ruler_layout(rows, cols)
  local g = self.cfg.cells or {}
  local ruler = self:find("ruler")
  if ruler == nil then return 0 end
  local rx, ry = nil, nil
  pcall(function() rx, ry = ruler:GetAnchoredPosition() end)
  if type(rx) ~= "number" or type(ry) ~= "number" then
    pcall(function() local p = ruler:GetUIPos() if p then rx, ry = p.x, p.y end end)
  end
  if type(rx) ~= "number" or type(ry) ~= "number" then rx, ry = 0, 0 end

  local moved = 0
  local function cellPos(i, j)
    local c = self:find(string.format("cell.%d.%d", i, j))
    if c == nil then return nil, nil end
    local x, y = nil, nil
    pcall(function() x, y = c:GetAnchoredPosition() end)
    if type(x) ~= "number" then
      pcall(function() local p = c:GetUIPos() if p then x, y = p.x, p.y end end)
    end
    return x, y
  end

  -- 列标：贴着第 1 行格子的横向中心
  for j = 1, math.min(cols or 5, 7) do
    local lbl = self:find("ruler.c." .. j)
    local cx, _ = cellPos(1, j)
    if lbl ~= nil and type(cx) == "number" then
      local lx, ly = nil, nil
      pcall(function() lx, ly = lbl:GetAnchoredPosition() end)
      if type(lx) ~= "number" then pcall(function() local p = lbl:GetUIPos() if p then lx, ly = p.x, p.y end end) end
      if type(lx) == "number" and lbl.SetAnchoredPosition then
        -- ★ 2026-09-28：**先把 pivot 归中**再定位。
        --   上一版只 SetAnchoredPosition，结果还剩 ~25px 的**恒定偏移** ——
        --   那是标签自身 pivot 与格子 pivot 不一致造成的（SetAnchoredPosition 定的是
        --   **锚点**的位置，pivot 不同则视觉中心不同）。
        --   与格子保持同一套 pivot（0.5,0.5），偏移就没了。
        if lbl.SetPivot then pcall(function() lbl:SetPivot(0.5, 0.5) end) end
        pcall(function() lbl:SetAnchoredPosition(cx - rx, ly) end)
        moved = moved + 1
      end
    end
  end
  -- 行标：贴着第 1 列格子的纵向中心
  for i = 1, math.min(rows or 5, 7) do
    local lbl = self:find("ruler.r." .. i)
    local _, cy = cellPos(i, 1)
    if lbl ~= nil and type(cy) == "number" then
      local lx, ly = nil, nil
      pcall(function() lx, ly = lbl:GetAnchoredPosition() end)
      if type(lx) ~= "number" then pcall(function() local p = lbl:GetUIPos() if p then lx, ly = p.x, p.y end end) end
      if type(ly) == "number" and lbl.SetAnchoredPosition then
        if lbl.SetPivot then pcall(function() lbl:SetPivot(0.5, 0.5) end) end
        pcall(function() lbl:SetAnchoredPosition(lx, cy - ry) end)
        moved = moved + 1
      end
    end
  end
  if print then
    -- ★★★★★ 2026-10-05 Round 49 **日志节流：只在"对齐结论真的变了"时才打** ✓
    --
    --   起因：本方法刚被修好（它以前被吞在 `apply_tray_layout` 里、**从未运行过** ✗），
    --   于是这段"无条件打印"第一次真的跑起来 ✗ ⇒ 实测 **2 行/次**，
    --   而调用频率是 **1.10 次/秒**（`main.lua:709` 的 `Murdoku.render` 被
    --   `sec ~= last_tick or controller.dirty` 门控）⇒ **≈2.2 行/秒 ≈ 7900 行/小时** ✗
    --   ⇒ 移动端日志洪水（也会拖慢真机）。**修好一个功能反而引入了负担** ✓ 所以要节流。
    --
    --   做法：把**会被打印出来的那些数**拼成结论串；与上次相同 ⇒ **整段跳过**（连日志都不打）✓
    --   ⚠️ 两个坑（都是踩过的 ✗）：
    --     ① **签名里不能塞"没被打印的数"** ✗ —— 例如 `ly1` / `rx1`（读了但没打），
    --        它们会随引擎抖动 ⇒ 误判"结论变了" ⇒ 白打一遍，节流被击穿 ✓
    --     ② `string.format` 的**占位符不能比参数多** ✗ —— 否则报
    --        `bad argument #N to 'format'`，而它若发生在 `on_start` 的 pcall 里会被**静默吞掉** ✗
    --   反向对照（防"静默阉割"）：把 `cell.1.1` 横移 ⇒ **正好打 2 行** ✓；再连调 20 次 ⇒ **0 行** ✓
    local cx1, cy1 = cellPos(1, 1)
    local l1, r1 = self:find("ruler.c.1"), self:find("ruler.r.1")
    local lx1, ly1 = nil, nil
    if l1 then pcall(function() lx1, ly1 = l1:GetAnchoredPosition() end) end
    local rx1, ry1 = nil, nil
    if r1 then pcall(function() rx1, ry1 = r1:GetAnchoredPosition() end) end
    -- 签名 = **只由下面两行 print 用到的数**构成 ✓（`ly1` / `rx1` 不进来 ✓）
    local sig = string.format("%d|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f",
      moved, rx, ry, cx1 or 0, cy1 or 0, lx1 or 0, ry1 or 0)
    if self._ruler_align_sig ~= sig then
      self._ruler_align_sig = sig
      print(string.format("[murdoku] 行标/列标已按格子实际位置对齐：%d 个（ruler 容器偏移 %.1f, %.1f）",
        moved, rx, ry))
      -- 顺手把"格子位置 vs 标签位置"打出来 —— 下次若还有偏差，
      -- 这两个数一比就知道差在哪一维，不用再靠截图量像素。
      print(string.format("  核对：cell.1.1=(%.1f, %.1f)  ruler.c.1.x=%.1f（应≈%.1f）  ruler.r.1.y=%.1f（应≈%.1f）",
        cx1 or 0, cy1 or 0, lx1 or 0, (cx1 or 0) - rx, ry1 or 0, (cy1 or 0) - ry))
    end
  end
  return moved
end
-- ★★ 2026-09-28 新增：**列出"与棋盘区域相交、且处于显示中"的控件**。
--
-- 为什么需要：用户反复报「棋盘上有白色/紫色方块」「R3/R4 之间粘连」。
--   而我只能靠截图量像素去猜是哪个控件 —— 规划文件是**多状态并集**，
--   光看数据分不清"屏幕上现在到底有谁"。
--   这条诊断直接把答案打出来：名字 + 实际位置 + 尺寸 + 是否显示。
--
-- 用法：开机自动跑一次（cfg.overlap_diag = false 可关），
--       列出的每一条都值得怀疑；空列表 = 棋盘区域是干净的。
function Adapter:diagnose_overlap()
  -- ⚠️ 必须用**绝对坐标**（`GetUIPos`），不能用 `GetAnchoredPosition`！
  --   后者返回的是"**相对各自父控件**"的偏移 —— 拿它去和棋盘的坐标比，
  --   等于拿两套不同原点的数相减。真机日志因此报过 **100 个控件压在棋盘上**（全是误报），
  --   而玩家屏幕上真正看到的只有 2 条。
  --   ⇒ 规矩：**比坐标之前先确认两者在同一坐标系**。拿不到绝对坐标就明说，不要硬比。
  local board = self:find((self.cfg.cells or {}).parent or "board")
  if board == nil then return 0 end
  local bx, by, bw, bh = nil, nil, nil, nil
  pcall(function() local p = board:GetUIPos() if p then bx, by = p.x, p.y end end)
  pcall(function() bw, bh = board:GetSizeDelta() end)
  if type(bx) ~= "number" or type(bw) ~= "number" then
    print("[murdoku] 相交诊断：**本环境拿不到控件的绝对坐标（GetUIPos 不可用）**，跳过 —— "
      .. "不再用相对坐标硬比（那会报出一堆假阳性）。")
    return 0
  end
  local x0, x1 = bx - bw / 2, bx + bw / 2
  local y0, y1 = by - bh / 2, by + bh / 2
  print(string.format("[murdoku] --- 相交诊断：棋盘 x[%.0f,%.0f] y[%.0f,%.0f] ---", x0, x1, y0, y1))

  local hits = 0
  for i = 1, #MANAGED do
    local parent = self:find(MANAGED[i])
    if parent ~= nil then
      local ok, kids = pcall(function() return parent:GetChildren() end)
      if ok and type(kids) == "table" then
        for k = 1, #kids do
          local ch = kids[k]
          local nm, vis, cx, cy, cw, chh = nil, nil, nil, nil, nil, nil
          pcall(function() nm = tostring(ch.name) end)
          pcall(function() vis = ch.visible end)
          pcall(function() local p = ch:GetUIPos() if p then cx, cy = p.x, p.y end end)
          pcall(function() cw, chh = ch:GetSizeDelta() end)
          if type(cx) == "number" and type(cw) == "number" and vis ~= false then
            -- 相交判定（中心落在棋盘内即算，避免把边缘相接的 ruler 也算进来）
            if cx > x0 and cx < x1 and cy > y0 and cy < y1 then
              hits = hits + 1
              if hits <= 24 then
                print(string.format("  ⚠️ %-22s 父=%-10s 中心(%.0f,%.0f) 尺寸%.0fx%.0f",
                  tostring(nm), MANAGED[i], cx, cy, cw, chh or 0))
              end
            end
          end
        end
      end
    end
  end
  print(string.format("  与棋盘相交且显示中的控件：%d 个%s", hits,
    hits == 0 and "（干净）" or "  ← 这些就是压在棋盘上的"))
  print("[murdoku] --- 相交诊断结束 ---")
  return hits
end

-- ⚠️ 2026-10-05 Round 45：这里原来是「按钮底图上色（运行时）」那一整段循环。
--   它已经**整段搬进**上面的顶层 helper `Adapter:_tray_btn_art`（同一个文件，函数体原样）✓
--   搬走的理由：它用 `names` / `done, miss`（`apply_tray_layout` 的局部变量），
--   而那两个方法必须在 `apply_tray_layout` **外面** ⇒ 只有把这段移出去，
--   才可能让 `apply_tray_layout` 在方法**之前** `end` 掉 ✓
--   ⚠️ 别把它搬回来：搬回来 ⇒ `apply_tray_layout` 又要把方法吞进去（本 bug 复发 ✗）。

-- 尝试由**脚本自己**打开容器的「显示常驻光标」(`showCursor`)。
--
-- 背景：真机上"点不动界面"的头号原因就是**控件的祖先容器没打开 showCursor**
-- （模拟器的派发条件是
--   `for i=t; i; i=i.parent do if i.kind=="container" and i.showCursor then return true end end`
--  —— 见 docs/环境问题-诊断记录.md 的门控 ②）。
-- 正常要在编辑器里手勾，但**如果 Lua 侧允许写这个字段**，脚本就能自己搞定，
-- 少一个最容易漏的手工步骤。
--
-- 真机若不开放该字段，pcall 会失败 → 返回 0 → 上层只记一条提示，不影响运行。
function Adapter:enable_cursor()
  local n = 0
  for i = 1, #CURSOR_CONTAINERS do
    -- ⚠️⚠️ 2026-10-02 **这里原来写的是 `MANAGED[i]`** —— 边界用 CURSOR_CONTAINERS（12 项），
    --   取名字却用 MANAGED（只有 10 项）⇒ i=11/12 时 `MANAGED[i]` 是 **nil**
    --   ⇒ `find(nil)` 返回 nil ⇒ **`home` / `select` 从来没被找到过**。
    --   这就是"补了名单却完全没生效"的真正原因 —— **一行索引写错了数组**，
    --   和"调用时机"无关（我昨晚那个"时机"推断是错的）。
    --   回读那段当时也抄了同一个错，所以两边**一致地缺** `home`/`select` ——
    --   反而让日志看起来"自洽"，更不容易发现。
    --   ⇒ 教训：**同一份名单出现在两处时，索引必须指向同一份**。
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(function() ctrl.showCursor = true end)
      if ok then n = n + 1 end
    end
  end
  -- ★ 回读：把每个受管容器的 showCursor 实际值打出来。
  --   门控②（祖先容器 showCursor=true）是"点不动"的头号原因，
  --   而 `pcall` 会**静默吞掉失败** —— 改了必须回读才算数。
  --
  --   ★★ 2026-10-02 追加 `kind`：派发条件是 **`i.kind == "container" and i.showCursor`**，
  --   `showCursor` 已经全 true 了（真机回读证实），而点击依旧不通 ⇒ **剩下的变量就是 `kind`**。
  --   如果 `root`/`home`/`select` 的 `kind` 不是 `"container"`（比如是别的名字），
  --   门控②**永远不满足** ⇒ 点不动 —— 而且能解释探针那句"所有容器都不支持光标事件"。
  local parts = {}
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local sc, kd = "?", "?"
      pcall(function() sc = tostring(ctrl.showCursor) end)
      -- `kind` 可能叫别的名字，多试几个写法，读不到就留 "?"
      pcall(function() kd = tostring(ctrl.kind) end)
      if kd == "nil" then pcall(function() kd = tostring(ctrl.Kind) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.type) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.controlType) end) end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
      -- （类型探测已撤：它每 20 帧打一次，刷屏；结论已记录在 enable_cursor 上方）
    else
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  -- 只在内容变化时打（`enable_cursor` 现在每 20 帧重试一次，否则会刷屏）
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  return n
end

-- 把「脚本能看到的客户端控件名字」打出来。
--
-- 用途：真机上最费时间的排查就是「脚本说控件未找到，可你明明建了」——
-- 到底是名字差一个字符、层级放错、还是容器没激活，光看错误信息猜不出来。
-- 这里直接把整棵树的名字按层级列出来，一对照就知道差在哪。
--
-- 只在诊断时调用（默认不跑），输出走 print（普通级日志）。
--
-- `quiet = true` 时**只数不打印**，用来回答"树到底起来了没有"。
-- 为什么要这个：真机上 `OnInit` 阶段控件树**本来就是空的**（约 0.5 秒后才出现），
-- 这不是故障。所以探针必须先量一下再决定"要不要现在就把话说完" ——
-- 树是空的且还有重试机会 → 说一句"稍后重试"就够了，别把三条病因砸给玩家看。
function Adapter:dump_names(max_depth, max_items, quiet)
  max_depth = max_depth or 6
  max_items = max_items or 400
  if game == nil or game.GetClientUIRoots == nil then
    if not quiet then self:err("dump_names：拿不到 game.GetClientUIRoots") end
    return 0
  end
  local ok, roots = pcall(game.GetClientUIRoots)
  if not ok or type(roots) ~= "table" then
    if not quiet then self:err("dump_names：GetClientUIRoots 失败") end
    return 0
  end
  local n = 0
  local lines = {}
  local function walk(c, depth)
    if c == nil or depth > max_depth or n >= max_items then return end
    local name, kind = "?", "?"
    pcall(function() name = tostring(c.name) end)
    pcall(function() kind = tostring(c.kind) end)
    local vis, act, pf = "?", "?", nil
    pcall(function() vis = tostring(c.visible) end)
    pcall(function() act = tostring(c.active) end)
    -- 控件模板索引（只读）。**专门为「另存为模板」那条路加的**：
    -- 真机上"读得到的索引"和"能实例化的索引"不是一回事（基础模板读得到但返回 nil），
    -- 所以排查时必须能一眼看到每个控件的索引，尤其是 tpl.cell 和 cell.1.1 各是多少。
    pcall(function() pf = c.prefabIndex end)
    n = n + 1
    if not quiet then
      local pfstr = ""
      if type(pf) == "number" and pf > 0 then pfstr = " tpl=" .. tostring(pf) end
      lines[#lines + 1] = string.rep("  ", depth) .. "- " .. name
        .. "  [" .. kind .. " vis=" .. vis .. " act=" .. act .. pfstr .. "]"
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  for i = 1, #roots do walk(roots[i], 0) end

  if not quiet and print then
    print("[murdoku] ===== 客户端控件树（脚本能看到的，共 " .. n .. " 个节点）=====")
    for i = 1, #lines do print("[murdoku] " .. lines[i]) end
    print("[murdoku] ===== 控件树结束 =====")
  end
  return n
end

-- 只数不打印：判断"控件树起来了没有"，用于决定诊断话术的轻重。
function Adapter:count_names(max_depth, max_items)
  return self:dump_names(max_depth or 6, max_items or 400, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- 格子**模板候选**体检（配合「另存为模板」那条路）
--
-- 为什么单独报这个：`cell.1.1` 自己的 `prefabIndex` 是「预设按钮」的**基础模板**
-- （读得到，但拿去 InstantiateClientUIControl 会**静默返回 nil**）。
-- 所以必须有一个"**从另存出来的模板新建的**"控件，它的索引才是可实例化的。
--
-- 脚本本身**不关心你是怎么做出 tpl.cell 的** —— 它只看「那个控件的 prefabIndex
-- 能不能真的造出一个格子」。但「能不能造」只有**缺格子时**才会被试到，
-- 而那时日志里已经混了一堆别的东西。这里提前把候选和索引列出来，
-- 让你**试玩之前**就能确认配对了没有。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:diagnose_template()
  local log = print
  if log == nil then return false end
  local g = self.cfg.cells
  if g == nil then return false end

  local base_id = g.probe or "cell.1.1"
  -- 与 _cells_prefabs 同样的规矩：基准**只从参照格子取**。
  -- 纯模板模式下参照格子不存在 → base_idx 保持 nil → `tpl.cell` 会被正确算成"可用候选"。
  --
  -- ⚠️ 但要注意**时机**：本函数跑在 `ensure_cells` **之后**，那时纯模板模式下的
  --    `cell.1.1` 已经被脚本造出来了 —— 现场查一定查得到。所以"纯模板模式"这个事实
  --    要读 `ensure_cells` **当时记下**的 `self.cells_probe_missing`，不能现场重推。
  local base_idx = nil
  local base_ctrl = self:find(base_id)
  if base_ctrl ~= nil then pcall(function() base_idx = base_ctrl.prefabIndex end) end
  if self.cells_probe_missing == true then
    log("[murdoku]   （**纯模板模式**：生成前没有参照格子 " .. base_id
      .. "，格子全部由脚本按模板生成 —— 这是一种合法且推荐的配置）")
  elseif base_idx == nil then
    log("[murdoku]   （没有参照格子 " .. base_id .. "，也读不到它的模板索引）")
  end

  local names = g.prefab_from or { base_id, "tpl.cell", "cell.tpl", "cell.prefab" }
  local found, usable = {}, 0
  log("[murdoku] --- 格子模板候选（用来批量生成其余格子）---")
  if type(g.prefab) == "number" and g.prefab > 0 then
    log("[murdoku]   cfg.cells.prefab = " .. tostring(g.prefab)
      .. "   ← **显式配置**，脚本会最先试它")
  else
    log("[murdoku]   cfg.cells.prefab = (未配置)")
  end
  for i = 1, #names do
    local id = tostring(names[i])
    local c = self:find(id)
    if c == nil then
      log("[murdoku]   " .. id .. "  —— **不存在**")
    else
      local p = nil
      pcall(function() p = c.prefabIndex end)
      -- ★ 两个数字含义不同，都要打出来（用户 2026-09-26 纠正过：
      --   `prefabIndex` 是**控件自身**的模板索引；模板引用控件引用的是
      --   `referencedPrefabIndex`。只打一个会让人把"控件自身索引"误当成"模板索引"。）
      local rf = self:_ref_index_of(c)
      local ref_txt = (rf ~= nil) and ("  ref=" .. tostring(rf) .. "（引用的模板）") or ""
      found[#found + 1] = { id = id, idx = p }
      local tag
      if id == base_id then
        tag = "   ← 参照格子自己"
      elseif type(p) == "number" and p > 0 and p == base_idx then
        tag = "   ← 与 " .. base_id .. " 同一个索引"
      elseif type(p) == "number" and p > 0 then
        tag = "   ← 与 " .. base_id .. " **不同**"
        if rf == nil then tag = tag .. "：可能就是可用的那个" end
        usable = usable + 1
      else
        tag = "   ← 读不到 prefabIndex"
      end
      log("[murdoku]   " .. id .. "  prefabIndex=" .. tostring(p) .. ref_txt .. tag)
    end
  end

  -- ★★ 结论必须报**实际结果**，不能靠"索引看起来不同"来猜。
  --
  -- 真机 16:07 就是这么被误导的：生成**明明成功了**
  -- （`格子模板索引 1073741876 可用；棋盘格子：25 / 25 存在`），
  -- 可这一段却打出「**没有可用的自定义模板** —— 缺格子时生成会失败」。
  -- 原因：`cell.1.1` 现在自己就带着模板索引（它是「模板引用控件」），
  -- 于是 `base_idx` 等于它自己 → "与 base 不同"这个启发式恒为假 → usable=0。
  --
  -- 所以现在：**ensure_cells 跑过就以它的实测结果为准**，启发式只当备注。
  -- ★ 把"生成前就存在的格子"点出来 —— 这是最容易被看错的一件事。
  do
    local pre = self.cells_preexisting
    if pre ~= nil then
      local ids = {}
      for id in pairs(pre) do ids[#ids + 1] = id end
      table.sort(ids)
      if #ids > 0 then
        log("[murdoku]   ℹ️ 生成前**已存在**的格子：" .. table.concat(ids, " "))
        log("[murdoku]     这些是**编辑器里的控件**，脚本只把它们摆正、**不会覆盖** —— "
          .. "所以它们不是模板生成的副本。")
        if pre[base_id] and base_idx ~= nil and g.prefab ~= nil and base_idx == g.prefab then
          log("[murdoku]     ⚠️ **" .. base_id .. " 的索引 == cfg.cells.prefab** —— "
            .. "它**就是那个模板引用控件本身**，不是生成的格子！")
          log("[murdoku]        它的外观由它自己决定，**可能和模板里的格子不一样**"
            .. "（截图里常见表现：只有它看着不对 / 缺一块）。")
          log("[murdoku]        想要「全 25 格都是模板副本」：把它**改名成 `tpl.cell`**（或删掉），"
            .. "让脚本把 " .. base_id .. " 也一起生成。")
        end
      end
    end
  end

  if self.cells_ok ~= nil then
    if self.cells_ok then
      log("[murdoku] 结论（实测）：**生成成功了** —— 用模板索引 "
        .. tostring(self.cells_index) .. " 建了 " .. tostring(self.cells_made)
        .. " 个格子，棋盘 " .. tostring(self.cells_total) .. " 格齐全")
    else
      log("[murdoku] 结论（实测）：**生成失败** —— 试过的索引都不可实例化（见上面的错误行）")
    end
    log("[murdoku] --- 体检结束（模板）---")
    return self.cells_ok
  end

  -- 没跑过 ensure_cells（例如缺格子数为 0）时才用启发式
  if usable > 0 or (type(g.prefab) == "number" and g.prefab > 0) then
    log("[murdoku] 结论（推测）：有**可能是可用模板**的候选 —— "
      .. "缺格子时脚本会挨个**真试着造**，造得出来才用它")
    log("[murdoku] --- 体检结束（模板）---")
    return true
  end

  log("[murdoku] 结论：**没有可用的自定义模板** —— "
    .. "缺格子时生成会失败（日志会打「全部实例化失败」）")
  log("[murdoku]   原因：" .. base_id .. " 自己的 prefabIndex 是「预设按钮」的**基础模板**，"
    .. "读得到但不能实例化；而右键【另存为模板】存出来的索引**也调不动**。")
  log("[murdoku] ⚠️ 正确入口是官方文档里那个（右键另存为模板**不是**它）：")
  log("[murdoku]   ① 界面控件组管理 → 界面控件组库 → **客户端控件模板** → 【添加客户端控件】")
  log("[murdoku]      → 加一个「预设按钮」，配好底图与子控件 → **存为模板**")
  log("[murdoku]   ② 那个模板的**控件模板索引 ID** 才是客户端脚本能调用的")
  log("[murdoku]      （点它就能看到 ID，把数字填进 cfg.cells.prefab 也行）")
  log("[murdoku]   ③ 也可尝试把它放进容器画布后改名 tpl.cell（脚本会自己读它的索引）")
  log("[murdoku] 依据：官方《客户端控件和客户端脚本的定义》——")
  log("[murdoku]   「除客户端控件容器画布中的客户端控件以及客户端控件模板中的控件外，"
    .. "其他控件均为服务器控件，**服务器控件的模板索引无法被客户端脚本调用**」")
  log("[murdoku] --- 体检结束（模板）---")
  return false
end

-- ════════════════════════════════════════════════════════════════════════
-- 参照格子体检（`cell.1.1`）
--
-- 为什么需要：一个格子要能"看得见 + 点得动 + 能当模板"，同时依赖四五项设置：
--   控件类型（必须预设按钮/光标检测区域）、可被光标射线检测、子控件 face/note/x、
--   face 挂到「默认」状态节点、图片类型=拉伸、祖先容器开了「显示常驻光标」。
--   这些**在日志里全都没有痕迹** —— 出问题时只能靠肉眼一个个猜。
--   2026-09-26 的真机日志就是这样：只知道"缺 24 个格子"，不知道手上这个配好没有。
--
-- 这里把上面每一项读出来，逐条给出 ✅/❌ 和"怎么修"，一次性讲完。
-- 每个会话打一次，不刷屏。
-- ════════════════════════════════════════════════════════════════════════

function Adapter:diagnose_cell(id)
  id = id or (self.cfg.cells and self.cfg.cells.probe) or "cell.1.1"
  -- 走 print（**正常级**日志）而不是 printerr：
  -- 这是一份**报告**，不是故障。走 stderr 有两个坏处：
  --   ① 模拟器/排查脚本会把"日志里有没有报错"当成健康判据 → 一份全是 ✅ 的体检
  --      也会被算成错误（本次就是这样挂了 8b/9 两步回归）；
  --   ② 你在日志窗口的「报错」分类里会看到一堆其实是 ✅ 的行。
  local log = print
  if log == nil then return false end

  local c = self:find(id)
  if c == nil then
    -- ⚠️ 纯模板模式（board 下只留一个 `tpl.cell` 模板引用控件、不建任何真格子）下，
    --    参照格子**本来就不存在** —— 这时候报"找不到控件"就是误报（会把人吓一跳）。
    --    改成明确说"这是合法配置，体检跳过"，把判断权交给下面的「模板候选」实测结论。
    local g = self.cfg.cells or {}
    if id == (g.probe or "cell.1.1") and (g.prefab ~= nil or self:find("tpl.cell") ~= nil) then
      log("[murdoku] 格子体检：没有 " .. id .. " —— **纯模板模式**（board 下只放模板引用控件）")
      log("[murdoku]   这是合法配置：格子全部由脚本按模板生成，编辑器里一个真格子都不用建。")
      log("[murdoku]   子控件 face/note/x 与状态节点引用都在**模板里**，不在这里，所以本段体检跳过。")
      log("[murdoku]   → 有没有配对，看紧接着的「格子模板候选」那段的**实测结论**。")
      log("[murdoku] ===== 体检结束 =====")
      return true
    end
    log("[murdoku] 格子体检 " .. id .. "：**找不到这个控件**"
      .. "（名字要一字不差；必须在客户端控件容器里）")
    return false
  end

  local lines, bad = {}, 0
  local function say(s) lines[#lines + 1] = s end
  local function mark(okflag, text, fix)
    if okflag then
      say("  ✅ " .. text)
    else
      bad = bad + 1
      say("  ❌ " .. text .. (fix and ("   → " .. fix) or ""))
    end
    return okflag
  end

  -- ① 类型：只有「预设按钮 / 光标检测区域」才有 AddCursorEventListener
  --    注意：kind 在真机/模拟器上可能读不到（模拟器返回 nil），所以以
  --    **接口是否存在**为准，类型名只作参考 —— 否则会出现"类型 = nil ✅"
  --    这种自相矛盾的行。
  local kind = nil
  pcall(function() kind = c.kind end)
  local kind_s = (kind ~= nil) and tostring(kind) or "读不到"
  if c.AddCursorEventListener ~= nil then
    say("  ✅ 控件类型 = " .. kind_s .. "，且**支持光标事件**（AddCursorEventListener 存在）")
  else
    mark(false, "控件类型 = " .. kind_s .. "，**不支持光标事件**",
      "改成【预设按钮】或【光标检测区域】；用容器/文本框永远点不动")
  end

  -- ② 射线检测 + 可交互
  local ray, ia = nil, nil
  pcall(function() ray = c.raycastTarget end)
  pcall(function() ia  = c.interactable end)
  if ray ~= nil then
    mark(ray == true, "可被光标射线检测 raycastTarget = " .. tostring(ray),
      "在【基础】里打开它，否则点击到不了脚本")
  else
    say("  ⚠️ 读不到 raycastTarget（该实现不暴露这个字段）—— 请到编辑器里确认已打开")
  end
  if ia ~= nil and ia ~= true then
    mark(false, "可交互 interactable = false",
      "脚本会按格子是否可站人切它；常关会让格子一直是灰的")
  end

  -- ③ 模板索引（决定能不能复制出其余格子）
  local pf = nil
  pcall(function() pf = c.prefabIndex end)
  if type(pf) == "number" and pf > 0 then
    say("  ℹ️ 模板索引 prefabIndex = " .. tostring(pf)
      .. "（**能不能实例化以实际生成结果为准** —— 见下面「格子模板候选」那段的实测结论。"
      .. "内置基础模板（例如「预设按钮」的 1073741848）会静默返回 nil；"
      .. "用「**模板引用控件**」引用自定义模板后，这里就会变成可用的模板索引）")
  end

  -- ④ 子控件（脚本按名字找，**支持装在中间容器里的方案 A**）
  --
  -- ⚠️ 这里曾经写死 `c:GetChild(name)`（只查直接子控件），于是用户采用
  --    **方案 A**（子控件装进 `content` 容器）时，体检会**误报「不存在」** ——
  --    而运行时的 `Adapter:sub` 早就支持穿透容器了。**两处查找方式必须一致**，
  --    否则就会变成"体检说没有、其实能用"或反过来，白折腾。
  local via = nil
  do
    local direct = nil
    pcall(function() direct = c:GetChild("face") end)
    if direct == nil then
      for _, rn in ipairs({ "content", "root", "body" }) do
        local mid = nil
        pcall(function() mid = c:GetChild(rn) end)
        if mid ~= nil then via = rn break end
      end
    end
  end
  if via ~= nil then
    say("  ℹ️ 子控件装在中间容器 `" .. via .. "` 里（方案 A）—— 按路径查找")
  end

  local want_children = { { "face", true }, { "note", false }, { "x", false } }
  for i = 1, #want_children do
    local name = want_children[i][1]
    local sub = self:sub(id, name)      -- ★ 与运行时同一套查找
    if sub == nil then
      mark(false, "子控件 " .. name .. " —— 不存在",
        (name == "face" and "没它就换不了格面图（放置角色时看不到人）"
          or "没它这一格的" .. (name == "note" and "铅笔笔记" or "X 标记") .. "显示不出来")
        .. (via ~= nil and "" or "（若你把它装进了中间容器，容器名要在 content/root/body 之一）"))
    else
      local vis = nil
      pcall(function() vis = sub.visible end)
      local extra = ""
      -- face 和 x 都是**图片**控件，把图片来源/类型都读出来。
      -- 为什么连 x 也要读：能立刻发现"X 根本没配图"（imageId 为 nil 就永远不显示），
      -- 也能看到「基础 / 拉伸」实际是哪一个。
      if name == "face" or name == "x" then
        local it, iid = nil, nil
        pcall(function() it = sub.imageType end)
        pcall(function() iid = sub.imageId end)
        extra = "  imageType=" .. tostring(it) .. " imageId=" .. tostring(iid)
        if iid == nil then
          bad = bad + 1
          extra = extra .. "   ← **图片来源没配**！去「图片设置 → 图片源=静态引用 → 引用素材资产」选一张 "
            .. (name == "face" and "格面底图（带圆角/边框的建议用九宫格素材 + 图片类型=拉伸）"
                          or "X 图标（功能图标类即可）")
        end
        -- ⚠️ 这里**只提示、不报错**。
        --
        -- 2026-09-26 真机实验（用户做的）：**基础 也会铺满图片控件本身** ——
        -- 所以"格面不是拉伸"**不会**导致棋盘花掉，格面照样跟着格子缩放。
        --
        -- 「基础 / 拉伸」的真正区别只在**素材是九宫格/三宫格**时才显现：
        --   · 素材图片属性 = 普通   → 基础 和 拉伸 表现**完全一样**（角都形变）
        --   · 素材图片属性 = 三宫格 → 拉伸 保住那一对边，基础 会压扁
        --   · 素材图片属性 = 九宫格 → 拉伸 保住四角，基础 会压扁圆角
        -- 依据：官方《图片控件》那张「**图片属性**」表（注意：它属于**素材**，
        -- 不是「图片类型」的选项）。
        --
        -- 所以这里最多给一句 info，绝不记成 ❌ —— 否则就是在制造误报。
        if name == "face" and it ~= nil then
          local s = tostring(it)
          if not s:find("Stretch") then
            say("  ℹ️ 格面用的是【基础】：**也会铺满格子**，不影响棋盘。"
              .. "只有当你给 face 换了**九宫格/三宫格**素材、想让四角不被压扁时，"
              .. "才需要把图片类型改成【拉伸】")
          end
        end
      end
      say("  ✅ 子控件 " .. name .. " 存在（visible=" .. tostring(vis) .. "）" .. extra)
    end
  end

  -- ⑤ 祖先容器有没有开「显示常驻光标」（门控②）。脚本会自己开，这里只做复核。
  local cur, cursor = c, false
  for _ = 1, 12 do
    if cur == nil then break end
    local sc = nil
    pcall(function() sc = cur.showCursor end)
    if sc == true then cursor = true end
    local p
    pcall(function() p = cur.parent end)
    cur = p
  end
  mark(cursor, "祖先容器已开「显示常驻光标」（门控②）",
    "日志里没看到『已由脚本打开 N 个容器』就得在编辑器里手动勾")

  log("[murdoku] ===== 格子体检：" .. id .. " =====")
  for i = 1, #lines do log("[murdoku]" .. lines[i]) end
  if bad == 0 then
    log("[murdoku] 结论：**这一格配好了**（底图 + face/note/x + 状态节点 + 射线 + 门控②都过）。")
    log("[murdoku]   → 接下来按第 5 节做「客户端控件模板」，再用「**模板引用控件**」引用它，")
    log("[murdoku]     把 referencedPrefabIndex 填进 cfg.cells.prefab（**不是** prefabIndex）就行。")
    log("[murdoku]   → 若这一格是**脚本生成**的副本，说明模板已通，不用再动编辑器。")
  else
    log("[murdoku] 结论：还有 " .. bad .. " 项要处理（见上面 ❌ 行）")
  end
  log("[murdoku] ===== 体检结束 =====")
  return bad == 0
end

-- ★★★★★ 2026-10-05 **销毁/回收一个控件时，把它名下「所有规划节点」的事件一起扔掉。**
--
--   为什么不能只按 id 清一笔：事件表现在按**规划节点**记（`id \1 父容器 \1 序号`），
--   一个 id 可能挂着好几个节点（`action.back` 就挂着 2 个）。
--   控件真的没了 ⇒ 这几个节点的事件**全都作废**：只清掉其中一个会留下**孤儿条目**
--   （那个键再也不会被写、也再也不会被读，纯泄漏）。
--   ⚠️ 前缀匹配是安全的：分隔符 `\1` 不可能出现在控件 id 里（同一条约定见
--      ui_controller 的 `drop_props_of`），所以 `id .. "\1"` 只会命中**这个 id** 的节点键。
--   ★★★★★ 2026-10-05 **B2 追加：`event_claim` 也要一起清**（同一件事，不能只做一半）。
--      `event_claim[id]` 指着"认领这个控件的那把节点键" —— 控件销毁重建后，那把键**已经
--      不存在**（上面刚被清掉）⇒ 不清就会**认领到旧节点** ✗：
--      `live_event()` 读 `self.events[旧键]` = nil ⇒ 静默退回 `node.event`，
--      看起来"还能点"，实际派发的可能不是这颗新控件的语义（而且新节点再也认领不上 ✗）。
function Adapter:forget_events_of(id)
  local pre = tostring(id) .. "\1"
  local stale = nil
  for k in pairs(self.events) do
    if type(k) == "string" and k:sub(1, #pre) == pre then
      stale = stale or {}
      stale[#stale + 1] = k
    end
  end
  if stale ~= nil then
    for i = 1, #stale do self.events[stale[i]] = nil end
  end
  self.event_claim[id] = nil   -- ★ B2：控件没了 ⇒ 认领关系作废（新控件要能重新认领）
  self.event_latest[id] = nil
  self.handlers[id] = nil
end

function Adapter:destroy_control(id)
  local ctrl = self.controls[id]

  -- ★ 2026-09-26 修：以前这里对**编辑器里手摆的控件**也调 DestroyClientUIControl，
  --   于是弹窗一关，modal / modal.suspect.* 就被**真销毁**了 ——
  --   下次再要显示指认面板时，脚本按名字怎么也找不到，面板永远出不来。
  --   只有「脚本用 InstantiateClientUIControl 现生成的」控件才允许销毁；
  --   编辑器手摆的只能藏起来。
  if self.instantiated and self.instantiated[id] then
    if ctrl and game and game.DestroyClientUIControl then
      pcall(function() game.DestroyClientUIControl(ctrl) end)
    end
    self.instantiated[id] = nil
    self.bound[id] = nil
    self.controls[id] = nil
    self:forget_events_of(id)
    -- ★ 控件真的没了 ⇒ 名字缓存整代作废（"不在"的判定和"在"的句柄都可能已经过期）
    self:invalidate_lookups("destroy:" .. tostring(id))
    return
  end

  if ctrl ~= nil then
    if ctrl.SetVisible then
      pcall(function() ctrl:SetVisible(false) end)
    elseif ctrl.SetActive then
      pcall(function() ctrl:SetActive(false) end)
    end
  end
  -- 只清缓存，让下次 create_control 重新 find；控件本身留着（监听也留着）
  self:drop_lookup(id)
  self:forget_events_of(id)
end

----------------------------------------------------------------------------
-- 属性同步
----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- 素材调色板：解决「一个模板怎么给不同格子配不同图」
--
-- 问题本质：`SetImage(imageSource, imageId)` 要的是**整数 imageId**，
--   而 `imageId` / `imageSource` 字段都是**只读**（官方 API），
--   所以脚本没法把"图片名字"直接变成 ID；你也不可能把几十个数字抄进代码。
--
-- 解法：在编辑器里放一个**调色板容器**（默认叫 `assets`），
--   里面每个想要的图各放一个**图片控件**，控件名就是引用键
--   （例如 `room.kitchen`、`floor.wood`、`portrait.A`），图在编辑器里配。
--   脚本运行时**读它们的 `imageSource` + `imageId`**，之后按名字套到任意格子：
--
--     set_property("cell.2.3", "image", "room.kitchen")
--
-- 好处：一个模板 + 一张调色板 = 任意多种外观，**不用为每种外观做模板**；
--       换图只在编辑器里改，**代码一个字都不用动**；不用手抄任何 ID。
--
-- 调色板容器会被 `hide_unlisted` 自动隐藏（它不在关卡布局里），放哪都行。
----------------------------------------------------------------------------
function Adapter:read_palette()
  if self._palette ~= nil then return self._palette end
  local map, names = {}, {}
  local a = self.cfg.assets or {}
  local root = self:find(a.palette or "assets")
  if root ~= nil then
    local kids = nil
    pcall(function() kids = root:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, #kids do
        local k = kids[i]
        local nm, src, id = nil, nil, nil
        pcall(function() nm = tostring(k.name) end)
        pcall(function() src = k.imageSource end)
        pcall(function() id = k.imageId end)
        if nm ~= nil and nm ~= "" and type(id) == "number" then
          map[nm] = { source = src, id = id }
          names[#names + 1] = nm
        end
      end
    end
  end
  self._palette = map
  self._palette_names = names
  return map
end

-- 把「素材键」解析成 { source, id }。
-- value 可以是：调色板里的名字（字符串）、或直接的整数 ID。
function Adapter:resolve_asset(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n ~= nil then return { source = nil, id = n } end   -- 直接给数字：来源由调用方沿用
  local map = self:read_palette()
  local hit = map[tostring(value)]
  if hit ~= nil then return hit end
  self:warn_once("asset:missing:" .. tostring(value),
    "调色板里没有素材「" .. tostring(value) .. "」。\n"
    .. "       建法：在编辑器里放一个容器（默认名 `assets`），每个素材放一个**图片控件**，\n"
    .. "       控件名就是引用键（例如 `room.kitchen`），图在编辑器里配好。\n"
    .. "       当前调色板：" .. ((self._palette_names and #self._palette_names > 0)
      and table.concat(self._palette_names, " ") or "（空 —— 找不到 `assets` 容器？）"))
  return nil
end

-- 每格四边的墙 / 门：固定 4 个子控件，按数据开关。
--
-- 为什么这样做：`cd.walls` / `cd.doors` 每格都不同（`{up,down,left,right}` 布尔表），
--   但**一个模板的副本结构是一样的** —— 所以做法是在模板里放 4 个固定的
--   墙位子控件（`wall.up` / `wall.down` / `wall.left` / `wall.right`）
--   与 4 个门位（`door.*`），运行时按数据 `SetVisible(true/false)`。
--   官方依据：`SetVisible(visible)`「仅设置可见性，不改变激活状态」。
-- ★★ 图层顺序：**必须显式规划**，不能听天由命。
--
-- 用户 2026-09-27 提醒：图片/文本之间的层级**由模板里的位置（同级次序）决定**，
-- **不看创建或生成顺序**，而且**图层会互相覆盖**。
--
-- 官方给了控制手段（客户端控件基类）：
--   · `GetSiblingIndex()` → 当前同级索引
--   · `SetSiblingIndex(i)` → 「数值越大通常越靠后、**显示越靠上**」
--   · `SetAsFirstSibling()` / `SetAsLastSibling()`
--
-- 所以这里按 `cfg.cells.layer_order`（**从下到上**）把每个格子的子控件重排一遍 ——
-- 于是最终层叠**不依赖编辑器里的摆放次序**（那个只是默认值）。
--
-- 实现技巧：**倒序**逐个 `SetAsFirstSibling()`。
--   先处理"最上层"的那个 → 它到 0；再处理下一个 → 它到 0、前一个退到 1……
--   全部处理完，列表里**最后一个**就在 0（最底），第一个在最高位 —— 正好是我们要的顺序。
-- ★★★★★ 2026-10-02 **按屏幕排图层**（真机"选关点不动"的根因，用户指出的方向）。
--
--   用户的观察拼出了完整答案：
--     · 「那个全屏按钮还在」            => 屏幕上有个**全屏的东西**在吃点击
--     · 「界面内的按钮并没有被恢复回来」 => 它盖住了那些按钮
--   而 `home` / `select` **都是 1600x900、都在 `root` 下** ——
--   **谁在兄弟列表里靠后，谁就显示在上面**（官方 `SetSiblingIndex`「数值越大越靠上」）。
--
--   => 主页能点，是因为 `home` 恰好在上；
--     选关不能点，是因为 **`select` 显示时 `home` 仍然压在它上面** ——
--     那层 1600x900 的容器把选关页的点击全吃了。
--     （我前几轮一直盯着 `select`，方向错了；**凶手是另一个容器**。）
--
--   => 修法：**不用 visible 开关**（真机证明"由藏变显"会让射线出问题），
--     改成**每帧把当前屏幕的容器排到最上、另一个排到最下**。
--     幂等、便宜、只动顺序。
--
--   ★ 这正是本项目反复吃亏的那一类错：**图层顺序**。
--     （格子子控件排过 `enforce_layers`；这次轮到屏幕容器。）
-- ★★★★★ 2026-10-02 **强制打开「可被光标射线检测」（`raycastTarget`）—— 真机"点不动"的正解**。
--
--   官方文档（docs/api-cache/mhd4fxr5v6la.txt）：
--     「可被光标射线检测：可以检测到光标在控件范围内的悬浮和点击行为」
--   项目自己的排查清单（docs/最小骨架控件清单.md:151 / 真机-cell.1.1-逐步指南.md:67）：
--     「**可被光标射线检测**（raycastTarget）—— 脚本靠 AddCursorEventListener 收点击；**关掉就点不动**」
--     「**界面看得见，但点哪儿都没反应**」= 没开这个开关
--     「点不动卡片 → 选不了人」（本次搭建要求.md:416）
--
--   而官方 API：**预设按钮只有三个自有字段 `interactable` / `clickAudioId` / `raycastTarget`**
--   —— `clickAudioId` 就是"点击音效" ⇒ **"处处有音效但什么也没发生" = 点到了按钮、但它 `raycastTarget=false`**。
--
--   我之前的错误：只对 **容器节点** 试过这个字段（容器没有它 ⇒ 读到 nil）
--   ⇒ 误以为"这个字段在引擎里不存在" ⇒ **从来没对按钮读过/写过它**。
--
--   ⇒ 这里**遍历整棵控件树**，对每个控件尝试写 `raycastTarget = true`，并统计/回读。
--     （只对"支持这个字段的控件"生效，别的控件 pcall 静默失败，无害。）
--
-- ════════════════════════════════════════════════════════════════════════
-- ★★★★★ 2026-10-05 **这一趟不能再"每 20 帧永远重扫"**（这一轮每帧成本第 (3) 条）。
--
--   真机形状：`Murdoku.on_update`（`main.lua` L666）原来每 20 帧**无条件**调一次
--   `enable_raycast()`，而它每次都**从 root 起整棵树 walk**（深度 ≤ 6、每层 ≤ 200 个子控件）。
--   实测（`tests/grid_cost.lua` 口径 [E]，300 帧）：调用 **15 次**、walk 掉
--   **7020 次 `GetChildren`** = **23.4 个节点/帧** —— 而它要做的事
--   （把 `raycastTarget` 打开）**是幂等的**：第一趟扫完就已经全打开了，
--   后面 14 趟是纯白跑。用户那句"没必要留着不必要的负载浪费"说的就是这一笔。
--
--   ⚠️ 但**不能"成功一次就永远不扫"**：本项目有明确的「**控件晚一步才进树**」案例 ——
--      `home` / `select` 这两个屏幕容器是**第一次渲染时**才 `create_control` 的
--      （见 `main.lua` 门控②那段注释：`find("home")` 开局返回 nil ⇒ 永远开不上）。
--      早停会让**后出现的屏幕控件永远开不上 `raycastTarget`**
--      ⇒ 那正是"界面看得见、点哪儿都没反应"的老病。所以三条一起用，各管一件事：
--
--     ① **收敛即停**（省掉绝大多数趟数）：
--        `seen > 0 且 set == 0` = "树里有带这个字段的控件，**而且它们全都已经是 true**"
--        ⇒ 连续 `RAY_IDLE_STOP` 趟都是这样 ⇒ 收工，之后**一次树都不走**。
--        ⚠️ `seen == 0`（树里一个带该字段的控件都没有）**不算收敛** ——
--           那更可能是"树还没就绪"，要继续试（这正是"控件晚一步才进树"要救的情形）。
--     ② **硬上限**（防止"永远试不成功"变成新的每帧负载）：
--        每一代最多 `RAY_MAX_SCANS` 趟（25 趟 × 20 帧 ≈ 8.3 秒），到顶就停，
--        **并且只报一次**（真机上 `seen == 0` 是真问题：按钮没这个字段就点不动）。
--     ③ **换屏 / 换关重新武装**（`Adapter:rearm_raycast`）：那一代会长出新控件
--        （`home` / `select` 以及各屏自己的子控件），必须给它一次机会。
--
--   ⚠️ **不把"重新武装"挂进 `invalidate_lookups`**：那个函数还被 `create_control` /
--      `destroy_control` **每个控件各调一次**（进关时几十次）⇒ 挂在那里等于
--      "每建一个控件就重扫一趟"，白跑比改之前还多。只有 **screen / level 换代**
--      （`ui_controller.render` 里那个块）才重新武装。
--
--   ⇒ 实测收益见 `tests/grid_cost.lua` 口径 [E]：300 帧里 `enable_raycast` 走掉的
--     `GetChildren` 从 **7020** 降到**个位数×一趟**，且**不再随帧数增长**。
-- ════════════════════════════════════════════════════════════════════════
local RAY_IDLE_STOP = 3      -- 连续几趟"树里全都开好了"就收工
local RAY_MAX_SCANS = 25     -- 每一代最多扫几趟（25 × 20 帧 ≈ 8.3 秒）

-- ②/③ 的那一半：换屏 / 换关时**重新武装**（不重置累计值，只重置本代的额度）。
--   为什么需要它：新屏幕的控件是**后来才建**的，早停会让它们开不上 raycastTarget。
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end    -- 本来就没扫过 ⇒ 没什么可武装的
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end

-- ★★★★★ 2026-10-05 **单个控件的 `raycastTarget` 就地打开（O(1)）**。
--
--   给谁用：**引擎在运行时克隆出来的控件** —— 最典型的就是网格视窗的列表项
--   （`RefreshItems` 里由引擎实例化的线索卡）。
--
--   为什么必须补这一条（**这是有意的补偿，不是顺手加的**）：
--     `enable_raycast` 原来**每 20 帧整树重扫**，顺带就把"引擎后来克隆出来的列表项"
--     也扫进去了；收敛/放弃之后不再重扫 ⇒ 那些**晚到**的按钮**没人给它们开这个字段**
--     ⇒ 「卡片点不动」。所以在这一边补上，而且比原来那趟重扫**更强**：
--       · 时机：**绑定的那一刻就开**（原来是"最多晚 20 帧"）；
--       · 成本：**1 次字段读写**（原来是一趟 ≈ 470 个 `GetChildren`）。
--   ⚠️ 三条返回值都有意义：`false` = 这个控件没有该字段（**容器**就是这种，
--      真机上读容器拿到的是 nil）—— 那不是失败，只是"不适用"。
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local before = nil
  pcall(function() before = c.raycastTarget end)
  if before == nil then return false end          -- 没有该字段 ⇒ 不适用
  if before == true then return true end          -- 已经是开的 ⇒ 幂等，不重复写
  local ok = pcall(function() c.raycastTarget = true end)
  return ok == true
end

function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
  -- ★① 已经收敛 / 已经放弃 ⇒ **一次树都不走**。这一行就是第 (3) 条的全部收益。
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local function walk(c, depth)
    if c == nil or depth > 6 then return end
    local nm = "?"
    pcall(function() nm = tostring(c.name) end)
    -- 先读原值（判断它是不是"有 raycastTarget 的控件"）
    local before = nil
    pcall(function() before = c.raycastTarget end)
    if before ~= nil then
      seen = seen + 1
      if before ~= true then
        local ok = pcall(function() c.raycastTarget = true end)
        if ok then
          set = set + 1
          if #samples < 6 then samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true" end
        end
      end
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)
    if type(kids) == "table" then
      for i = 1, math.min(#kids, 200) do walk(kids[i], depth + 1) end
    end
  end
  walk(root, 0)
  -- ── 这一趟之后：更新收敛账（见上面 ①② 两条）────────────────────────────
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and st.idle >= RAY_IDLE_STOP then
    -- ① 收敛：树里有带该字段的控件，而且它们**全都已经是 true** ⇒ 幂等的事做完了。
    st.done = true
    -- 只报一次（每次换屏都报会变成新的日志噪音，而用户这一轮明确嫌日志多）。
    if print and not st.announced then
      st.announced = true
      self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
        .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
    end
  elseif st.scans >= RAY_MAX_SCANS then
    -- ② 到顶：**放弃**，只报一次。
    st.done = true
    self:warn_once("raycast_giveup",
      "射线开关（raycastTarget）：扫了 " .. tostring(st.scans) .. " 趟，"
      .. "一个「带该字段的控件」都没找到（seen=0）—— 停止重扫。"
      .. "⚠️ 这一条是真问题：按钮没有 raycastTarget 就**点不动**"
      .. "（「界面看得见、点哪儿都没反应」）。请核对控件树是否就绪、"
      .. "控件是不是预设按钮；换屏/换关会自动重扫一次，不必重进游戏。")
  end
  return seen, set, samples
end
function Adapter:enforce_screen_layers(screen)
  local function put(id, idx)
    local c = self:find(id)
    if c == nil then return end
    if c.SetSiblingIndex ~= nil then
      pcall(function() c:SetSiblingIndex(idx) end)
    end
  end
  if screen == "home" then
    put("select", 0)
    put("home", 20)
  elseif screen == "select" then
    put("home", 0)
    put("select", 20)
  else
    -- 关卡内：两个都压到最下面（棋盘/顶栏/线索才该在最上）
    put("home", 0)
    put("select", 1)
  end
end
function Adapter:enforce_layers(cell_id)
  local order = (self.cfg.cells and self.cfg.cells.layer_order)
    or { "face", "obj",
         "wall.up", "wall.down", "wall.left", "wall.right",
         "door.up", "door.down", "door.left", "door.right",
         "x", "note" }
  local done = 0
  for i = #order, 1, -1 do
    local sub = self:sub(cell_id, order[i])
    if sub ~= nil and sub.SetAsFirstSibling ~= nil then
      if pcall(function() sub:SetAsFirstSibling() end) then done = done + 1 end
    end
  end
  return done
end

-- ★★ 打开「点击事件穿透」——**点不动格子的头号原因**。
--
-- 官方 API `ClientUIContainerControl` 的字段里有一个
--     `disableCursorEventPassthrough` —— 「是否屏蔽**区域内点击事件穿透**」
-- 方案 A 下，`content`（容器节点）**整块压在按钮 `cell` 上面**。
-- 只要它屏蔽穿透，鼠标点击就**到不了按钮** → 表现为"点格子完全没反应"，
-- 而体检一切正常（按钮自己的 raycastTarget = true 也照样读得到）。
--
-- 好消息：这个字段是**读写**的，所以脚本可以直接把它关掉 ——
-- 不用你逐个容器去取消勾选。
--
-- 顺带把 `showCursor` 也打开（官方：「CursorEvent 相关方法都需设置该参数为真后
-- 才可正常使用」），与门控②同源；`disableKeyEventPassthrough` 也放开，
-- 免得中间容器把键盘事件也吃掉。
-- ★★★ 2026-09-30：**屏蔽穿透 —— 把 2D 界面和 3D 角色隔开**。
--
--   用户问过"社区里怎么把 2D 操作和后面的 3D 角色模型隔开，是拦截键位还是别的办法"。
--   答案（官方《客户端 Lua UI 脚本公共 API》第 24 节 ClientUIContainerControl）：
--     **不是拦截键位**，而是给**容器**设"屏蔽穿透"字段（均读写）：
--       disableKeyEventPassthrough     是否屏蔽**按键**事件穿透
--       disableCursorEventPassthrough  是否屏蔽**区域内点击**事件穿透
--       isolateNavigation              是否隔离手柄导航
--   一个字段覆盖整棵子树，不需要按键黑名单。
--
--   为什么"拦截"思路走不通：`AddKeyEventListener` **只是监听，没有"消费"语义** ——
--   监听无法阻止引擎把按键交给角色。官方给的解法就是在容器层面屏蔽穿透。
--
--   ⚠️ 本项目里 `open_click_passthrough` 用的是**同一个字段的反方向**
--      （设 false，让点击落到棋子上）—— 所以这不是新机制，只是换个方向用。
--
--   ⚠️ 待真机验证：**屏蔽之后 `AddKeyEventListener` 自己还能不能收到按键**。
--      如果连自己也收不到，就不能对整屏开 —— 所以这里**逐个容器可配**，
--      并打一行日志说明设了几个。
function Adapter:seal_container(id)
  local c = self:find(id)
  if c == nil then return false end
  local n = 0
  -- ① 按键：**屏蔽穿透 = true**（**这才是 2D/3D 隔离的正确开关**）。
  --
  --   ★★★★★ 2026-10-02 **真机 A/B 对比得出的结论，别再改错了**：
  --
  --   官方文档（docs/api-cache/mh3qqq9xc102.txt）：
  --     「**屏蔽按键事件穿透**：容器节点内的按键事件交互**不会穿透到界面外**」
  --   —— 这里的"界面外"指的是 **3D 世界**（不是游戏的原生 UI）。
  --   ⇒ `true` = **按键不会传到 3D 角色**（隔离生效）。
  --
  --   【A/B 实测】
  --     · 设 `true`  + 回调 `return true`  ⇒ Enter 打不开原生对话框（按键被回调标记"已处理"）
  --     · 设 `false` + 回调 `return false` ⇒ **点击/Enter 都通了，但隔离彻底失效**
  --       （真机日志：`按键事件 → KeyboardJumpKeyDown` ⇒ 按跳跃键角色真的跳了）
  --   ⇒ 真相：**"Enter 打不开"是回调 `return true` 造成的，跟这个字段无关**；
  --     而这个字段设 `false` 才会让按键穿到 3D。
  --   ⇒ **正确组合 = 本字段 `true`（隔离）+ 回调 `return false`（不标记已处理）**。
  if c.disableKeyEventPassthrough ~= nil then
    if pcall(function() c.disableKeyEventPassthrough = true end) then n = n + 1 end
  end
  -- ② 点击：**必须放开（false）**！
  --
  --   ⚠️⚠️ 我第一版把这里也设成了 `true`，结果**主页上所有按钮都点不动**
  --   （点了完全没反应，界面像卡死）。本项目 `open_click_passthrough` 的注释早就写明：
  --       `disableCursorEventPassthrough = false` …… **否则点击到不了按钮**
  --   "屏蔽区域内点击事件穿透"的语义是「**点击不再传给这个区域里的控件**」，
  --   **不是**"挡住背后的 3D 世界"。对自己要用鼠标点的界面必须设 `false`，
  --   否则等于把界面锁死。真正要挡的是**按键**落到 3D 角色身上 —— 那是 ① 的职责。
  if c.disableCursorEventPassthrough ~= nil then
    pcall(function() c.disableCursorEventPassthrough = false end)
  end
  -- ③ 手柄导航隔离：社区资料少，**先不动**（等真机验证过再开）。
  return n > 0
end

-- 批量：给一组容器屏蔽穿透。返回成功的个数。
function Adapter:seal_containers(list)
  if list == nil then return 0 end
  local ok = 0
  for i = 1, #list do
    if self:seal_container(list[i]) then ok = ok + 1 end
  end
  return ok
end
function Adapter:open_click_passthrough(cell_id)
  local roots = (self.cfg.cells and self.cfg.cells.sub_roots)
    or { "content", "root", "body" }
  local parent = self:find(cell_id)
  if parent == nil or parent.GetChild == nil then return false end
  local touched = false
  for i = 1, #roots do
    local mid = nil
    pcall(function() mid = parent:GetChild(tostring(roots[i])) end)
    if mid ~= nil then
      if mid.disableCursorEventPassthrough ~= nil then
        pcall(function() mid.disableCursorEventPassthrough = false end)
        touched = true
      else
        -- 没有这个字段（不是容器节点 / 该实现不暴露）→ 只能靠编辑器里手动取消勾选
        self:warn_once("passthru:" .. cell_id,
          "中间容器 `" .. tostring(roots[i]) .. "` 读不到 `disableCursorEventPassthrough`，"
          .. "改不了。请在编辑器里把它的「**屏蔽区域内点击事件穿透**」**取消勾选** ——"
          .. "否则点击到不了按钮，表现为「点格子没反应」而体检却全绿。")
      end
      pcall(function() mid.disableKeyEventPassthrough = false end)
      pcall(function() mid.showCursor = true end)
    end
  end
  return touched
end

function Adapter:_apply_edges(id, prefix, flags)
  -- ⚠️ 返回值 = "**这一趟真的把边下发成功了吗**"（true/false），见下面 `missing_sub` 那段。
  --    没有边要画（flags 不是表）时算成功 —— 没东西要送，不该让上层一直重试。
  if type(flags) ~= "table" then return true end

  -- ★★ 内部边**只画一次** —— 否则同一条边被两格各画一条，屏幕上出现两条平行线。
  --
  -- 为什么：core 的 `view()` 里
  --     walls.up   = (r == 1)    or wall_set[h, r-1, c]
  --     walls.down = (r == rows) or wall_set[h, r,   c]
  --   于是**内部边**（键 `h, r, c`）既是上格的 `down`、也是下格的 `up` ——
  --   同一根墙被重复绘制，两者还隔着 gap 的间距，看着就是**两条线**。
  --
  -- 约定：**每条边由"上/左"的那一格负责画**；`down`/`right` 只在**最后一行/列**（真边框）才画。
  --   up(r=1)=顶边、down(r=rows)=底边、left(c=1)=左边、right(c=cols)=右边。
  local r, c = tostring(id):match("^cell%.(%d+)%.(%d+)$")
  r, c = tonumber(r), tonumber(c)
  local rows = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows)
  local cols = self.cells_cols or (self.cfg.cells and self.cfg.cells.cols)
  local skip = {}
  if r ~= nil and rows ~= nil and r < rows then skip["down"] = true end
  if c ~= nil and cols ~= nil and c < cols then skip["right"] = true end

  -- ★ 记下"本关真的需要哪些边" —— 之后和"模板里配了哪些子控件"对账。
  --   用户 2026-09-27 04:26 的实例：关卡里 `v:4:3` / `v:5:3` 是**竖墙**，
  --   但模板只配了 `wall.up`，于是那两面竖墙**根本画不出来**，
  --   而日志里当时**什么都没说** —— 全靠人看截图才发现。
  self.edges_needed = self.edges_needed or {}
  local sides = { "up", "down", "left", "right" }
  -- ★★★★★ 2026-10-05 **"这一趟到底送出去了没有"要答得上来**（返回值 → `set_property` → 界面层）。
  --
  --   为什么：`self:sub()` 查不到子控件时，下面这段是**静默跳过**的 —— 属性在界面层
  --   看起来"已经下发"，实际**一次 `SetVisible` 都没调用**。而 `sub` 只缓存命中、
  --   不缓存未命中（见它的注释），所以"首帧/首次进关子控件还没就绪"是完全可恢复的：
  --   只要上层**再下发一次**就能补上 —— 这正是用户报的
  --   "第一次进关墙/门没画出来、第二次正常"最可能的形状。
  --   ⇒ 这里把**本关真需要、却取不到子控件**的边记下来，函数返回 false；
  --     界面层按"有限次重试"补发（次数有上限，不会变成每帧死循环）。
  local missing_sub = {}
  for i = 1, #sides do
    local s = sides[i]
    local want = (flags[s] and not skip[s]) and true or false
    if want then self.edges_needed[prefix .. "." .. s] = true end
    local sub = self:sub(id, prefix .. "." .. s)
    if sub == nil then
      if want then missing_sub[#missing_sub + 1] = prefix .. "." .. s end
    elseif sub.SetVisible ~= nil then
      pcall(function() sub:SetVisible(want) end)
    end
  end

  -- ★★★★★ 2026-10-05 **关卡内读回：每个格子只打一次** ✗✓ —— 时机对了才有意义 ✓
  --
  --   为什么要在【这里】打（而不是"逐格自检"那里 ✓）：
  --     · 上一版打在 `逐格自检` 里 ✗ ⇒ 而那一刻 `controller.screen` 还是 `"home"` ✗
  --       （真机日志紧接着就打了 `controller.screen = home` ✓）
  --       ⇒ ★ 读数全是 `vis=false` ✗ —— 而【同一行】的 `clues` 也是 false ✗
  --         可用户实测【线索区是好的】✓ ⇒ ★★ 证明那行读数【不在关卡内】✗✓
  --     · 而 `_apply_edges` 是**每帧渲染**都会走的 ✓ ⇒ ★ 这里才是"关卡内真实状态" ✓
  --
  --   ★ 判据（这次时机是对的 ✓）：
  --     · `vis=true` ✓ 而屏幕上没有 ✗ ⇒ ★ 层序/素材（但 sib/sx 已排除 ✓）
  --     · `vis=false` ✗ ⇒ ★ `SetVisible(want)` 当帧没生效 ⇒ 句柄/引擎 ✓
  --     · `vis` 与 `want` 不一致 ✗ ⇒ ★ 有人在别处覆盖它 ✓
  --   ⚠️ 只读 ✓ 每格只打一次（`self._edge_readback`）✗ 不刷屏 ✓
  -- ★★★★★ 2026-10-05 **去重键必须带 `prefix`** ✗✓ —— 否则读回是假象 ✓
  --
  --   我第一版用 `self._edge_readback[id]` ✗ ⇒ 而 `_apply_edges` 对**同一个格子**
  --   会被调用**两次**（`prefix="wall"` 一次 ✓ `prefix="door"` 一次 ✓）
  --   ⇒ ★★ 只记了第一次 ⇒ 真机日志里**只有 `door.*`** ✗ ⇒ 看起来"只有门没有墙" ✓✓
  --   ⇒ ★ 那是我探针的假象 ✗ —— ★ 离线探针已证明 `wall_set` 有 **7 条** ✓
  --     `view()` 有 **34 条墙边** ✓ ⇒ ★ 数据是对的 ✓
  --   ⚠️ 结论：★ **诊断代码的假象比被测 bug 更能骗人** ✓ —— 这次连吃了两次
  --     （上次是 `print_` ✗ 这次是去重键 ✗）
  -- ★★★★★ 2026-10-05 **把这一刻的"该亮哪些边"记下来** ✗✓ —— 供每帧重放 ✓
  --
  --   为什么必须记：★ `face` 是【每帧】被点亮的 ✓（真机日志：
  --   「格子底图已点亮：25 个 face（每帧保持）」✓ 走的是 `_cells_paint` ✓）
  --   而 `wall.*` / `door.*` 只在**属性下发那一趟**设一次 ✗
  --   ⇒ ★★ 只要之后任何一帧有人把它们覆盖回 false ✗ ⇒ **`face` 会被救回来 ✓ 而墙/门不会** ✗✓
  --     ⇒ ★ 屏幕上看不见 ✓ —— ★ 而我的读回是在**这一刻**读的 ✓ ⇒ 当然读到 true ✓✓
  --       ⇒ ★★ "读回 true 而屏幕没有"的最后一层就在这里 ✓
  --   ⇒ 记下来，在 `_cells_paint`（每帧那条路 ✓）里重放 ✓ —— 与 `face` 同等待遇 ✓
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end

  -- ★★★★★ 2026-10-06 **记下"该亮哪些边"，供每帧重放** ✗✓ —— 对抗 `hide_kids` 的递归藏 ✓
  --
  --   ★★ 这是"墙/门第一次进关不画"的**第二半**（也是真正的凶手 ✓）：
  --     · 适配层 `set_property(…, "visible", false)` 里有一段 ✗：
  --         `if vis == false and id:sub(1,5) == "cell." then hide_kids(ctrl, 0) end`
  --       ⇒ ★ 它把格子的**全部子控件递归设成 false** ✗（`face` / `wall.*` / `door.*` ✓）
  --     · ★ 而它**只在 `vis == false` 时递归** ✗（那段的注释自己说"显示时不递归" ✓）
  --       ⇒ ★★ **单向** ✗ ⇒ `cell.*` 一旦被藏过 ⇒ 子控件永不恢复 ✓✓
  --     · ★ 为什么"第二关正常"✗：★ 第二关【不重建格子】✗
  --       ⇒ `cell.*` 没有 `false → true` 的过程 ✗ ⇒ **从不触发那个分支** ✓
  --       ⇒ 子控件从没被递归藏过 ✓ —— ★★ 这解释了"只有第一关坏" ✓✓
  --   ⇒ ★ 修法：★ **把"该亮"记下来，在每帧都会跑的 `_cells_paint` 里重放** ✓
  --     这与 `face` 的"每帧保持"是**同一个套路** ✓（那段注释也是这么写的 ✓）
  do
    self._edge_want = self._edge_want or {}
    local w = self._edge_want[id]
    if w == nil then w = {}; self._edge_want[id] = w end
    for i = 1, #sides do
      local s = sides[i]
      w[prefix .. "." .. s] = (flags[s] and not skip[s]) and true or false
    end
  end



  -- ★★ 「图片类型 = 基础」的图**按原尺寸画，不会填充控件** ——
  --    真机 2026-09-27 05:13 实测：同一面墙，素材选「拉伸」时是**满宽蓝条**，
  --    换成「基础」后只剩**左上角一小段**（"显示不完全"）。
  --    而「拉伸」只有**部分资产**支持（官方：「部分图片资产具有拉伸属性」），
  --    所以"大多数素材只能用基础"是常态。
  --
  --    对策：用 `localScaleX/Y`（官方：number、**读写**、Tweenable）把基础图**缩放**到
  --    目标长度。缩放不是"拉伸"（不保角），但对**墙/门这种纯色条**完全够用，
  --    而且**任何素材都能用** —— 这就把可用素材范围打开了。
  --
  --    前提：编辑器里把墙控件的尺寸调成**"正好包住那张图"**（脚本按
  --    目标长度 ÷ 这个尺寸 求缩放比）。控件已经铺满整条边时缩放比≈1，不受影响。
  if self.cfg.cells == nil or self.cfg.cells.edge_fit ~= false then
    -- 格子边长：`cell_geometry(n)` 才是权威算法（它按 board 实际尺寸与行列数算）。
    -- n 用当前关卡的真实行列数（ensure_cells 时记在 self.cells_rows/cols 上）。
    local n = self.cells_rows or (self.cfg.cells and self.cfg.cells.rows) or 5
    local cw = nil
    pcall(function() cw = self:cell_geometry(n) end)
    local ch = cw
    if type(cw) ~= "number" or cw <= 0 then cw, ch = nil, nil end

    -- ★★★★★ 2026-10-05 **"算不出格子边长"必须说出来**（否则这一整段是静默跳过的）。
    --
    --   为什么：下面 `if cw ~= nil then` 一旦为假，**整个几何适配（缩放 + 贴边）都不跑**，
    --   日志里却一个字都没有 —— 而"什么都没做"和"做了但没生效"在画面上完全一样，
    --   排查时会往错的方向找（比如怀疑贴图/层序）。
    if cw == nil and print and not self._edge_no_geo_noted then
      self._edge_no_geo_noted = true
      print("[murdoku] 边缘适配：**算不出格子边长**（cell_geometry(" .. tostring(n)
        .. ") 返回 0/nil）⇒ 墙/门的**缩放与贴边整段跳过**（按编辑器里摆的原样显示）")
    end

    -- 墙/门的**目标厚度**（画布单位）。做成配置项，这样"看起来多粗"是确定的数字，
    -- 而不是"看你素材多大"。
    local thick = (self.cfg.cells and self.cfg.cells.edge_thickness) or 8
    local door_ratio = (self.cfg.cells and self.cfg.cells.door_length_ratio) or 0.45

    if cw ~= nil then
      for i = 1, #sides do
        local s = sides[i]
        local sub = self:sub(id, prefix .. "." .. s)
        if sub ~= nil and flags[s] then
          local w, h = nil, nil
          pcall(function() w, h = sub:GetSizeDelta() end)
          local horiz = (s == "up" or s == "down")
          -- 目标几何：横边 = 长 cw × 厚 thick；竖边 = 厚 thick × 长 ch
          -- 门比墙短一点，看起来才像"门"而不是一整面墙
          local tlen = (prefix == "door") and (cw * door_ratio) or cw
          local tthick = thick
          local base_l = horiz and w or h      -- 基准：编辑器里控件的尺寸
          local base_t = horiz and h or w
          if type(base_l) == "number" and base_l > 0 and type(base_t) == "number" and base_t > 0 then
            local kl = tlen / base_l
            local kt = tthick / base_t
            -- ★ 双向缩放：**长和厚都由脚本定死**，所以最终看到的条一定是
            --   目标长度 × 目标厚度，跟你素材多大无关（前提：控件尺寸 == 素材原尺寸，
            --   即"别手动改尺寸，让编辑器按图自动定"）。
            if kl > 1.001 or kl < 0.999 then
              if horiz then pcall(function() sub.localScaleX = kl end)
              else pcall(function() sub.localScaleY = kl end) end
            end
            if kt > 1.001 or kt < 0.999 then
              if horiz then pcall(function() sub.localScaleY = kt end)
              else pcall(function() sub.localScaleX = kt end) end
            end
            -- 把基准和倍率**打进日志**：这样"正好包住"变成一个可核对的数字，
            -- 而不是一句模糊的话。第一次试玩看一眼就知道该不该调。
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              if not self._edge_fit_seen[s] then
                self._edge_fit_seen[s] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：基准 %.0fx%.0f → 目标 %.0fx%.0f（倍率 %.2f / %.2f）",
                    prefix, s, w or 0, h or 0, horiz and tlen or tthick, horiz and tthick or tlen, kl, kt))
                end
              end
            end
          else
            -- ★★★★★ 2026-10-05 **基准读成 0 ⇒ 这一段是"静默跳过"的，必须明说**。
            --
            --   判据：`base_l` / `base_t` 取的是控件自己的 `GetSizeDelta()`（"编辑器里摆的尺寸"），
            --   它是**缩放倍率的分母**。分母是 0 或读不到时，这段（缩放）**整段不执行**，
            --   而下面的"贴边"照旧执行 —— 于是画面上是"墙在正确的位置上，但是原来那么大"
            --   （或者根本看不见），很容易被读成"贴边也没生效"。
            --   ⇒ 直接把读到的原始值打出来：这行和上面那行「基准 …→ 目标 …（倍率 …）」
            --     **互斥**（一个成功一个失败），日志里看到哪一行就知道走了哪条路。
            if self.cfg.cells and self.cfg.cells.edge_fit_log ~= false then
              self._edge_fit_seen = self._edge_fit_seen or {}
              local skip_key = "skip:" .. prefix .. "." .. s
              if not self._edge_fit_seen[skip_key] then
                self._edge_fit_seen[skip_key] = true
                if print then
                  print(string.format(
                    "[murdoku] 边缘适配 %s.%s：**基准读成 0 / 读不到**（w=%s h=%s）"
                    .. "⇒ 缩放这一段整段跳过（贴边照做）；原因通常是子控件尺寸还没定下来，"
                    .. "或编辑器里没给它尺寸",
                    prefix, s, tostring(w), tostring(h)))
                end
              end
            end
          end
          -- 贴到对应边（缩放绕中心，所以位置按"目标厚度"算，不再依赖控件自身尺寸）
          local x, y = 0, 0
          if s == "up" then y = (ch - tthick) / 2
          elseif s == "down" then y = -((ch - tthick) / 2)
          elseif s == "left" then x = -((cw - tthick) / 2)
          elseif s == "right" then x = ((cw - tthick) / 2) end
          if sub.SetPivot then pcall(function() sub:SetPivot(0.5, 0.5) end) end
          if sub.SetAnchoredPosition then pcall(function() sub:SetAnchoredPosition(x, y) end) end
        end
      end
    end
  end
  -- ★ 只有"本关真需要的边**全都取到了子控件**"才算下发成功；取不到的交给上层**有限次**重发。
  --   ⚠️ 这里**只对"子控件取不到"负责**：倍率/贴边那两段也有各自静默跳过的情形
  --      （比如基准尺寸读成 0），但那些不是"缺控件"，把它们也算成失败会让每条边都反复重发，
  --      纯粹是噪音 —— 那两种情形已经各自打了日志（见上面两处「边缘适配 …」）。
  return #missing_sub == 0
end

function Adapter:set_property(id, key, value, nkey)
  -- ★★★★★ 2026-10-05 **返回值 = "这次真的送达了吗"**（true/false），界面层据此决定记账 or 重发。
  --
  --   为什么要有返回值：这里在 `find(id) == nil` 时是**静默 no-op**（既不报错也不写），
  --   而界面层原来是**无条件**把属性记成"已下发" ⇒ 首次进关时"控件还没进树"
  --   就把状态记死了 ⇒ 本关内**永不重发**，只能出关重进
  --   ⇒ 用户看到的"第一次进关渲染得比第二次少"。
  --   ⇒ 契约：**true = 该做的都做了（可以记账）；false = 这次没送到（上层可以重发）**。
  --     ⚠️ 只有"确实没送到"才返回 false —— 故意的空操作（如 `respect_editor_rect`
  --     跳过位置）要算 true，否则那些属性会被无意义地反复重发。
  local ctrl = self:find(id)
  if ctrl == nil then return false end

  if key == "text" then
    -- ★★ 2026-09-28：**按钮的文字走 `label` 子控件**。
    --
    -- 起因：我生成了 35 个按钮的 `label` 子控件（真机 `label(visible=true)` ✅），
    --   但**屏幕上一个字都没有**。探明原因后是这么回事：
    --     · 控件的**文字内容根本不存进 `.gil`**！
    --       证据：`hud.title` 里唯一的文本字段内容是 `"hud.title"`（它自己的名字），
    --       而屏幕上那句"框架自检样例（偷窃版）"是**脚本运行时填的**。
    --     · 空文字 = 那个字段**根本不存在**（和"空子控件列表"同一个规律）——
    --       所以往 .gil 里写初值这条路走不通。
    --   ⇒ 结论：**按钮名字必须由脚本在运行时填**。这里把按钮的文字转发到它的 `label` 子控件。
    --
    -- 顺序（先专用后通用）：
    --   ① 按钮自己的 `label` 子控件（我生成的那种）
    --   ② 按钮自己就是文字控件（`ctrl.text` 可写）
    --   ③ 老的 `text` 子控件（兼容）
    local done = false
    do
      local lc = nil
      pcall(function() lc = self:sub(id, "label") end)
      if lc ~= nil and lc.text ~= nil then
        local ok = pcall(function() lc.text = tostring(value) end)
        done = ok
      end
    end
    if not done and ctrl.text ~= nil then
      ctrl.text = tostring(value)
      done = true
    end
    if not done then
      local c = self:sub(id, "text")
      if c and c.text ~= nil then c.text = tostring(value); done = true end
    end
    -- ★ 三条路都走不通（没有 label / 自己不能写字 / 没有 text 子控件）⇒ 这次**没送到**。
    --   真机意义：按钮文案是运行时填的（不进 .gly），首帧"label 子控件还没就绪"时
    --   这里会返回 false，界面层就会**下一帧再补一次** —— 而不是让按钮永远空着。
    return done

  elseif key == "object" then
    -- ★★ 2026-09-28 新增：**物件图标的显隐**。
    --
    -- 背景（用户报「人物头像上有异常遮挡」）：模板里的 `obj` 子控件是给物件图标（书桌/地毯）留的，
    --   `layer_order` 把它排在 `face` **之上**。但我当初克隆它用了**白色占位图**，
    --   **又没有任何代码去关它** ⇒ 它永远是"一块白板压在头像上"：
    --   空格看不出（face 本来就是白图），**一放人就露馅** ——
    --   截图里 C3/R1、C4/R2、C4/R3 那三块白方块就是它。
    --   ⇒ 没物件就**藏起来**；将来配了物件图（调色板 `obj.*`）再按名字换图并显示。
    local o = self:sub(id, "obj")
    if o ~= nil then
      -- `false` 是 ui_controller 约定的"没有物件"哨兵（nil 会让这个键在 `pairs` 里消失）
      if value == false or value == nil then
        if o.SetVisible then pcall(function() o:SetVisible(false) end) end
        return true          -- ★ "藏起来"就是这次要做的全部 ⇒ 算送达（不要重发）
      end
      -- ⚠️ 这里**不要用 `resolve_asset`** —— 它查不到会 `warn_once` 打**报错**，
      --    而"调色板里还没有 obj.* 素材"是**当前阶段的正常状态**（物件美术还没配），
      --    不该污染日志。直接查表，查不到就藏起来。
      local hit = nil
      do
        local map = self:read_palette()
        local key = tostring(value)
        hit = map[key]
      end
      if hit ~= nil and hit.id ~= nil then
        local src = nil
        pcall(function() src = o.imageSource end)
        if hit.source ~= nil then src = hit.source end
        pcall(function() o:SetImage(src, hit.id) end)
        if o.SetVisible then pcall(function() o:SetVisible(true) end) end
      else
        -- 没有物件（或名字解析不出来）→ **必须藏**，否则白板会盖住头像
        if o.SetVisible then pcall(function() o:SetVisible(false) end) end
      end
    end
  elseif key == "imageType" then
    -- ★★★ 2026-10-01：**强制图片的拉伸方式**（Basic = 按原始像素 / Stretch = 填满控件）。
    --
    --   背景（真机日志对比出来的）：
    --     正常工作的：  bg(visible=true type=Enum.ImageType.Stretch id=100108)
    --                   face(visible=true type=Enum.ImageType.Stretch id=106053)
    --     我克隆出来的：action.submit.hex1(visible=false type=Enum.ImageType.Basic id=100001)
    --   **Basic 就是"按原始像素铺"** —— 如果 `100001` 是 1×1，画出来就等于**看不见**。
    --   日志自己也提示过：「静态引用大多不支持拉伸 —— 需要拉伸的地方请选「底板」类素材；
    --   imageType 显示 Stretch 才说明这个素材支持，Basic 就只能按原样铺」。
    --
    --   而 `imageType` 是**读写**字段（docs/未验证清单.md 第 2 条那条「SetImage 之后
    --   imageType 会不会变」的验证日志里记着），所以这里直接赋枚举值即可。
    --
    --   为什么要在脚本里设、而不是写进 `.gil`：`imageType` **不在存档记录里**
    --   （我把 wall.left / wall.right 逐字段比过，只差 id，没有任何 visible/imageType 差异）
    --   ⇒ 它是引擎按素材算出来的默认值 ⇒ 只能运行时改。
    local want = nil
    pcall(function() want = value end)
    if want ~= nil then
      local enum = nil
      pcall(function() enum = Enum.ImageType[tostring(want)] end)
      if enum ~= nil then
        pcall(function() ctrl.imageType = enum end)
        -- 子控件（face/obj）也有 imageType，一起设，免得"设了父级没生效"
        local f = self:sub(id, "face")
        if f ~= nil then pcall(function() f.imageType = enum end) end
      end
    end
  elseif key == "image" then
    -- 头像/格面/物件图标：图片来自子控件 "face"
    --
    -- `value` 可以是两种：
    --   · 整数 ID（老写法，兼容）；
    --   · **调色板里的素材名**（字符串）—— 推荐写法，例如 "room.kitchen"。
    --     整数 ID 的难题（只读字段 + 不能手抄数字）由调色板解决：见 read_palette。
    local target = self:sub(id, "face") or ctrl
    if target ~= nil then
      -- ★★ 2026-09-27 修：**没有图时不要直接把 face 藏掉**。
      --
      -- 旧行为：`value == nil` → `SetVisible(false)`。后果很严重 ——
      --   格子的 `face` 在编辑器里**配了默认底图**（真机日志 `imageId=106053`），
      --   而空格的 view 里 `image = nil`（角色没配 portrait），于是**每次开局
      --   脚本都把底图藏了** → 玩家看到的是"格子什么都没有"。
      --   用户报的"文本图片都没有配备""放置没有视觉反馈"里有一部分就是这个。
      --
      -- 新行为：**记住第一次看到的图（编辑器配的默认图），并只在"我们换过图"之后
      --   才需要还原**。`value == nil` 时：换过 → 还原默认图；没换过 → 什么都不做。
      --   这样既不会留上一张残图，也不会把编辑器配好的底图抹掉。
      self._face_def = self._face_def or {}
      local d = self._face_def[id]
      if d == nil then
        d = { src = nil, id = nil, visible = true }
        pcall(function() d.src = target.imageSource end)
        pcall(function() d.id = target.imageId end)
        pcall(function() d.visible = target.visible end)
        self._face_def[id] = d
      end

      -- ★★ 2026-09-28：`false` 是 ui_controller 约定的「这格没有人」哨兵。
      --   为什么需要它：渲染循环是 `for k, v in pairs(n)`，
      --   **Lua 里 `image = nil` 等于"这个键不存在"** ⇒ 人走了的格子**永远不会下发 image**
      --   ⇒ 旧格的头像**永远不清**（用户报的「换位后头像卡残留」）。
      --   这和 `obj` 白块是**同一个 bug 形状** —— 我在同一个坑里摔了两次，
      --   所以现在两个值都统一用 `false` 当哨兵。
      if value == false then value = nil end
      if value == nil then
        if d.swapped then                       -- 只有"换过图"才需要还原，避免留残图
          if target.SetImage and d.id ~= nil then
            pcall(function() target:SetImage(d.src, d.id) end)
          end
          d.swapped = false
        end
        -- 注意：这里**不再** SetVisible(false) —— 编辑器配的底图要留着
      elseif target.SetImage then
        local src = target.imageSource                 -- 默认沿用编辑器配好的来源
        local hit = self:resolve_asset(value)
        if hit ~= nil then
          if hit.source ~= nil then src = hit.source end   -- 调色板带了来源就用它的
          if hit.id ~= nil then
            local ok, err = pcall(function() target:SetImage(src, hit.id) end)
            if not ok then self:warn_once("setimage", "SetImage 失败：" .. tostring(err)) end
            d.swapped = true
          end
        end
        -- ★ 图片换上了还不够：face 子控件必须可见，否则玩家什么也看不到
        if target.SetVisible then pcall(function() target:SetVisible(true) end) end

        -- ★★ 「SetImage 之后 imageType 会不会变」的验证日志（`docs/未验证清单.md` 第 2 条）：
        --   控件的「图片类型」（基础/拉伸）是**控件级**属性；换上"功能图标"类素材后，
        --   可能保持 Stretch（头像铺满），也可能按新素材退回 Basic（小小一张居中）。
        --   `imageType` 是**读写**字段，所以**直接读回来打印**就行 ——
        --   比让用户盯着屏幕判断"铺满还是小小一张"可靠得多。
        if self.cfg.debug_image then
          local it = nil
          pcall(function() it = tostring(target.imageType) end)
          print(string.format("[murdoku] SetImage 后 `%s` 的 imageType = %s（Basic=按原始像素 / Stretch=填满）",
            tostring(id), tostring(it)))
        end
      end
    end

  -- ★ 每格四边的墙 / 门（靠固定子控件 + SetVisible 开关，不用为每格做模板）
  elseif key == "walls" then
    -- ★ 返回值直达上层：`_apply_edges` 只有在"本关真需要的边全都取到子控件"时才返回 true
    --   （见它内部 `missing_sub` 那段）。首帧子控件没就绪 ⇒ false ⇒ 界面层下一帧补发。
    return self:_apply_edges(id, "wall", value)

  elseif key == "doors" then
    return self:_apply_edges(id, "door", value)

  -- ★ 染色：`imageColor` 官方是 **读写**（ColorValue、Tweenable），
  --   所以"同底图 + 不同颜色区分区域"是零额外素材的做法。
  --   value 用 {r,g,b,a?}（0–255）；官方构造是全局函数 `Color(r,g,b,a?)`。
  elseif key == "tint" then
    local target = self:sub(id, "face") or ctrl
    if target ~= nil and type(value) == "table" then
      local r = tonumber(value.r or value[1]) or 255
      local g = tonumber(value.g or value[2]) or 255
      local b = tonumber(value.b or value[3]) or 255
      local a = value.a or value[4]
      local made = nil
      if type(Color) == "function" then
        if a ~= nil then made = Color(r, g, b, tonumber(a) or 255)
        else made = Color(r, g, b) end
      end
      if made ~= nil then
        local ok = pcall(function() target.imageColor = made end)
        if not ok then
          self:warn_once("tint", "设置 imageColor 失败（可能是 ColorValue 的构造方式不对）")
        end
      else
        -- ⚠️ 没有全局 `Color` **不是错误**，只是这个运行环境不支持染色
        --    （模拟器就没有它）。所以这里用 print 说一次，**不能走 printerr** ——
        --    模拟器有「运行期不得有错误日志」的断言，走 printerr 会把 8b/9 两步打挂。
        if not self._tint_no_color_noted then
          self._tint_no_color_noted = true
          if print then
            print("[murdoku] 环境没有全局函数 `Color`，染色跳过（不影响玩法）。"
              .. "官方文档里 ColorValue 由 `Color(r,g,b,a?)` 创建（0–255，a 可省略）。")
          end
        end
      end
    end

  elseif key == "visible" then
    -- ★★★★★ 2026-10-05 **要显示时，显式补一次 `SetActive(true)`** —— 社区知识给的强候选根因。
    --
    --   来源：作者仓库 `client/lua-runtime/docs/observed-contract.md:7`（**真机**）。
    --   原文要点：`ClientUIBaseControl.active` 的**默认值三方不一致** ——
    --     · 官方加工稿写「默认为 `false`」；
    --     · 真机**未改过**的客户端模板实例为 `true`；明确设 `false` 的实例为 `false`；
    --     · 编辑器新建节点默认 `true`。
    --   ⇒ **手写控件树漏写 `active`，会比编辑器里新建的节点「少一层可见性」**，
    --     看起来就像「我改了 visible 又被改回去」。
    --
    --   我们这一侧的实测（可复现）：
    --     · `lua/ui_controller.lua` 里 `push({` 共 **80 处**，其中写 `active` 的 **0 处** ✗；
    --     · 本文件里 `SetActive` **只有一处**（销毁时的 `SetActive(false)`）⇒ **从不 `SetActive(true)`** ✗。
    --   ⇒ 规划节点是**手写**的（不是编辑器摆的），若被引擎按 `active=false` 处理，
    --     那么 `SetVisible(true)` 也**不显示** —— 这正是「门墙 / 网格列表项渲染不出来」的候选根因。
    --
    --   为什么只补 `value == true`：隐藏方向不需要补，而且 `SetActive(false)` 会**停掉子树脚本**
    --     （另一套语义，本项目已记录）⇒ 只在"要显示"时补，幂等、低风险 ✓
    --   ⚠️ 验收只能靠**真机截图（L3 层）**：离线模拟器不还原 active 的默认值差异 ✗
    if value == true and ctrl.SetActive ~= nil then
      pcall(function() ctrl:SetActive(true) end)
    end
    -- ★★★★ 2026-10-01 **隐藏要连子控件一起藏**（真机"点不动"的根因）。
    --
    --   真机排行榜（从 root 用 GetChildren 递归）显示选关页上还有：
    --        tray 300x182 / legend 300x63 / face 135x135 / content 135x135 x十几
    --   —— 全是**关卡内的东西**，而 content/face 是**格子模板自带的子控件**。
    --
    --   原因：`apply_screen_hide` 只把 `cell.1.1` 这类**格子本身**设成不可见，
    --   格子的子控件（content/face/text/obj/wall…）是**模板实例化**带出来的，
    --   脚本从没设过它们的 visible => 它们一直显示着，铺在棋盘位置上，
    --   而 `cell.*` 自己绑了点击 => **射线被格子接走，选关卡片收不到**。
    --
    --   规则：隐藏时**递归隐藏所有子控件**；显示时同样递归显示
    --   （格子的子控件本来就该跟着格子走，各自显隐由格子状态渲染另行覆盖）。
    --   枚举用 GetChildren()（项目里已验证可用）。
    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end
    -- ★ 记一份"当前被隐藏的 id"，交给每帧的 enforce_hidden_subtrees 兜底。
    --   为什么要兜底：渲染**只在属性变化时**才下发（same_value 缓存）
    --   ⇒ `cell.1.1` 的 visible=false 只在第一帧下发过一次，
    --   而格子的子控件（content/face/…）是模板**之后**才实例化出来的
    --   ⇒ 那一次递归隐藏根本没赶上它们（真机排行榜里 face/content 依然可见）。
    self._hidden_ids = self._hidden_ids or {}
    if vis then self._hidden_ids[id] = nil else self._hidden_ids[id] = true end
    -- ★★★★★ 2026-10-05 **可见性真的被脚本改了 ⇒ 兜底隐藏这一帧必须重跑一次。**
    --
    --   这是 `enforce_hidden_subtrees` 从"每帧扫"改成"事件驱动"之后的**主要触发源**
    --   （另外几个：切屏/换关、新建或销毁控件、收到光标事件 —— 见 `invalidate_lookups`
    --   和 `_fire`）。之所以在这里无条件置位而不去读 `ctrl.visible` 比较：
    --   界面层只在**属性值变了**才会走到这里（`same_value` 缓存），所以"进到这个分支"
    --   本身就已经是"可见性变了"的证据；置一个布尔比回读一次引擎属性便宜得多。
    self._subtree_dirty = true
    -- ⚠️ **只在"隐藏"时递归** —— 我第一版连"显示"也递归，结果把各控件
    --   自己藏起来的子控件又显示出来了（play_test 立刻报：
    --   棋盘的弹窗是隐藏的 / 此时没有指认面板 / 从存档点开始进关时 board=true home=true）。
    --   显示时不递归：子控件的显隐各有自己的负责人（格子渲染会逐个设
    --   face/note/x 的 visible），脚本不该越权替它们决定。
    -- ⚠️⚠️ 递归**只对 `cell.` 生效**。
    --   我第一版对所有控件递归隐藏 —— play_test 立刻红了三条
    --   （从存档点开始进关时 board=true home=true、选关页 home 没藏住、
    --     关卡内主页/选关没藏住）。说明"隐藏容器就递归隐藏子控件"会打乱
    --   各控件自己那套显隐责任划分。
    --   而**真正需要递归的只有格子**：`cell.N.M` 的子控件（content/face/text/obj/wall…）
    --   是**模板实例化**带出来的，脚本从不单独设它们的 visible
    --   ⇒ 格子藏了它们还亮着 ⇒ 铺在棋盘位置上 ⇒ 射线被格子接走。
    if vis == false and id:sub(1, 5) == "cell." then
      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local kids = nil
        pcall(function() kids = node:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              if k.SetVisible then pcall(function() k:SetVisible(false) end) end
              hide_kids(k, depth + 1)
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    -- ★★★★★ 2026-10-06 **对称：格子重新可见时，把该亮的子控件放回来** ✗✓
    --
    --   ★ 这是用户复盘出来的那条 ✓（原话：「要么 PREFIX 里的 cell. 没重新删掉，
    --     要么合并的有问题」✓ —— **是合并引入了触发器** ✓）：
    --     · 上面那段递归【一直在】✗ —— ★ 但删掉 PREFIX 的 `"cell."` 之后
    --       **没人再写 `cell.* = false`** ✗ ⇒ ★ 它**从不触发** ✓（墙门正常 ✓）
    --     · 而把 `visible = (self.screen == nil)` 加进规划 ✗
    --       ⇒ ★ 主页时规划写 `cell.* = false` ✗ ⇒ **递归被重新触发** ✗
    --       ⇒ ★★ 子控件（`face` / `wall.*` / `door.*`）全灭 ⇒ **墙门又不见了** ✓✓
    --   ⇒ ★ 上面那段**只在隐藏时递归** ✗（它自己的注释也写着"显示时不递归"✓）
    --     ⇒ ★★ **单向** ✗ ⇒ 藏过的子控件**永远回不来** ✓✓
    --   ⇒ ★ 这里补上**对称的那一半** ✓：★ 格子变可见 ⇒
    --     · `face` 点亮 ✓（底图 ✓）
    --     · `wall.*` / `door.*` 按 `_edge_want` 恢复 ✓（★ 就是"该亮哪些边" ✓）
    --   ⚠️ 只在 `vis == true` **且**这一刻确实是格子的根时做 ✗（过渡时一次 ✓ 不是每帧 ✓）
    if vis == true and id:sub(1, 5) == "cell." then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.SetVisible ~= nil then
        pcall(function() face:SetVisible(true) end)
      end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil and s2.SetVisible ~= nil then
            pcall(function() s2:SetVisible(want) end)
          end
        end
      end
    end
  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end

  elseif key == "rect" and self.apply_rect then
    if ctrl.SetAnchoredPosition then ctrl:SetAnchoredPosition(value.x, value.y) end
    if ctrl.SetSizeDelta then ctrl:SetSizeDelta(value.w, value.h) end

  elseif key == "event" then
    -- 让增量渲染能把「同一条按钮换了事件」同步下来（配合 bind_input 的现查）
    --
    -- ★★★★★ 2026-10-05 **按「规划节点」记，不按控件 id**（这一条是「同 id 两个节点
    --   互相覆盖」的第二半，见 `Adapter.new` 里 `self.events` 那段）。
    --
    --   ⚠️ 2026-10-05 修：这两行原来用的是 **ASCII 双引号**（`"同 id …` / `互相覆盖"`）✗
    --      ⇒ 被 `tools/lua_quote_scan.ps1`（check_all 步骤 **2g**）判红 ✓
    --      —— 判据很硬：**该行的 ASCII 双引号个数为奇数** ✓（这里是 1 个 ✗）
    --      在 `--` 注释里暂时无害 ✓ 但**同一个写法一旦落进字符串**就会让字符串提前结束 ✗
    --      ⇒ 语法错误，而且**报错行号指向别处** ⇒ 极难一眼看出 ✓（本项目踩过 4 次 ✓）
    --      ⇒ 规矩：中文引号一律用 **「」** ✓ 不要用 ASCII 的英文引号字符 ✗
    --      ⚠️ 连"举反例"都不行 ✓ —— 我第一版修复里为了说明这件事，
    --         在注释里把那个字符**打了出来** ⇒ 扫描器**照样判红** ✗✓
    --         （判据只数"该行 ASCII 双引号是不是奇数"，**不看语境** ✓）
    --         ⇒ 要提它时：**描述**（如"英文引号字符"）✓ 不要**写出它** ✗
    --
    --   旧写法：
    --       local h = self.handlers[id]
    --       if h == nil then h = {}; self.handlers[id] = h end
    --       h.event = value
    --   ⇒ 一份表、两个节点轮流写：`action.back` 的 `topbar` 节点先写 `back_confirm`、
    --     `right` 节点紧接着写 `back` ⇒ **前者静默消失**（不报错）。
    --   ⇒ 现在每个规划节点各占一格；`nkey` 由渲染循环算好传进来（**复用**属性账本那把
    --     `node_key`，不在这里另造）。
    --   ⚠️ `nkey == nil` 时退回按 id —— 兼容旧调用方（例如 `main.lua` 里
    --      `bind_input("selbtn.N", {...})` 那条路，以及离线假适配器/老测试）。
    local k = nkey or id
    self.events[k] = value
    -- ★★★★★ 2026-10-05 **B2（用户拍板 ✓）：认领者赢 —— 只认第一次。**
    --   `event_claim[id]` = **第一个**给这个控件写过事件的规划节点 = 这颗控件的语义归属者
    --   （理由与三条硬证据见 `Adapter.new` 里 `self.event_claim` 那段）。
    --   ⚠️⚠️ 这里**必须是 `== nil` 判断**（"只认第一次"）：后写的节点**不许换人** ✗
    --     —— 一旦写成无条件赋值，就等于退回"最后写的赢"（B2 要修的就是这个 ✗）。
    if self.event_claim[id] == nil then self.event_claim[id] = k end
    -- ⚠️ 诊断用（**不再是派发依据**）：这个控件最近一次被哪个节点写过事件。
    --   `topbar` 与 `right` 写的是**同一个控件**，所以它记的是"最后那份"（`right`）。
    self.event_latest[id] = k

  elseif key == "rect" then
    -- ★★★ 2026-09-29：**编辑器优先 —— 不再覆盖你已经调好的控件几何**。
    --
    --   用户反馈「加入的文本与我调整的布局未完整生效」。
    --   根因：`M.LAYOUT` 里的坐标是我**当初规划时写的**，而用户在编辑器里
    --   把按钮的尺寸/位置都改过（例如 `action.hint` 的 bg 从 90×52 改成 97×43、
    --   label 改成 59×40）。脚本每次渲染都按自己的表把位置尺寸推下去
    --   ⇒ **用户的调整被无声地覆盖**。
    --
    --   新规则：
    --     · **运行时由脚本生成的控件**（格子等）→ 仍由脚本摆位置
    --       （它们本来就不在存档里，没有"编辑器几何"可言）。
    --     · **存档里已有的控件** → 保持编辑器里的几何，脚本不碰。
    --   `cfg.respect_editor_rect = false` 可关掉此行为（回到"布局全由代码说了算"）。
    --
    --   注意：行标/列标、头像卡另有 `apply_ruler_layout` / `apply_tray_layout`
    --   直接写位置，不受这里影响（那两条本来就是运行时重排）。
    --
    -- ★★★ 2026-09-30：`runtime_rect` 是**只影响这一处**的独立标记。
    --
    --   为什么不能复用 `instantiated`：那个标记还管着"**允不允许销毁控件**"
    --   （见隐藏分支：`instantiated[id]` 为真时会调 `DestroyClientUIControl`）。
    --   我第一版复用它 —— 结果房间名标签 / 选卡色块被当成"脚本建的"，
    --   某次渲染里它们短暂不可见 ⇒ 被判为"该隐藏" ⇒ **真销毁了** ⇒ 再也回不来
    --   （测试报"可见色块 0 块"，而单独探针在别的时点看是 3 块 ——
    --     这个"两处看到的不一样"就是销毁的证据）。
    --   ⇒ 挪到独立标记：**只跳过 `respect_editor_rect`，不碰销毁语义**。
    if self.cfg.respect_editor_rect ~= false
       and not (self.instantiated and self.instantiated[id])
       and not (self.runtime_rect and self.runtime_rect[id]) then
      -- ★ 这是**故意的空操作**（"位置归编辑器管"）⇒ 算送达，否则这个属性会被反复重发。
      return true
    end

    -- ⚠️⚠️ 2026-09-28：这一段是**事故后重建**的。
    --   我在加 ruler 漂移检测时误删了函数体，而工程没有 git、没有备份 ——
    --   只能按现有代码里的换算规则重建。**务必以模拟器/真机的实际渲染为准**。
    --
    -- 换算规则（依据：官方「位置」两套规则 + `apply_tray_layout` 里已验证可用的写法）：
    --   · `rect` 是**设计坐标**（1920×1080，**左上原点**，见 ui_controller 的 rect_of）
    --   · 引擎要的是**相对父级中心**的偏移，且 **Y 轴向上**
    --   ⇒ 先设计→画布（乘 scale），再把"左上原点"翻成"Y 向上"，最后减去父级中心
    local sc = self.cfg.scale or (5 / 6)
    -- ⚠️ 必须**取整**：规划里的画布尺寸是 `round(设计 * scale)`（例如 812 → 677），
    --   而我第一版直接留浮点（676.666…）—— 结果 `cell_geometry` 按 676.67 算格子，
    --   比规划少 1px（124.17 而不是 124），选关测试因此报红。
    --   **同一组数字在两处出现就必须用同一种取整**。
    local function R(v) return math.floor((v or 0) + 0.5) end
    local w = R((value.w or 0) * sc)
    local h = R((value.h or 0) * sc)
    local cx = R(((value.x or 0) + (value.w or 0) * 0.5) * sc)
    local cyTop = R(((value.y or 0) + (value.h or 0) * 0.5) * sc)   -- 画布坐标，从上往下
    local ch = self.cfg.canvas_h or 900
    local cy = ch - cyTop                                            -- 翻成 Y 向上

    self.rects = self.rects or {}
    self.rects[id] = { cx = cx, cy = cy, w = w, h = h }

    -- ★★ 父级中心怎么来：**从父节点自己的 `rect` 算**，而不是读"运行时已经摆过没有"。
    --
    --   为什么：`rect` 是**设计绝对坐标**，父级中心可以直接由它的 `rect` 推出 ——
    --   完全不依赖渲染顺序。而"读运行时位置"要求父级**先**被摆过，
    --   一旦顺序不巧（或父级这帧没推 rect），子级就会按画布中心算 ⇒ **整块跑到画布外**。
    --
    --   事故记录：我重建这一段时先用 `cfg.parent_of`（本工程里并不存在这个表）⇒ 取到 nil
    --   ⇒ 所有子控件都相对画布中心摆放 ⇒ **头像卡直接消失**（用户报"你把人物卡弄没了"）。
    --   父节点就在 `self.handlers[pid]` 里（`create_control` 时存下的），它自带 `rect`。
    local h_node = self.handlers and self.handlers[id] or nil
    local pid = (h_node and h_node.parent)
      or (self.cfg.parent_of and self.cfg.parent_of[id]) or nil
    local pcx, pcy = nil, nil
    local p_node = (pid ~= nil and self.handlers ~= nil) and self.handlers[pid] or nil
    if p_node ~= nil and p_node.rect ~= nil then
      local pr = p_node.rect
      pcx = R(((pr.x or 0) + (pr.w or 0) * 0.5) * sc)
      pcy = ch - R(((pr.y or 0) + (pr.h or 0) * 0.5) * sc)
    end
    -- 兜底①：父级还没落过 rect，但已经摆过运行时位置 → 用运行时中心
    if pcx == nil and pid ~= nil and self.rects[pid] ~= nil then
      pcx, pcy = self.rects[pid].cx, self.rects[pid].cy
    end
    -- 兜底②：根级控件（没有父）→ 画布中心
    if pcx == nil then
      pcx = R((self.cfg.canvas_w or 1600) * 0.5)
      pcy = R(ch * 0.5)
    end

    if ctrl.SetAnchorMin then pcall(function() ctrl:SetAnchorMin(0.5, 0.5) end) end
    if ctrl.SetAnchorMax then pcall(function() ctrl:SetAnchorMax(0.5, 0.5) end) end
    if ctrl.SetPivot     then pcall(function() ctrl:SetPivot(0.5, 0.5) end) end
    if ctrl.SetSizeDelta then pcall(function() ctrl:SetSizeDelta(w, h) end) end
    if ctrl.SetAnchoredPosition then
      pcall(function() ctrl:SetAnchoredPosition(cx - pcx, cy - pcy) end)
    end
  elseif key == "style" then
    -- 语义化样式：只做最小可感知反馈；正式外观请在编辑器里配控件视觉状态
    --
    -- ★ 已放置头像卡的着色值：`0x80FFFFFF` = **50% 透明白**。
    --   颜色在引擎里就是 **32 位整数**（真机日志 `fontColor=4294967295`），
    --   而 `Color()` 全局函数**不存在** —— 所以直接写整数，不走构造函数。
    --   `imageColor` 是**乘算着色**：乘白=不变色，乘半透明白=整体减淡 ⇒ 正是"减淡+加透明"。
    local PLACED_TINT = 2147483647
    local NORMAL_TINT = 4294967295      -- 0xFFFFFFFF：不透明白 = 还原
    -- ★★ 2026-09-28：缩放值**不再在这里写 if/elseif 链** —— 改查 `scale_of_style`。
    --
    --   为什么：原来这里设了 0.72，而 `apply_tray_layout`（头像卡重排）随后把姿态重置
    --   ⇒ **设了又被覆盖**，用户看到"已放置头像卡没有变小"。
    --   这与本工程反复出现的"同一件事两处实现"是同一类病
    --   （前面吃过：`erases` 动效、运行时上色 vs 存档静态图、自动 ✗ 的三处还原）。
    --   ⇒ 缩放表抽成**一个函数**，style 分支与重排函数共用，从根上不可能不一致。
    self._style = self._style or {}
    self._style[id] = value             -- 记住样式：重排函数要据此**重新施加**缩放
    local scale = self:scale_of_style(value)
    if scale and ctrl.SetLocalScale then ctrl:SetLocalScale(scale, scale, 1) end

    -- ★★★ 2026-09-30：**文字颜色**（线索卡的"人名标红"，见 `color_of_style` 的注释）。
    --   和缩放一样，颜色表也只定义一处 —— 避免"两个地方各写一份必然漂移"。
    local wantColor = self:color_of_style(value)
    if wantColor ~= nil and ctrl.fontColor ~= nil then
      pcall(function() ctrl.fontColor = wantColor end)
    end

    -- ★ 着色：**只有"已放置"才减淡**，其余状态一律还原成不透明白。
    --   不还原的话，取消放置后头像会一直是淡的（"调色"会粘住）。
    --   只对头像卡（`portrait*` 系列样式）做，避免影响线索/标签等其它用 style 的控件。
    if type(value) == "string" and string.sub(value, 1, 8) == "portrait" then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.imageColor ~= nil then
        local want = (value == "portrait.placed") and PLACED_TINT or NORMAL_TINT
        local okc, err = pcall(function() face.imageColor = want end)
        if not okc then
          self:warn_once("tint:" .. tostring(id), "头像卡调色失败（imageColor 可能不是整数）：" .. tostring(err))
        end
      end
    end

  elseif key == "notes" then
    local c = self:sub(id, "note")
    if c ~= nil then
      local txt = table.concat(value or {}, " ")
      if c.text ~= nil then c.text = txt end
      -- 有笔记才显示；没笔记藏起来，免得留一个空框
      if c.SetVisible then pcall(function() c:SetVisible(txt ~= "") end) end
    end

  elseif key == "x_mark" then
    local c = self:sub(id, "x")
    if c and c.SetVisible then c:SetVisible(value and true or false) end

  elseif key == "walls" or key == "doors" then
    local prefix = (key == "walls") and "wall." or "door."
    local dirs = { "up", "down", "left", "right" }
    for i = 1, #dirs do
      local c = self:sub(id, prefix .. dirs[i])
      if c and c.SetVisible then c:SetVisible((value and value[dirs[i]]) and true or false) end
    end
  end

  -- ★★★★★ 2026-10-05 **默认"送达成功"** —— 这条 `return true` 是上面那条契约的另一半：
  --   只有明确知道"没送到"的分支（`ctrl == nil`、文字无处可写、墙/门缺子控件）才返回 false，
  --   其余分支（tint / style / visible / image …）照旧一律算成功，**行为与改动前完全一致**。
  return true
end

----------------------------------------------------------------------------
-- 输入：只绑 CursorClick（双击由上层判定）
----------------------------------------------------------------------------

function Adapter:_fire(event, phase, data, src_id)
  -- ★★★★★ 2026-10-05 **收到光标事件 ⇒ 兜底隐藏重跑一次。**
  --
  --   为什么把"点击"也算成"树可能变了"：预设按钮的**状态节点**会引用子控件当外显样式
  --   （见 `Adapter:sub` 里那段官方文档引用）—— 按下/抬起会让引擎自己把某个子控件
  --   显示出来，而这件事**不经过脚本的 `set_property`**。
  --   原来靠每帧扫一遍兜住它；现在挂在输入事件上（人的手速，一帧最多几次，布尔赋值）。
  --   ⚠️ 这是"每帧扫"被去掉之后，**唯一**能兜住"引擎自己改显隐"的触发点，
  --      所以宁可多置一次位（一次 enforce ≈ 几百个节点），也不能漏。
  self._subtree_dirty = true
  if self.on_input == nil then return end
  local evt = {}
  for k, v in pairs(event) do evt[k] = v end
  evt.phase = phase
  if data and data.GetUIPos then
    local ok, x, y = pcall(function() return data:GetUIPos() end)
    if ok then evt.x, evt.y = x, y end
  end
  -- ★★★★★ 2026-10-05 **补格子坐标 `r` / `c`** —— 修「点了格子没反应」✗
  --
  --   根因（实测锁定 ✓）：界面层收事件的入口是
  --     · `ui_controller.lua:818-823`  `elseif a == "click" then self:on_cell_click(event.r, event.c)`
  --     · `ui_controller.lua:562-565`  `function Controller:on_cell_click(r, c) … core.grid[r][c]`
  --   ⇒ **界面层认格子靠的是 `event.r` / `event.c`，不是 x/y** ✗
  --   而 `_fire` 原来只做三件事：复制 `event` ✓ · 补 `phase` ✓ · 补 `x`/`y` ✓
  --   ⇒ ★ **从不补 `r`/`c`** ✗ ✓ 计划里也没有（`layout-plan.json` 实测 `"r"` / `"c"` 各 **0** 次 ✓）
  --   ⇒ 于是 `on_cell_click(nil, nil)` ⇒ `core.grid[nil]` ⇒
  --     **既不记笔记、也不放置、步数不动** ✗（模拟器实测：`8/13` 的 #2–#8 #13 + `13/13` 唯一红 ✓）
  --
  --   ★ 为什么在这里补：**`bind_input(id, node)` 本来就知道 `id`** ✓（L4405 ✓）
  --     而格子控件的命名就是 `cell.<行>.<列>` ✓ ⇒ 从 `id` 里解析出来 ✓
  --   ⚠️ **必须是数字** ✗ —— `core.grid[r][c]` 用字符串下标会拿到 nil ✗ ⇒ 用 `tonumber` ✓
  --   ⚠️ **不覆盖已有的 `r`/`c`** ✗ —— 若 `event` 自己带了（或将来引擎直接给 ✓）就以它为准 ✓
  --   ⚠️ **只认 `cell.<数字>.<数字>`** ✓ —— 其它控件（按钮/热区/线索卡 ✓）一律不碰 ✓
  if src_id ~= nil and evt.r == nil then
    local R, C = tostring(src_id):match("^cell%.(%d+)%.(%d+)$")
    if R ~= nil then
      evt.r = tonumber(R)
      evt.c = tonumber(C)
    end
  end
  self.on_input(evt)
end

----------------------------------------------------------------------------
-- 输入绑定：2D 平面操作，**同一套界面同时吃 PC 键鼠和移动端触碰**
--
-- 官方只有这几个光标事件（没有长按、没有右键）：
--   CursorDown / CursorUp / CursorClick / CursorEnter / CursorExit
--   CursorBeginDrag / CursorDrag / CursorEndDrag
--
-- 触摸屏上"点一下"同样会派发 Down→Up→Click，所以**鼠标点**和**手指点**
-- 走的是同一条路，不需要两套代码。这里额外绑 Down/Up 是为了：
--   · 自己合成**长按**（移动端比双击好按，双击还要担心系统双触缩放）
--   · 用"按下→抬起之间有没有移动"来区分"点"和"划"
--
-- 键盘（PC）用 AddKeyEventListener，属于**加分项**：
-- 取不到枚举时只是不绑定，鼠标照样能玩，不影响可用性。
----------------------------------------------------------------------------

local function make_cursor_data(x, y, press_x, press_y)
  return {
    x = x, y = y, pressX = press_x, pressY = press_y,
    GetUIPos = function() return x, y end,
    GetPressUIPos = function() return press_x, press_y end,
  }
end

-- 平台/设备：KeyboardAndMouse | Mobile | Controller | MobileController
function Adapter:device()
  if self._device ~= nil then return self._device end
  local name = "unknown"
  pcall(function()
    if game ~= nil and game.GetDevice ~= nil then
      local d = game.GetDevice()
      if d ~= nil then
        name = tostring(d.Name or d.FullName or d)
      end
    end
  end)
  self._device = name
  return name
end

-- 归一化成三种"操作档"，界面层按它决定提示文案
function Adapter:input_profile()
  local d = self:device()
  if d == "Mobile" or d == "MobileController" then return "touch" end
  if d == "Controller" then return "gamepad" end
  return "pc"        -- KeyboardAndMouse，以及拿不到设备时的兜底
end

function Adapter:bind_input(id, node)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if ctrl.AddCursorEventListener == nil then
    self:warn_once("nocursor:" .. tostring(id),
      "控件 " .. tostring(id) .. " 不支持光标事件（请用「预设按钮」或「光标检测区域」控件）")
    return
  end
  self.bound = self.bound or {}
  if self.bound[id] then return end          -- 防重复绑定
  local click = E("CursorEventType.CursorClick")
  if click == nil then
    self:warn_once("noenum", "Enum.CursorEventType.CursorClick 缺失，无法绑定点击")
    return
  end
  self.bound[id] = true

  -- ★ 绑定自检（2026-09-27）：把"这条控件绑到了什么事件"打出来。
  --   起因：真机上点 `tray.V` 三次都毫无效果，而事件链路代码看着是通的。
  --   有了这行就能直接区分两种可能：
  --     · 事件 = suspect/V  → 事件绑对了，问题在逻辑层
  --     · 事件 = click/-    → 绑的是兜底事件（fallback），根本没拿到 node.event
  if self.cfg.debug_event ~= false then
    self._bind_seen = (self._bind_seen or 0) + 1
    if self._bind_seen <= 16 and print then
      local ev = node.event
      local what = "-"
      if ev ~= nil then
        if ev.id ~= nil then what = tostring(ev.id)
        elseif ev.r ~= nil then what = tostring(ev.r) .. "," .. tostring(ev.c)
        elseif ev.mode ~= nil then what = tostring(ev.mode) end
      end
      print("[murdoku] 绑定输入 `" .. tostring(id) .. "`  事件="
        .. (ev and tostring(ev.action) or "nil") .. "/" .. what)
    end
  end

  -- ★★ 关键：**事件要现查**，不要在绑定时捕获进闭包。
  --   同一条预设按钮在不同弹窗状态下要发不同事件（指认盗窃者 → 同伙是谁），
  --   而控件只创建/绑定一次；捕获写法会让第二次点谁都还在发旧事件。
  local function live_event()
    -- ★★★★★ 2026-10-05 **事件表搬到 `self.events[规划节点键]` 之后，现查要跟着改。**
    --
    --   旧写法读 `self.handlers[id].event`（那张表兼任事件表，已于本轮拆开）。
    --   照旧写会读到一个**再也不会被更新的**创建期快照 ⇒ 点了不对（静默）。
    --
    --   ★★ **取谁：`self.event_claim[id]` = 认领这颗控件的那个规划节点（第一个写的）** ★★
    --      —— **这就是 B2 的核心一行**（用户 2026-10-05 拍板 ✓）。
    --
    --      为什么不是 `self.event_latest[id]`（"最后写的"）：一个 id 只有一个引擎控件、
    --      只有一次绑定（`create_control` 按 id 建）⇒ **只能派发一份事件** ——
    --      所以"选哪一份"就是**这颗按钮到底是什么意思**的决定。
    --      计划里 `action.back` 有两个节点：`topbar`（「返回菜单」/ `back_confirm`，先写）
    --      与 `right`（「返回列表」/ `back`，后写）。取"最后写的" ⇒ 派发 `back` ⇒
    --      **鼠标点这颗按钮直接跳列表**，而左上那颗 ↰ 图标按 `back_confirm` **先弹 ✓/✗** ✗
    --      ⇒ 同一颗按钮、两种语义，差别只取决于"点的哪一颗"（`action.back` 还是 `hex.back`）
    --      ⇒ 这是**自相矛盾**，不是设计（三条硬证据见 `Adapter.new` 里 `self.event_claim`）。
    --      取"认领者" ⇒ 派发 `back_confirm` ⇒ **点击与 ↰ 一致，都先弹 ✓/✗** ✓
    --      （`ui_controller.lua:854` 收到 `back_confirm` ⇒ `self.pending = { action = "back" }`）。
    --
    --   ⚠️ 兜底顺序**保持不变**：认领者的那一份 → 绑定时的 `node.event` → `{ action = "click" }`。
    --      （认领者还没有时 —— 例如控件刚建出来、渲染还没轮到它 —— 仍按老路兜底 ✓）
    local k = self.event_claim[id]
    local cur = nil
    if k ~= nil then cur = self.events[k] end
    return cur or node.event or { action = "click" }
  end

  ctrl:AddCursorEventListener(click, function(data)
    -- ★ 「点击到底有没有到达脚本」必须能判定。
    --
    -- 用户 2026-09-27 报告"点击无反馈"，而当时日志里**完全看不出点击有没有到达脚本** ——
    -- 排查死角。这里在搭界面阶段把前几次点击打出来：
    --   · **看到**这行 → 点击到达了脚本，问题在后面（笔记/文本渲染、或游戏逻辑）
    --   · **看不到**这行 → 点击根本没到 → 查中间容器的
    --     「屏蔽区域内点击事件穿透」（`disableCursorEventPassthrough`）
    if self.cfg.debug_click ~= false then
      self._click_seen = (self._click_seen or 0) + 1
      if self._click_seen <= 8 and print then
        -- ★ 连**点击坐标**一起打（`CursorEventData:GetUIPos()`，官方：
        --   「以画布左下角为原点，获取当前屏幕 UI 坐标」）。
        --   为什么必须打：用户 2026-09-27 05:59 点的是"第2行第2列"，
        --   而事件报的是 `cell.2.4` —— 差了 2 列。有了坐标就能直接判断
        --   是"点错了"还是"命中矩形和画出来的位置不一致"。
        local xy = ""
        pcall(function()
          if data ~= nil and data.GetUIPos ~= nil then
            local x, y = data:GetUIPos()
            if type(x) == "number" then
              xy = string.format("  点击坐标=(%.0f, %.0f)", x, y)
            end
          end
        end)
        print("[murdoku] 收到点击 → 控件 `" .. tostring(id) .. "`（第 "
          .. self._click_seen .. " 次）" .. xy
          -- ★ 把**实际派发的事件**一起打（2026-09-27）：光知道"点击到了"不够，
          --   还要知道"派发的是什么事件" —— 因为 live_event() 有兜底
          --   `{action="click"}`，一旦没拿到 node.event 就会静默变成格子点击。
          .. "  事件=" .. tostring((live_event() or {}).action or "nil"))
      elseif self._click_seen == 9 and print then
        print("[murdoku] （点击日志到此为止，后面不再刷；cfg.debug_click = false 可关）")
      end
    end
    -- ★ 2026-10-05 **把控件 id 传下去** ✓ —— 格子点击要靠它解析出 `r`/`c`（见 `_fire` 里那段）✓
    --   `id` 是 `bind_input(id, node)` 的形参 ✓ 就在本闭包作用域里 ✓ 不需要额外查表 ✓
    self:_fire(live_event(), "click", data, id)
  end)

  -- 按下 / 抬起：界面层据此自己合成"长按"
  --
  -- ★★★★★ 2026-10-05 **必须把 `id` 一起传下去** ✗ —— 否则**长按抬起会崩** ✓
  --
  --   与 `click`（上面那条）是**同一个病**：界面层认格子靠的是 `event.r` / `event.c`
  --   （`ui_controller.lua:810/814` → `on_cell_down/on_cell_up(event.r, event.c, …)`），
  --   而 `_fire` 里**只有拿到 `src_id` 才**从 `cell.<行>.<列>` 解析出 `r`/`c` ✓。
  --
  --   不传 `id` 的实测反事实：`live_event()` 落到兜底 `{ action = "click" }` 时，
  --   down/up 两边的 `_press` 都成了 `{ r = nil, c = nil }` ⇒ `on_cell_down` 存进去、
  --   `on_cell_up` 取出来比 `dt` ⇒ **崩**：
  --     `murdoku_core.lua:1917: attempt to compare nil with number`
  --   （`_press.r`/`_press.c` 是 nil，长按判定那一步拿 nil 去比数字。）
  --
  --   `id` 就在 `bind_input(id, node)` 的形参作用域里 ✓（同一闭包，见上面 `click` 那条注释 ✓）。
  local down = E("CursorEventType.CursorDown")
  if down ~= nil then
    ctrl:AddCursorEventListener(down, function(data)
      self:_fire(live_event(), "down", data, id)
    end)
  end
  local up = E("CursorEventType.CursorUp")
  if up ~= nil then
    ctrl:AddCursorEventListener(up, function(data)
      self:_fire(live_event(), "up", data, id)
    end)
  end

  -- 拖动：按住期间移动。用它**当场**取消待判定的长按，不用等到抬起 ——
  -- 移动端上"按住想微调、结果落子了"就是这条救回来的。
  --
  -- ⚠️ 只绑 CursorDrag，**不绑 CursorBeginDrag**：
  --    官方枚举里确实有 BeginDrag / Drag / EndDrag 三个，但 BeginDrag 的语义是
  --    "开始可能成为拖动"，有些实现**一按下就发**。把它接成"取消长按"会让
  --    真机上长按彻底失效（而且模拟器发不出 drag，这个错查不出来）。
  --    CursorDrag 才是"已经在移动"，安全。EndDrag 与 Up 重复，不需要。
  --
  -- 界面层还会再比一次坐标位移（见 Controller:on_cell_drag），所以就算某个实现
  -- 在同一点狂发 Drag，也不会误取消。
  --
  -- ★★★★★ 2026-10-05 **`drag` 也要传 `id`** ✓ —— 和 down/up 同一条理由 ✓。
  --
  --   不传会**静默**丢掉这个功能（不崩，但等于没做 ✓）：
  --     `_fire` 拿不到 `src_id` ⇒ `evt.r`/`evt.c` 恒为 nil ✗
  --     ⇒ `on_input`（`ui_controller.lua:818`）转给 `on_cell_drag(nil, nil, x, y)` ✗
  --     ⇒ 函数第一句 `local p = self._press` 之后、`p.r ~= r or p.c ~= c` 那一比就
  --       **直接 return false** ⇒ 位移容差那几行**永远跑不到** ✗
  --     ⇒ 长按期间手抖/滑动**不会取消** ⇒ 移动端"按住想微调、结果落子了"又回来了 ✗
  --   （上面那段注释写的就是"这条救回来的"那个功能 —— 不传 id 等于把它悄悄删掉。）
  --   ⇒ ★ 传 `id` 之后 `r`/`c` 才解析得出来，位移判断才真的生效 ✓
  local drag = E("CursorEventType.CursorDrag")
  if drag ~= nil then
    ctrl:AddCursorEventListener(drag, function(data)
      self:_fire(live_event(), "drag", data, id)
    end)
  end
end

-- PC 键盘快捷键（可选）。绑定失败就算了，不影响鼠标/触摸。
--
-- ⚠️ 键位监听是**控件**的接口，不是 `script` 的：
--     `ctrl:AddKeyEventListener(key, cb)`（`RemoveKeyEventListener` / `RemoveKeyEventListeners` 同族）。
--     一开始我绑到 `script` 上了，结果永远绑不上（模拟器实测：
--     控件的方法表里有 AddKeyEventListener，Script 的方法表里没有）。
--     现在绑在 `cfg.key_control`（默认 "root"）上。
--
-- 键名的取法有三种可能（不同版本实现不一样），逐个试：
--   ① Enum.KeyboardKeyCode.<Name>   ② Enum.KeyCode.<Name>   ③ 直接传字符串
-- 一个都取不到就用字符串兜底；控件不支持就整体跳过（不是故障，记 info）。
--
-- 参数可以是：
--   · 数组 { "Up", "Space", "Return", ... }      —— 键名就是全部信息
--   · 或表 { Up = { action = "..." }, ... }      —— 需要为每个键带不同事件时用
function Adapter:bind_keys(spec, control_id)
  self.keymap = self.keymap or {}
  if game == nil then return 0, "没有 game 环境" end

  -- ── 候选控件：可以给一个名字，也可以给一串 ──────────────────────────────
  --
  -- ★ 2026-09-26 13:12 真机日志：补绑**还是**失败，而旧代码两种病因
  --   （"控件找不到" / "控件不支持按键事件"）打的是**同一句**被 warn_once 去重过的
  --   日志，所以第二次尝试完全静默 —— 只知道"没绑上"，不知道为什么。
  --
  --   而且真机上「容器节点到底支不支持 AddKeyEventListener」我们**没验过**
  --   （模拟器里所有控件都有这个方法，验不出来）。所以现在列一串候选：
  --   找到第一个**既能找到、又支持按键事件**的控件就用它。
  local names = {}
  local src = control_id or self.cfg.key_control or "root"
  if type(src) == "table" then
    for i = 1, #src do names[#names + 1] = tostring(src[i]) end
  else
    names[1] = tostring(src)
  end
  local extra = self.cfg.key_control_fallbacks
  if type(extra) == "table" then
    for i = 1, #extra do names[#names + 1] = tostring(extra[i]) end
  end

  local ctrl, used, why = nil, nil, {}
  for i = 1, #names do
    local c = self:find(names[i])
    if c == nil then
      why[#why + 1] = names[i] .. "=找不到"
    elseif c.AddKeyEventListener == nil then
      why[#why + 1] = names[i] .. "=不支持按键事件"
    else
      ctrl, used = c, names[i]
      break
    end
  end

  if ctrl == nil then
    -- **不在这里打印**：OnInit 阶段树是空的，绑不上属正常，在这里报就是误报
    -- （和 §9.2 那个"空树报成故障"是同一类错误）。
    -- 把原因返回给调用方，由它按阶段决定话术（entry 里 OnInit 说"稍后补绑"）。
    return 0, "候选控件都不中用：" .. table.concat(why, "；")
  end

  local list = {}
  if type(spec) == "table" then
    if #spec > 0 then
      for i = 1, #spec do list[#list + 1] = { tostring(spec[i]), {} } end
    else
      for k, v in pairs(spec) do list[#list + 1] = { tostring(k), v or {} } end
    end
  end

  local n, failed, unresolved = 0, 0, {}
  for i = 1, #list do
    local key_name, event = list[i][1], list[i][2]
    if self.keymap[key_name] == nil then
      -- ★★ 2026-09-26 真机日志查出来的**真 bug**：
      --   官方签名是 `AddKeyEventListener(eventType, callback)`，第一个参数是
      --   **`Enum.KeyEventType` 事件类型**（例如 `KeyboardCraftspersonKey1Down`
      --   = "键鼠：奇匠按键1（按下）"），**不是键码**。
      --   旧实现传的是 `Enum.KeyboardKeyCode.<名字>` / `Enum.KeyCode.<名字>` /
      --   裸字符串 —— 三者都不是合法的 eventType，于是**30 个调用全部抛错**，
      --   日志表现成"绑在 root 上，成功 0 个，失败 30 个"。
      --
      --   而且**取不到枚举时绝不能硬绑**（拿字符串当枚举必然抛），
      --   所以这里单独计一个 unresolved，并把它报出来。
      local et = E("KeyEventType." .. key_name)
      if et == nil then
        unresolved[#unresolved + 1] = key_name
      else
        -- ★ 2026-09-27：真机日志显示 **24/24 绑定成功，但按了 15 个键一行回调都没有**。
        --   为排除"看着像枚举、其实是字符串"（拿字符串硬绑也可能不抛错），
        --   把解析结果的**类型与值**打出来：真枚举应是 userdata/table，不是 string。
        if self.cfg.debug_key and print then
          self._key_dbg = (self._key_dbg or 0) + 1
          if self._key_dbg <= 4 then
            print("[murdoku] KeyEventType 解析：" .. key_name
              .. " -> type=" .. type(et) .. " 值=" .. tostring(et))
          end
        end
        local ok = pcall(function()
          ctrl:AddKeyEventListener(et, function()
            -- ★ 物理键映射验证用的日志（`docs/未验证清单.md` 第 1 条）：
            --   官方只给了「奇匠按键36 = ↑」这种说法，而**物理键到底触发哪个事件**
            --   只有真机能验，而且「奇匠按键」是可被玩家重映射的槽位。
            --   所以把**实际收到的键名**打出来 —— 这样验证就变成"按键 + 读日志"，
            --   不用靠"看棋盘上有没有高亮框"这种主观判断。
            if self.cfg.debug_key then
              print("[murdoku] 按键事件 → " .. tostring(key_name))
            end
            -- ★★★ 2026-09-30：**输入隔离的自检结论** —— 只在**第一次**按键时打一行，
            --   而且**不依赖 debug_key**（这条是验收结论，不是调试信息）。
            --
            --   为什么需要它：目标 ⑦ 要回答的是
            --   「给容器设了 `disableKeyEventPassthrough = true` 之后，
            --     脚本自己的 `AddKeyEventListener` 还收不收得到按键？」
            --   这个问题**只有真机能回答**（模拟器里这些字段根本不生效）。
            --   ⇒ 把验证做成"按一个快捷键 + 看日志"，而不是靠主观判断：
            --     看到这一行 ⇒ 屏蔽**没有**影响脚本自身的监听（最坏情况被排除）；
            --     看不到     ⇒ 屏蔽把键盘也挡住了 ⇒ 去掉 `main.lua` 里的 `seal_containers`，
            --                  或缩小到只用 `disableCursorEventPassthrough`（都是一行）。
            if not self._key_first_seen then
              self._key_first_seen = true
              if print then
                print("[murdoku] ✅ 键盘事件仍能收到（第一个键：" .. tostring(key_name)
                  .. "）—— 「屏蔽按键事件穿透」没有影响脚本自身的监听，目标⑦的疑问到此处排除。")
              end
            end
            if self.on_input ~= nil then
              local evt = {}
              for k, v in pairs(event) do evt[k] = v end
              evt.phase = "key"
              evt.key = key_name      -- 界面层按 `Enum.KeyEventType` 的**名字**分派
              self.on_input(evt)
            end
            -- ★★★★★ 2026-10-02 **不能返回 `true`**。
            --
            --   官方文档（docs/api-cache/mhtakr07vej4.txt:1379）：
            --     「AddKeyEventListener(eventType, callback) …… 回调返回 boolean；
            --       **同一个容器中，如果交互按键事件被 lua 回调响应，并标记为已处理，
            --       容器内的其他按键不会也响应此次按键事件**」
            --   ⇒ 返回 `true` = **把这次按键标记成"已处理"** ⇒ 后面的人收不到。
            --   而这里的监听绑在 **`root`** 上（日志：`绑在 root 上，成功 24 个`）——
            --   `root` 是**所有 UI 的祖先** ⇒ 它标记已处理之后，**游戏自己的功能收不到这个键**
            --   （用户实测：**原神自带的对话框按 Enter 打不开**，而且**首页就不行**）。
            --
            --   ⇒ 改成 `return false`：**"我没处理，请继续传"**。
            --     返回值只表示"是否已处理"，**不影响脚本自己收到事件**
            --     （日志里「✅ 键盘事件仍能收到」照样会出现）。
            return false
          end)
        end)
        if ok then n = n + 1 else failed = failed + 1 end
      end
    end
    self.keymap[key_name] = event
  end

  local note = "绑在 " .. tostring(used) .. " 上，成功 " .. n .. " 个"
  if failed > 0 then note = note .. "，失败 " .. failed .. " 个" end
  if #unresolved > 0 then
    note = note .. "；" .. #unresolved .. " 个键名取不到 Enum.KeyEventType："
      .. table.concat(unresolved, ", ")
  end
  return n, note
end

-- 键盘是否真的可用（要么绑成功过，要么收到过键盘事件）
function Adapter:keyboard_ready()
  if self.keymap ~= nil and next(self.keymap) ~= nil then return true end
  return false
end

----------------------------------------------------------------------------
-- 动效（TweenSequence 关键帧）+ 音效
--
-- 官方接口（已按实现核对）：
--   game.Tween(控件, {字段=值,...}, 时长) → Tween
--        :SetEase(Enum.EaseType.X) :SetRelative(bool) :SetLoops(n)
--        :Play() :Pause() :Resume() :Restart() :Complete() :Kill(bool)
--        :SetOnComplete(fn) :SetOnStepComplete(fn)
--   game.TweenSequence() → Seq
--        :Append(tween) :Join(tween) :AppendInterval(秒) :AppendCallback(fn)
--        :Insert(秒, tween) :InsertCallback(秒, fn) :Play() …
--
-- **可动的字段只有这些**（真机实现里的白名单，写别的没用）：
--   anchoredPositionX/Y、sizeDeltaX/Y、anchorMinX/Y、anchorMaxX/Y、
--   pivotX/Y、localScaleX/Y/Z、localRotationX/Y/Z
--
-- 所以：
--   · 缩放类 → localScaleX/Y
--   · 抖动类 → anchoredPositionX/Y（要**先记下基准值**，用绝对值做关键帧，
--     不能用 SetRelative 连续叠，否则一轮下来会累积偏移）
--   · 旋转类 → localRotationZ
----------------------------------------------------------------------------

-- 每个语义动效 = 一条关键帧时间线。
--   dur  总时长（秒）
--   ease Enum.EaseType 的名字（取不到就退回 Linear）
--   ch   通道：scale（默认）| pos_x | rot
--   keys { {t, v}, ... }，t 是 0..1 的归一化时间，v 是**绝对目标值**
--        （scale 的 1.0 = 原始大小；pos_x 的 0 = 原始位置）
local EFFECTS = {
  -- 落子：从小弹到略大再收回，最有"啪"的一声感
  pop_tile     = { dur = 0.26, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.62 }, { 0.55, 1.06 }, { 1.00, 1.00 } } },
  -- 铅笔笔记：轻轻一跳
  note_pop     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.90 }, { 1.00, 1.00 } } },
  -- X 标记 / 提示：脉冲
  pulse        = { dur = 0.18, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.50, 1.14 }, { 1.00, 1.00 } } },
  -- 选中头像卡：放大 + 一点点光晕感（用缩放近似）
  sel_pop_glow = { dur = 0.30, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.45, 1.12 }, { 0.70, 1.03 }, { 1.00, 1.00 } } },
  -- 撤销：闪一下
  undo_flash   = { dur = 0.16, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.05 }, { 1.00, 1.00 } } },
  -- 提交：顶一下
  submit_nudge = { dur = 0.28, ease = "OutCubic", ch = "scale",
                   keys = { { 0.00, 1.000 }, { 0.40, 1.035 }, { 1.00, 1.000 } } },
  -- 线索卡刷出来
  clue_box_pop = { dur = 0.22, ease = "OutBack",  ch = "scale",
                   keys = { { 0.00, 0.82 }, { 0.60, 1.03 }, { 1.00, 1.00 } } },
  -- 破案：整块闪一下
  solved_flash = { dur = 0.36, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 1.00 }, { 0.40, 1.12 }, { 1.00, 1.00 } } },
  -- 擦除：缩到 0
  vanish       = { dur = 0.20, ease = "InQuad",   ch = "scale",
                   keys = { { 0.00, 1.00 }, { 1.00, 0.00 } } },
  -- 区域墙：轻微一缩（表示"这里隔断"）
  roomwall     = { dur = 0.14, ease = "OutQuad",  ch = "scale",
                   keys = { { 0.00, 0.98 }, { 1.00, 1.00 } } },
  -- 拒绝 / 错误：左右摇头
  shake        = { dur = 0.30, ease = "Linear",   ch = "pos_x",
                   keys = { { 0.00, 0 }, { 0.20, -8 }, { 0.45, 8 },
                            { 0.70, -5 }, { 1.00, 0 } } },
  -- 受害者头像从下往上"顶"出来（结算/揭示用）
  -- ⚠️ 这条曾经是**空转**的：ui_controller 里 M.EFFECTS.VICTIM = "portrait_slide_up"，
  --    但 EFFECTS 表里没有同名条目 → play_effect 第一行 spec==nil 就 return，
  --    不动也不报错。补上条目，同时给时间线加了 pos_y 通道（原先只有 pos_x）。
  portrait_slide_up = { dur = 0.34, ease = "OutBack", ch = "pos_y",
                   keys = { { 0.00, -34 }, { 0.70, 4 }, { 1.00, 0 } } },
}

-- 语义动效 → 音频 id。
-- ⚠️ 这些 id 是**占位**：音频 id 得在编辑器里查（音效资源），
--   查到之后直接改这张表即可，不用动别处。留 nil = 该动作不发声。
M.SOUNDS = {
  pop_tile     = nil,
  note_pop     = nil,
  pulse        = nil,
  sel_pop_glow = nil,
  undo_flash   = nil,
  submit_nudge = nil,
  clue_box_pop = nil,
  solved_flash = nil,
  vanish       = nil,
  roomwall     = nil,
  shake        = nil,
  portrait_slide_up = nil,
}

function Adapter:ease_of(name)
  if name == nil then return nil end
  local e = E("EaseType." .. tostring(name))
  if e == nil then e = E("EaseType.Linear") end
  return e
end

-- 读一个控件当前的缩放/位置，作为动效的基准
local function read_pose(ctrl)
  local pose = { sx = 1, sy = 1, ax = 0, ay = 0, rz = 0 }
  if ctrl == nil then return pose end
  pcall(function() if ctrl.localScaleX then pose.sx = ctrl.localScaleX end end)
  pcall(function() if ctrl.localScaleY then pose.sy = ctrl.localScaleY end end)
  pcall(function() if ctrl.anchoredPositionX then pose.ax = ctrl.anchoredPositionX end end)
  pcall(function() if ctrl.anchoredPositionY then pose.ay = ctrl.anchoredPositionY end end)
  pcall(function() if ctrl.localRotationZ then pose.rz = ctrl.localRotationZ end end)
  return pose
end

-- 把一条关键帧时间线变成一串 Tween，接进 Sequence
local function build_timeline(adapter, ctrl, spec, base)
  local keys = spec.keys
  local n = #keys
  if n < 2 then return {} end
  local ease = adapter:ease_of(spec.ease)
  local ch = spec.ch or "scale"
  local list = {}
  for i = 1, n - 1 do
    local t0, v0 = keys[i][1], keys[i][2]
    local t1, v1 = keys[i + 1][1], keys[i + 1][2]
    local seg = (t1 - t0) * spec.dur
    if seg <= 0 then seg = 0.01 end
    local props
    if ch == "pos_x" then
      props = { anchoredPositionX = base.ax + v1 }
    elseif ch == "pos_y" then
      -- 画布空间 Y 向上，v1 为"相对基准位置的纵向偏移"，正数 = 往上
      props = { anchoredPositionY = base.ay + v1 }
    elseif ch == "rot" then
      props = { localRotationZ = base.rz + v1 }
    else
      props = { localScaleX = v1, localScaleY = v1 }
    end
    list[#list + 1] = { props = props, seg = seg, ease = ease }
  end
  return list
end

function Adapter:play_effect(id, effect_name, params)
  local ctrl = self:find(id)
  if ctrl == nil then return end
  if game == nil or game.Tween == nil then return end
  local spec = EFFECTS[effect_name]
  if spec == nil then
    -- 不要静默返回：语义名写错或漏配时必须看得出来。
    -- portrait_slide_up 就是这么"空转"了很久 —— 界面层在调、适配器当没听见。
    self:warn_once("nomotion:" .. tostring(effect_name),
      "没有这条动效定义：" .. tostring(effect_name)
      .. "（核对 EFFECTS 表与 ui_controller 里 M.EFFECTS 的名字）")
    return
  end

  local base = read_pose(ctrl)
  local segs = build_timeline(self, ctrl, spec, base)

  -- ① 优先用 TweenSequence：关键帧**按顺序**播（旧实现是同时起 3 个 tween，全叠在一起）
  local ok = pcall(function()
    local seq = game.TweenSequence and game.TweenSequence()
    if seq == nil or seq.Append == nil then error("no sequence") end
    local added = 0
    for i = 1, #segs do
      local t = game.Tween(ctrl, segs[i].props, segs[i].seg)
      if t ~= nil then
        if t.SetEase and segs[i].ease then pcall(function() t:SetEase(segs[i].ease) end) end
        seq:Append(t)
        added = added + 1
      end
    end
    if added == 0 then error("no tween") end
    seq:Play()
    -- 动完把姿态还原（vanish 那种会缩到 0，不还原下次就"消失"了）
    if seq.SetOnComplete then
      pcall(function()
        seq:SetOnComplete(function()
          pcall(function()
            ctrl.localScaleX, ctrl.localScaleY = base.sx, base.sy
            ctrl.anchoredPositionX, ctrl.anchoredPositionY = base.ax, base.ay
            ctrl.localRotationZ = base.rz
          end)
        end)
      end)
    end
  end)

  -- ② 退化路径：没有 TweenSequence 就只播"最像"的那一段（至少有个反馈）
  if not ok and #segs > 0 then
    local pick = segs[1]
    for i = 1, #segs do
      if segs[i].props.localScaleX and segs[i].props.localScaleX ~= 1 then pick = segs[i] end
    end
    pcall(function()
      local t = game.Tween(ctrl, pick.props, pick.seg)
      if t ~= nil then
        if t.SetEase and pick.ease then pcall(function() t:SetEase(pick.ease) end) end
        t:Play()
      end
    end)
  end

  -- ③ 音效：语义动效名 → 音频 id（M.SOUNDS 里配，没配就不响）
  local aid = self.cfg.sounds and self.cfg.sounds[effect_name]
  if aid == nil and M.SOUNDS then aid = M.SOUNDS[effect_name] end
  if aid ~= nil then self:play_audio(aid) end
end

----------------------------------------------------------------------------
-- 计时器（没有 os 库，全部靠 OnUpdate 的 dt 累加）
----------------------------------------------------------------------------

function Adapter:now() return self.clock end

function Adapter:after(seconds, fn)
  local h = { at = self.clock + (seconds or 0), fn = fn }
  self.timers[#self.timers + 1] = h
  return h
end

function Adapter:cancel(handle)
  for i = 1, #self.timers do
    if self.timers[i] == handle then table.remove(self.timers, i) return true end
  end
  return false
end

-- 由客户端 OnUpdate(dt) 驱动
-- ★★★★ 2026-10-02 **兜底：把"被隐藏的控件"的整棵子树也压下去。**
--
--   真机排行榜证明：`face` / `content`（格子模板自带的子控件）在主页和选关页上
--   **依然可见** —— 它们铺在棋盘位置上，而 `cell.*` 自己绑了点击
--   ⇒ 射线被格子接走 ⇒ 选关卡片点不到 ⇒ 用户报"点不动"。
--
--   为什么不能只靠 visible 分支里的递归：渲染**只在属性值变化时**下发
--   （`same_value` 缓存），`cell.1.1` 的 visible=false 只在第一帧下发过一次，
--   而格子的子控件是模板**之后**才实例化出来的 —— 那一脚没赶上。
--   ⇒ 扫一遍"被标记为隐藏的控件"，幂等地把子树压下去。
--
-- ★★★★★ 2026-10-05 **它不再由 `on_tick` 每帧调用** —— 改成"树可能变了"才跑一次
--   （`self._subtree_dirty`，触发点见 `on_tick` 里那段注释）。
--   本函数自己负责把欠账标记清掉：**不管谁调它**（`on_tick` / 诊断 / 测试），
--   跑完这一趟账就算还了，不会再被下一帧重复触发。
function Adapter:enforce_hidden_subtrees()
  self._subtree_dirty = false
  local hid = self._hidden_ids
  if hid == nil then return end
  for id in pairs(hid) do
    if true then   -- ★ 对所有"被隐藏的控件"都兜底（原来只对 cell. 生效，范围开小了）
      local c = self:find(id)
      if c ~= nil then
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              pcall(function() k:SetVisible(false) end)
              local kk = nil
              pcall(function() kk = k:GetChildren() end)
              if type(kk) == "table" then
                for j = 1, math.min(#kk, 32) do
                  if kk[j] ~= nil and kk[j].SetVisible then
                    pcall(function() kk[j]:SetVisible(false) end)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  local due = {}
  for i = #self.timers, 1, -1 do
    if self.timers[i].at <= self.clock then
      due[#due + 1] = self.timers[i]
      table.remove(self.timers, i)
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
  -- ★★★★★ 2026-10-05 **兜底隐藏改成"事件驱动"，不再每帧扫一遍。**
  --
  --   改之前（每帧无条件跑）：`tests/grid_cost.lua` 量到每一帧都要
  --     · 关卡内：`enforce_hidden_subtrees` 本身 39 次 `find` + 78 个 `GetChildren`；
  --     · 选关页 60 帧：`SetVisible` 15,660 次（**261 次/帧**）、`GetChildren` 6186 次/帧。
  --   而这一趟在所查的状态**没有任何变化**时是纯白跑 —— 它做的事是幂等的
  --   （把"已知该隐藏的容器"的子控件再压一次 false）。
  --   ⇒ 只在**树真的可能变了**的时候跑一次；触发点见 `_subtree_dirty` 的**五处**写法：
  --       · 脚本改了某个控件的 visible（`set_property` 的 visible 分支）
  --       · 切屏 / 换关 / 网格视窗 RefreshItems（`ui_controller` 调 `invalidate_lookups`）
  --       · 新建 / 销毁控件（`create_control` / `destroy_control`）
  --       · 收到光标事件（`_fire`：预设按钮的状态切换可能让引擎自己把子控件显示出来）
  --       · 「本该隐藏的名字」刚刚才被搜到（`_note_lookup_hit`，原来靠每帧扫才发现）
  --   安全性：它防的是"隐藏容器后来才实例化出来的子控件仍然可见"——这些子控件
  --   要么来自我们自己的实例化（create_control 触发），要么来自引擎在 RefreshItems
  --   里实例化列表项（sync_clue_grid 触发），要么来自引擎的状态切换（_fire 触发）。
  --   另外 `find` 一搜到"该隐藏的名字"就置位（`_note_lookup_hit`）—— 兜底不会漏。
  if self._subtree_dirty then
    pcall(function() self:enforce_hidden_subtrees() end)
  end
  return self.clock
end

----------------------------------------------------------------------------
-- 本地状态 / 存档
--   客户端脚本没有本地持久化接口；跨场景只能走 信号 → 服务器 → 局内存档
----------------------------------------------------------------------------

function Adapter:state(key, value)
  if value ~= nil then
    self.state[key] = value
    return value
  end
  local v = self.state[key]
  if v == nil and script and script.GetParam then
    v = script:GetParam(key)          -- 退回到编辑器里配置的脚本变量
  end
  return v
end

function Adapter:_save_params(value)
  if type(value) ~= "table" then return { tostring(value) } end
  return {
    tostring(value.level_id or ""),
    tostring(value.state_code or ""),
    tonumber(value.moves) or 0,
    tonumber(value.elapsed) or 0,
    value.solved and true or false,
  }
end

function Adapter:save(key, value)
  self.state[key] = value
  self:signal_emit(self.signals.SAVE, self:_save_params(value))
  return true
end

function Adapter:load(key)
  return self.state[key]
end

----------------------------------------------------------------------------
-- 信号
----------------------------------------------------------------------------

function Adapter:signal_emit(name, params)
  if game == nil or game.ServerSignal == nil then return false end
  local sig = game.ServerSignal(name)
  if sig == nil then return false end
  params = params or {}
  for i = 1, #params do
    local v = params[i]
    local tv = type(v)
    if tv == "number" then
      if v == math.floor(v) then sig:AddInt(v) else sig:AddFloat(v) end
    elseif tv == "string" then
      sig:AddString(v)
    elseif tv == "boolean" then
      sig:AddBool(v)
    else
      sig:AddString(tostring(v))
    end
  end
  sig:SendSignal()
  return true
end

function Adapter:signal_on(name, handler)
  if script == nil or script.RegisterServerSignalHandler == nil then return false end
  local schema = M.SIGNAL_SCHEMA[name]
  script:RegisterServerSignalHandler(name, function(sigName, params)
    local payload
    if schema and params then
      payload = {}
      for i = 1, #schema do payload[schema[i]] = params[i] end
    else
      payload = params or {}
    end
    handler(payload)
  end)
  return true
end

----------------------------------------------------------------------------
-- 其他
----------------------------------------------------------------------------

function Adapter:random_int(a, b)
  a, b = a or 1, b or 1
  if b < a then a, b = b, a end
  if math.random == nil then return a end
  return a + math.random(0, b - a)
end

function Adapter:play_audio(audio_id)
  if game and game.PlayAudio2D then return game.PlayAudio2D(audio_id) end
  return nil
end

function Adapter:get_text(text_map_id)
  if game and game.GetText then return game.GetText(text_map_id) end
  return tostring(text_map_id)
end

----------------------------------------------------------------------------
-- 运行时能力自检
----------------------------------------------------------------------------

function M.capabilities()
  local has_game = (type(game) == "table")
  local has_script = (type(script) == "table")
  local rows, missing = {}, {}

  local function check(label, ok)
    rows[#rows + 1] = string.format("%-36s %s", label, ok and "OK" or "缺失")
    if not ok then missing[#missing + 1] = label end
  end

  check("game 全局表", has_game)
  check("game.GetClientUIRoots", has_game and type(game.GetClientUIRoots) == "function")
  check("game.FindClientUIRoot", has_game and type(game.FindClientUIRoot) == "function")
  check("game.GetClientUIControl", has_game and type(game.GetClientUIControl) == "function")
  check("game.InstantiateClientUIControl", has_game and type(game.InstantiateClientUIControl) == "function")
  check("game.Tween", has_game and type(game.Tween) == "function")
  check("game.TweenSequence", has_game and type(game.TweenSequence) == "function")
  check("game.ServerSignal", has_game and type(game.ServerSignal) == "function")
  check("game.PlayAudio2D", has_game and type(game.PlayAudio2D) == "function")
  check("game.GetText", has_game and type(game.GetText) == "function")
  check("game.GetUICanvasSize", has_game and type(game.GetUICanvasSize) == "function")
  check("Enum.CursorEventType.CursorClick", E("CursorEventType.CursorClick") ~= nil)
  check("Enum.ImageSource", E("ImageSource") ~= nil)
  check("script（当前脚本实例）", has_script)
  check("script:RegisterServerSignalHandler", has_script and type(script.RegisterServerSignalHandler) == "function")
  check("script:GetParam", has_script and type(script.GetParam) == "function")
  check("script:EnableUpdate", has_script and type(script.EnableUpdate) == "function")

  local text = "千星适配层运行时能力自检：\n" .. table.concat(rows, "\n")
  if #missing > 0 then text = text .. "\n\n缺失项：" .. table.concat(missing, "、") end
  return text, missing
end

-- ★★ 2026-09-28：`apply_button_labels` **放到文件最末尾**重新定义。
--
--   为什么搬：原来它定义在中段，语法上看是顶层，但实测
--   `M.Adapter.apply_button_labels == nil`（而同一位置的 `set_property` 存在）——
--   说明它被包在了某个 `do`/`local function` 里，**永远不会被赋值到 Adapter 上**。
--   放到 `return M` 前一行，**不可能再有嵌套**。
--
--   ⚠️ 现在它**没有调用方**（main.lua 走已验证的 `set_property` 路径），
--      保留它只为将来需要"批量重写按钮文字 + 读回校验"时有个现成入口。
function Adapter:apply_button_labels(labels)
  if labels == nil or print == nil then return 0 end
  local okN, miss, bad, shown = 0, 0, 0, 0
  local ids = {}
  for id in pairs(labels) do ids[#ids + 1] = id end
  table.sort(ids)
  for i = 1, #ids do
    local id, want = ids[i], labels[ids[i]]
    if type(want) == "string" and want ~= "" then
      local lb = nil
      pcall(function() lb = self:sub(id, "label") end)
      if lb == nil then
        miss = miss + 1
      else
        local wrote = pcall(function() lb.text = want end)
        local back = nil
        pcall(function() back = lb.text end)
        if wrote and back == want then okN = okN + 1 else bad = bad + 1 end
        if shown < 8 then
          print(string.format("  %s：想要 %q → 读回 %s", id, want, tostring(back)))
          shown = shown + 1
        end
      end
    end
  end
  print(string.format("[murdoku] 按钮文字：成功 %d，读回不一致 %d，找不到 label %d", okN, bad, miss))
  return okN
end

return M
