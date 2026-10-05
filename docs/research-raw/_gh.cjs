const fs=require('fs');
async function gh(url){
  const r=await fetch(url,{headers:{'user-agent':'research','accept':'application/vnd.github+json'}});
  const t=await r.text();
  try{return JSON.parse(t);}catch(e){return {raw:t.slice(0,300)};}
}
(async()=>{
  for(const repo of ['1475505/miliastra-beyond-simulator','1475505/Miliastra-toolbox','1475505/Miliastra-knowledge']){
    let info;
    try{ info=await gh('https://api.github.com/repos/'+repo); }catch(e){ console.log(repo,'ERR',e.message); continue; }
    console.log('=== ',repo,'| default_branch:',info.default_branch,'| desc:',(info.description||'').slice(0,160),'| stars:',info.stargazers_count,'| pushed:',info.pushed_at);
    try{
      const tr=await gh('https://api.github.com/repos/'+repo+'/git/trees/'+info.default_branch+'?recursive=1');
      if(tr.tree){
        console.log('  files:',tr.tree.filter(t=>t.type==='blob').length);
        fs.writeFileSync('docs/research-raw/tree-'+repo.replace('/','_')+'.json',JSON.stringify(tr.tree.map(t=>t.path),null,1));
      } else console.log('  tree err',JSON.stringify(tr).slice(0,200));
    }catch(e){console.log('  tree ERR',e.message);}
  }
})();
