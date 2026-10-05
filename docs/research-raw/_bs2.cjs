const fs=require('fs');
const files=[
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/05-lua-implementation.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/06-simulator-testing.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/01-game-design.md',
 'agent/wonderland-lua-builder/skills/qxqy-game-studio/references/02-test-cases.md',
 'agent/wonderland-lua-builder/evals/agent-behavior.md',
 'skill/SKILL.md'
];
(async()=>{
 for(let attempt=1;attempt<=3;attempt++){
  for(const f of files){
   const out='docs/research-raw/bs-'+f.split('/').pop();
   if(fs.existsSync(out)&&fs.statSync(out).size>200) continue;
   const url='https://raw.githubusercontent.com/1475505/miliastra-beyond-simulator/master/'+f;
   try{
     const r=await fetch(url,{headers:{'user-agent':'research'}});
     const t=await r.text();
     if(r.status===200){ fs.writeFileSync(out,t,'utf8'); console.log('OK',f,t.length); }
     else console.log('HTTP',r.status,f);
   }catch(e){console.log('ERR try'+attempt,f,e.message);}
  }
 }
 console.log('DONE');
})();
