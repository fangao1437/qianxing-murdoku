const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
async function call(tool,body){
  const r=await fetch(BASE+tool,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body||{})});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t,status:r.status};}
}
(async()=>{
  const titles=["按键提示控件","容器节点控件","客户端控件和客户端脚本","光标检测区域控件","预设按钮控件","网格视窗控件","客户端控件容器","客户端控件API文档","模板引用控件","文本视窗控件"];
  const r=await call('get_client_document',{titles});
  fs.writeFileSync('docs/research-raw/kb-client-docs.json',JSON.stringify(r,null,1));
  console.log('len',JSON.stringify(r).length);
  const res=r?.data?.result;
  console.log('keys',res?Object.keys(res):null);
  if(res&&res.documents) res.documents.forEach(d=>console.log(' -',d.title, (d.content||'').length));
})();
