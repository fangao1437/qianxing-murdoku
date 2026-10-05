const fs=require('fs');
const files=[
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/05-lua-implementation.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/06-simulator-testing.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/07-device-validation.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/SKILL.md',
 'client/lua-runtime/docs/observed-contract.md',
 'studio/docs/control-support.md',
 'studio/docs/script-sync.md',
 'agent/wonderland-lua-builder/README.md'
];
(async()=>{
  for(const f of files){
    const url='https://raw.githubusercontent.com/1475505/miliastra-beyond-simulator/master/'+f;
    try{
      const r=await fetch(url,{headers:{'user-agent':'research'}});
      const t=await r.text();
      const name=f.split('/').pop();
      fs.writeFileSync('docs/research-raw/bs-'+name,t,'utf8');
      console.log(r.status, name, t.length);
    }catch(e){console.log('ERR',f,e.message);}
  }
})();
