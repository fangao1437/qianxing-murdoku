local P = "C:\\Users\\18182\\AppData\\LocalLow\\miHoYo\\原神\\BeyondLocal\\153793556\\Beyond_Local_Save_Level\\1073742003\\external_lua_file\\client_script.lua"
print("路径长度 = " .. tostring(#P))
print("路径内容 = " .. P)
local fh, err = io.open(P, "wb")
print("io.open 结果 = " .. tostring(fh) .. "  err = " .. tostring(err))
if fh then fh:close() end