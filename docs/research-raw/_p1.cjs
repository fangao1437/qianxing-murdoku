const fs=require('fs');
const store=JSON.parse(fs.readFileSync('docs/research-raw/kb-docs.json','utf8'));
const want=['负载优化','逻辑自查小贴士','试玩及调试','编辑项范围限制','整体界面','界面控件组','界面控件组管理','界面介绍','交互界面的搭建','玩法整合：界面控件'];
let out='';
const seen=new Set();
for(const d of store){
  if(!want.includes(d.title)) continue;
  if(seen.has(d.title)) continue; seen.add(d.title);
  out+='\n\n========== '+d.title+' ('+d.file+') ==========\n'+d.content;
}
fs.writeFileSync('docs/research-raw/_read1.txt',out,'utf8');
console.log('chars',out.length);
