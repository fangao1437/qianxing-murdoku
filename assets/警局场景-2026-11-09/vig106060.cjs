const fs=require('fs');
const {createCanvas,loadImage}=require('D:/新建文件夹/miHoYo Launcher/qianxing-murdoku-tool/node_modules/@napi-rs/canvas');
const W=1600,H=900;
const cases=[
 {n:'a_1600_op1',w:1600,h:900,op:1},
 {n:'b_1800_op1',w:1800,h:1040,op:1},
 {n:'c_2000_op1',w:2000,h:1150,op:1},
 {n:'d_2200_op1',w:2200,h:1300,op:1},
 {n:'e_1800_plus_2400',w:1800,h:1040,op:0.8,extra:{w:2400,h:1400,op:0.4}},
 {n:'f_1600_plus_2000',w:1600,h:900,op:0.7,extra:{w:2000,h:1150,op:0.5}},
];
(async()=>{
 const pngs=[];
 for(const q of cases){
  const els=[{id:'bg',type:'image',x:800,y:450,width:W,height:H,color:'#B64A20',opacity:1,zIndex:0,imageAssetId:100001,imageType:'stretch',imageTint:true},
   {id:'t1',type:'image',x:800,y:241,width:1900,height:100,rotation:9,color:'#FFC400',opacity:1,zIndex:1,imageAssetId:100001,imageType:'stretch',imageTint:true}];
  els.push({id:'v1',type:'image',x:800,y:450,width:q.w,height:q.h,color:'#000000',opacity:q.op,zIndex:2,imageAssetId:106060,imageType:'stretch',imageTint:true});
  if(q.extra)els.push({id:'v2',type:'image',x:800,y:450,width:q.extra.w,height:q.extra.h,color:'#000000',opacity:q.extra.op,zIndex:3,imageAssetId:106060,imageType:'stretch',imageTint:true});
  const scene={canvas:{width:W,height:H,background:'#B64A20'},elements:els,meta:{sourceType:'editor',sourceName:q.n,warnings:[]}};
  const r=await fetch('https://qx.070077.xyz/api/export/png',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({scene,giaGroupName:q.n})});
  const b=Buffer.from(await r.arrayBuffer());if(r.ok){const f='v6-'+q.n+'.png';fs.writeFileSync(f,b);pngs.push({n:q.n,f})}else console.log(q.n,'ERR',r.status);
 }
 const ims=await Promise.all(pngs.map(async p=>({n:p.n,im:await loadImage(p.f)})));
 const cw=ims[0].im.width,ch=ims[0].im.height;
 const out=createCanvas(cw*3,ch*2),cx=out.getContext('2d');cx.fillStyle='#888';cx.fillRect(0,0,cw*3,ch*2);
 ims.forEach((o,i)=>{cx.drawImage(o.im,(i%3)*cw,((i/3)|0)*ch);cx.fillStyle='#000';cx.fillRect((i%3)*cw,((i/3)|0)*ch,230,26);cx.fillStyle='#fff';cx.font='bold 16px sans-serif';cx.fillText(o.n,(i%3)*cw+8,((i/3)|0)*ch+19)});
 fs.writeFileSync('vig106060-compare.png',out.toBuffer('image/png'));
 console.log('目标：原图 中心183 四角51 上边中182 左边中180 右边中84');
 for(const o of ims){const c=createCanvas(o.im.width,o.im.height),x=c.getContext('2d');x.drawImage(o.im,0,0);
  const d=x.getImageData(0,0,o.im.width,o.im.height).data;const at=(X,Y)=>d[(Y*o.im.width+X)*4];
  console.log(o.n.padEnd(20),'中心',at(800,450),'左上角',at(40,40),'右上角',at(1560,40),'左下角',at(40,860),'上边中',at(800,40),'左边中',at(40,450),'右边中',at(1560,450));}
})();
