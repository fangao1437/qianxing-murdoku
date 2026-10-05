const fs=require('fs');
const base='https://raw.githubusercontent.com/1475505/Miliastra-knowledge/main/';
const files=['bbs/bbs-faq.md','bbs/bbs-faq-since1282.md','bbs/bbs-faq-since1242.md','bbs/bbs-faq-since1207.md','bbs/bbs-faq-since1124.md','bbs/bbs-faq-since1036.md','README.md'];
(async()=>{
 for(const f of files){
  try{
   const r=await fetch(base+f,{headers:{'user-agent':'research'}});
   const t=await r.text();
   if(r.status===200){ fs.writeFileSync('docs/research-raw/bbs-'+f.split('/').pop(),t,'utf8'); console.log('OK',f,t.length); }
   else console.log('HTTP',r.status,f);
  }catch(e){console.log('ERR',f,e.message);}
 }
})();
