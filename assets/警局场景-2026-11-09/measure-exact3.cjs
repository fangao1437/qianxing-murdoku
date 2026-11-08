const {createCanvas,loadImage}=require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const fs=require('fs');
const P='C:/Users/18182/AppData/LocalLow/miHoYo/原神/BeyondLocal/Beyond_Local_Export_SourcePNG/';
const W=1280,H=720,S=1.25,TH=15.4;
const C={body:[217,147,49],dark:[200,109,32],red:[200,93,17]};
const d2=(p,q)=>(p[0]-q[0])**2+(p[1]-q[1])**2+(p[2]-q[2])**2;
const hull=(pts)=>{pts=pts.slice().sort((a,b)=>a[0]-b[0]||a[1]-b[1]);const cr=(o,a,b)=>(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0]);
 const lo=[],up=[];for(const p of pts){while(lo.length>=2&&cr(lo[lo.length-2],lo[lo.length-1],p)<=0)lo.pop();lo.push(p)}
 for(let i=pts.length-1;i>=0;i--){const p=pts[i];while(up.length>=2&&cr(up[up.length-2],up[up.length-1],p)<=0)up.pop();up.push(p)}
 lo.pop();up.pop();return lo.concat(up);};
const simplify=(hp,eps)=>{const out=[];for(let i=0;i<hp.length;i++){const a=hp[(i-1+hp.length)%hp.length],b=hp[i],cc=hp[(i+1)%hp.length];
  const cr=Math.abs((b[0]-a[0])*(cc[1]-b[1])-(b[1]-a[1])*(cc[0]-b[0])),len=Math.hypot(cc[0]-a[0],cc[1]-a[1]);
  if(cr/Math.max(len,1)>eps)out.push(b);}return out;};
const toLocal=(X,Y)=>{const a=TH*Math.PI/180,dx=X-666,dy=Y-331;
 return[Math.round(dx*Math.cos(a)-dy*Math.sin(a)),Math.round(dx*Math.sin(a)+dy*Math.cos(a))];};
(async()=>{
 const [ia,ib]=await Promise.all([loadImage(P+'scene-no-cup.png'),loadImage(P+'background.png')]);
 const g=(im)=>{const c=createCanvas(W,H);c.getContext('2d').drawImage(im,0,0);return c.getContext('2d').getImageData(0,0,W,H).data};
 const A=g(ia),B=g(ib);
 const px=(d,x,y)=>{const i=(y*W+x)*4;return[d[i],d[i+1],d[i+2]]};
 const sets={body:[],dark:[],red:[]},obj=[];
 const vis=createCanvas(W,H),vx=vis.getContext('2d');vx.fillStyle='#222';vx.fillRect(0,0,W,H);
 const vi=vx.getImageData(0,0,W,H);
 const COL={body:[255,0,0],dark:[0,255,0],red:[0,0,255]};
 let diffN=0;
 for(let y=0;y<H;y++)for(let x=0;x<W;x++){
  const p=px(A,x,y),q=px(B,x,y);
  const diff=Math.max(Math.abs(p[0]-q[0]),Math.abs(p[1]-q[1]),Math.abs(p[2]-q[2]));
  if(diff<=14)continue;diffN++;obj.push([x,y]);
  if(x<150||x>960)continue; // 只看档案袋区域
  let best=null,bd=1e9;for(const[k,cc]of Object.entries(C)){const d=d2(p,cc);if(d<bd){bd=d;best=k}}
  if(bd>1400){const i=(y*W+x)*4;vi.data[i]=200;vi.data[i+1]=200;vi.data[i+2]=200;vi.data[i+3]=255;continue}
  sets[best].push([x,y]);
  const i=(y*W+x)*4;vi.data[i]=COL[best][0];vi.data[i+1]=COL[best][1];vi.data[i+2]=COL[best][2];vi.data[i+3]=255;
 }
 vx.putImageData(vi,0,0);fs.writeFileSync('segment-vis2.png',vis.toBuffer('image/png'));
 console.log('差分像素',diffN);
 for(const[name,pts]of Object.entries(sets)){
  if(pts.length<100){console.log('\n'+name,'样本不足',pts.length);continue}
  const hp=simplify(hull(pts),14);
  console.log(`\n=== ${name} n=${pts.length} 凸包(原图1280) ===`);
  console.log(' ',hp.map(p=>`(${p[0]},${p[1]})`).join(' '));
  console.log('  设计:',hp.map(p=>`(${Math.round(p[0]*S)},${Math.round(p[1]*S)})`).join(' '));
  console.log('  局部(u,v):',hp.map(p=>`[${toLocal(p[0]*S,p[1]*S).join(',')}]`).join(' '));
  let x0=1e9,y0=1e9,x1=-1,y1=-1;for(const p of pts){if(p[0]<x0)x0=p[0];if(p[0]>x1)x1=p[0];if(p[1]<y0)y0=p[1];if(p[1]>y1)y1=p[1]}
  console.log(`  bbox原图=(${x0},${y0})-(${x1},${y1}) 设计=(${Math.round(x0*S)},${Math.round(y0*S)})-(${Math.round(x1*S)},${Math.round(y1*S)})`);
 }
 console.log('\n=== 深橙区每行 x 范围 ===');
 for(let y=120;y<=660;y+=30){const xs=sets.dark.filter(p=>Math.abs(p[1]-y)<4).map(p=>p[0]).sort((a,b)=>a-b);
  if(xs.length>20)console.log(` y=${y}: ${xs[0]}..${xs[xs.length-1]} (n=${xs.length})`);}
 console.log('\n=== 橘红区每行 x 范围 ===');
 for(let y=100;y<=660;y+=30){const xs=sets.red.filter(p=>Math.abs(p[1]-y)<4).map(p=>p[0]).sort((a,b)=>a-b);
  if(xs.length>8)console.log(` y=${y}: ${xs[0]}..${xs[xs.length-1]} (n=${xs.length})`);}
})();
