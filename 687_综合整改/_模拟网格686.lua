
local calls = {}
local gp = { SetAnchoredPosition=function(self,x,y) calls[#calls+1]={x,y} end }
local function help_visible(c, v) end
local function run(screen)
        local dx, dy = 0, 0
        if screen == "game" then dx, dy = 105, 46 end
        pcall(function() gp:SetAnchoredPosition(dx, dy) end)
end
run("home"); run("game"); run("home")
for i = 1, #calls do print(string.format('%d %.1f %.1f', i, calls[i][1], calls[i][2])) end
