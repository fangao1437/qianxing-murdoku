const fs=require('fs');
const BASE='https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/';
const tools=['list_documents','list_client_documents','get_node_info'];
(async()=>{
  const out={};
  for(const t of tools){
    try{
      const r=await fetch(BASE+t,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({keyword:''})});
      const t2=await r.text();
      out[t]={status:r.status,len:t2.length,head:t2.slice(0,300)};
    }catch(e){out[t]={err:e.message};}
  }
  console.log(JSON.stringify(out,null,1));
})();
