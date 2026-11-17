
local calls = {}
local gp = { SetAnchoredPosition=function(self,x,y) calls[#calls+1]={x,y} end }
local function help_visible(c, v) end
local function run(screen)
        -- ★ 687：art657.grid.reuse 一套 48 层被 home / game 两屏共享。680 为让关卡内
        --   网格纸跟随棋盘下移，把全部子层各 -30 ⇒ 首页被连带额外下移（656 设计位 -5 → 686 -45.5）。
        --   静态层保持不动（game 屏位置不变），只给 home/select 的父容器 +40.5 把首页抬回设计位；
        --   game 分支 (105,46) 逐字不动 ⇒ 两处真正分开调整。
        local dx, dy = 0, 40.5
        if screen == "game" then dx, dy = 105, 46 end
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
end
run("home"); run("game"); run("home")
for i = 1, #calls do print(string.format('%d %.1f %.1f', i, calls[i][1], calls[i][2])) end
