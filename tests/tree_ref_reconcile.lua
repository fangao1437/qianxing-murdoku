local tree_ref = dofile("tests/_wip/tree_ref.lua")
local NAME = {}
local function mk(name) local c = {__kids={}} NAME[c]=name; c.GetChildren=function() return c.__kids end; return c end
local function add(p,c) p.__kids[#p.__kids+1]=c; return c end
local function nm(c) return NAME[c] end
local function id(x) return x end
local SKIP = { root = true }   -- ★ 声明：root 是合成根
local pass,fail=0,0

-- ★ 真树：应当放行
local root=mk("root")
local cell=add(root,mk("cell.1.1"))
local content=add(cell,mk("content"))
add(content,mk("face")); add(content,mk("note"))
for _,e in ipairs({"wall.up","wall.down","wall.left","wall.right","door.up","door.down","door.left","door.right"}) do add(content,mk(e)) end
local ok,msg=tree_ref.check(root,nm,"★真树（按 347.gil 形状）",{skipParents=SKIP})
print(msg); if ok then pass=pass+1 else fail=fail+1 end

-- ★ 假树（审计说的那棵）：漏 8 边控件 + 造假 ruler.c.1 ⇒ 必须红
local root2=mk("root")
local cell2=add(root2,mk("cell.1.1"))
local content2=add(cell2,mk("content"))
add(content2,mk("face"))
add(content2,mk("ruler.c.1"))
local ok2,msg2=tree_ref.check(root2,nm,"★★假树（漏边控件＋造假 ruler）",{skipParents=SKIP})
print(msg2); if not ok2 then pass=pass+1 else fail=fail+1 end

print("")
print(string.format("== 对账器自测：%d 通过 / %d 失败 ==",pass,fail))
os.exit(fail==0 and 0 or 1)