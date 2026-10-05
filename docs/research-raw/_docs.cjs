const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
async function call(tool,body){
  const r=await fetch(BASE+tool,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body||{})});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t,status:r.status};}
}
const titles=[
 '负载优化','逻辑自查小贴士','试玩及调试','1.5Debug调试','《原神》UGC编辑器FAQ',
 '界面控件组编辑','界面控件','界面布局','界面控件组管理','界面控件组','整体界面','界面介绍',
 '客户端节点图日志','节点图日志','复合节点图日志','编辑项范围限制','定时器','全局计时器',
 '计时器界面控件','网格视窗控件','模板引用控件','文本视窗控件','客户端控件容器','容器节点控件',
 '预设按钮控件','光标检测区域控件','按键提示控件','自定义按钮控件','图片控件','局部脚本','局部变量',
 '自定义小地图控件','场景界面','交互界面的搭建','玩法整合：界面控件','界面控件——手柄适配引导'
];
(async()=>{
  // batch in groups of 8
  const store=[];
  for(let i=0;i<titles.length;i+=8){
    const batch=titles.slice(i,i+8);
    const r=await call('get_document',{titles:batch});
    const arr=r?.data?.result||[];
    for(const q of arr){ for(const d of (q.documents||[])){ store.push({title:d.title,file:d.file,content:d.content}); } 
      if(q.status!=='ok') store.push({title:'MISS:'+q.query,status:q.status});
    }
    console.log('batch',i/batch.length+1,'got',arr.length);
  }
  fs.writeFileSync('docs/research-raw/kb-docs.json',JSON.stringify(store,null,1));
  console.log('DOCS',store.length);
  store.forEach(d=>console.log(' -',d.title,'|',(d.content||'').length));
})();
