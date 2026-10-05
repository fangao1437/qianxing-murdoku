const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
async function call(tool,body){
  const r=await fetch(BASE+tool,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body||{})});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t,status:r.status};}
}
const queries=[
 '客户端控件 性能 优化','移动端 性能 卡顿','控件 数量 上限','每帧 遍历 控件树','SetVisible 可见性',
 '控件 生命周期 就绪 时机','首帧 渲染 不显示','控件 模板 实例化','模板 列表项 复用',
 '客户端 Lua 限制 不支持','定时器 计时器 客户端','滚轮 输入 客户端','日志 调试 输出',
 '改了 不生效 刷新','常见错误 报错','最佳实践 结构 拆分','状态 与 渲染 分离',
 '资源 释放 内存','控件 名字 冲突 重名','InstantiateClientUIControl','客户端脚本 注意事项'
];
(async()=>{
  const out=[];
  for(const q of queries){
    const r=await call('rag_search',{queries:[q]});
    out.push({query:q,res:r});
    const res=r?.data?.result;
    const n=Array.isArray(res)?res.reduce((a,x)=>a+((x.documents||[]).length),0):-1;
    console.log('Q:',q,'-> hits:',n);
  }
  fs.writeFileSync('docs/research-raw/kb-rag.json',JSON.stringify(out,null,1));
  // probe get_document signatures
  const p1=await call('get_document',{titles:['逻辑自查小贴士']});
  console.log('get_document(titles) ->',JSON.stringify(p1).slice(0,400));
})();
