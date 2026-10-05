const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
async function call(tool,body){
  const r=await fetch(BASE+tool,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body||{})});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t,status:r.status};}
}
(async()=>{
  const idx=await call('list_client_documents',{});
  fs.writeFileSync('docs/research-raw/kb-client-index.json',JSON.stringify(idx,null,1));
  const docs=(idx?.data?.result?.documents)||[];
  console.log('CLIENT DOCS:',docs.length);
  for(const d of docs) console.log(' -',d.title,'|',d.file);
  const store={};
  for(const d of docs){
    const r=await call('get_client_document',{title:d.title});
    const txt=JSON.stringify(r);
    store[d.title]={file:d.file,len:txt.length,data:r};
    console.log('FETCHED',d.title,txt.length);
  }
  fs.writeFileSync('docs/research-raw/kb-client-docs.json',JSON.stringify(store,null,1));
})();
