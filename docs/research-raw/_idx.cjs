const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
async function call(tool,body){
  const r=await fetch(BASE+tool,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body||{})});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t,status:r.status};}
}
(async()=>{
  const idx=await call('list_documents',{});
  const docs=idx.data.result.documents;
  console.log('TOTAL',idx.data.result.total,docs.length);
  const lines=docs.map(d=>d.title+'\t'+d.file);
  fs.writeFileSync('docs/research-raw/kb-index.tsv',lines.join('\n'),'utf8');
  // print titles matching client/perf/lifecycle-ish keywords
  const kw=['控件','性能','优化','卡','lua','Lua','脚本','生命周期','可见','模板','实例','日志','调试','报错','错误','限制','FAQ','自查','注意','最佳','规范','推荐','移动','适配','屏幕','分辨率','界面','UI','计时','定时','滚轮','输入','渲染','加载','预加载','资源','内存'];
  const hit=docs.filter(d=>kw.some(k=>d.title.includes(k)));
  console.log('--- matching titles ('+hit.length+') ---');
  hit.forEach(d=>console.log(d.title+'\t'+d.file));
})();
