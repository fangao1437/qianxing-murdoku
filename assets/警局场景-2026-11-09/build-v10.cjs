const fs=require('fs');
const OUT='C:/Users/18182/AppData/Local/Temp/wb-art-build';
const W=1600,H=900;
const BASE='#B64A20',TAPE='#FFC400',PAW='#6E2B10';
const BAG='#D99331',BAG_DARK='#C86D20',BAG_RED='#C85D11',LINE='#6A3210';
const IVORY='#F7E9C8',CORE='#6E2B10',FRAME='#F7F1DC',PHOTO='#3D3359';
const TH=15.4,BAG_C=[666,331],BAG_W=600,BAG_H=800;
const POL_C=[1256,516],POL_W=438,POL_H=419,POL_TH=8;
const local=(c,t,u,v)=>{const a=t*Math.PI/180;return[c[0]+u*Math.cos(a)+v*Math.sin(a),c[1]-u*Math.sin(a)+v*Math.cos(a)];};
const boxes=[
 {id:'①',text:'POLICE TIME',x:1365,y:181,w:480,h:120,rot:9},
 {id:'②',text:'POLICE TIME',x:330, y:680,w:480,h:120,rot:-7.6},
 {id:'③',text:'POLICE TIME',x:1281,y:807,w:480,h:120,rot:-7.6},
];
function build(withText){
 const els=[];let z=0;
 const add=o=>els.push(Object.assign({id:'e'+(++z),rotation:0,opacity:1,zIndex:z-1,isBackground:false},o));
 const img=(a,x,y,w,h,c,r=0,o=1)=>add({type:'image',x,y,width:w,height:h,rotation:r,color:c,opacity:o,imageAssetId:a,imageType:'stretch',imageTint:true});
 const tb=b=>add({type:'textbox',x:b.x,y:b.y,width:b.w,height:b.h,rotation:b.rot,color:'#241309',
  textBox:{text:b.text,fontSize:48,autoSize:false,minFontSize:24,textColor:'#241309',textOpacity:1,
   bgColor:'#ffffff',bgOpacity:0,outlineEnabled:false,alignH:'center',alignV:'middle',anchorType:'center',visible:true,
   scaleX:1,scaleY:1,anchorMinX:0.5,anchorMinY:0.5,anchorMaxX:0.5,anchorMaxY:0.5,pivotX:0.5,pivotY:0.5}});
 const bag=(a,u,v,w,h,c,r=TH,o=1)=>{const[x,y]=local(BAG_C,TH,u,v);img(a,x,y,w,h,c,r,o);};
 const pol=(a,u,v,w,h,c)=>{const[x,y]=local(POL_C,POL_TH,u,v);img(a,x,y,w,h,c,POL_TH);};
 img(100001,800,450,W,H,BASE);
 for(const[ox,oy]of[[150,120],[1090,225],[1200,285],[535,640],[330,560]]){const[cx,cy]=[ox*1.25,oy*1.25];
  img(100002,cx,cy+10,42.5,35,PAW,-15);
  for(const[dx,dy]of[[-22,-14],[-8,-26],[9,-26],[23,-12]])img(100002,cx+dx*1.25,cy+dy*1.25,16.25,16.25,PAW);}
 img(100001,800,241,1900,100,TAPE,9);
 img(100001,800,713,1900,100,TAPE,-7.6);
 // ★ 暗角：只用官方 106060（径向暗角素材），单层，去掉圆环
 img(106060,800,450,1800,1040,'#000000',0,1);
 img(106056,694,363,708,944,'#000000',TH,0.28);
 img(106056,1282,546,526,503,'#000000',POL_TH,0.26);
 if(withText)for(const b of boxes)tb(b);
 img(100001,BAG_C[0],BAG_C[1],BAG_W,BAG_H,BAG,TH);
 // ★ 深橙四边形：按精测顶点精确铺（局部坐标）
 //   实测目标 A(351,78) / B(-196,368) / C(273,361)；夹到档案袋右边缘 u=300 得 A'(300,105)
 //   斜边 A'→B: v = 105 + 0.531*(300-u)，底边 v=365
 //   用 90 条局部竖矩形随档案袋旋转铺满，形状精确、无 45° 山峰、零溢出
 const U0=-300,U1=300,N=100,du=(U1-U0)/N;
 for(let i=0;i<N;i++){const u=U0+(i+0.5)*du;
  const vTop=105+0.492*(300-u),vBot=395;
  if(vBot-vTop<1)continue;
  bag(100001,u,(vTop+vBot)/2,du+0.6,vBot-vTop+1,BAG_DARK,TH,0.92);
 }
 // ★ 橘红楔形：实测宽约 40~60px、长约 460px，贴档案袋左边缘（u≈-245）
 bag(100003,-258,120,64,520,BAG_RED,TH,0.95);
 // 两条分割线（原图局部 v=-281 / +356）
 bag(100001,0,-281,BAG_W,4,LINE,TH,0.85);
 bag(100001,0,356,BAG_W,4,LINE,TH,0.85);
 for(const v of[-330,-210]){bag(100002,28,v,84,84,IVORY,TH);bag(100002,28,v,20,20,CORE,TH);}
 pol(100001,0,0,POL_W,POL_H,FRAME);
 pol(100001,0,-16,350,300,PHOTO);
 return{canvas:{width:W,height:H,background:BASE},elements:els,meta:{sourceType:'editor',sourceName:'police-v10',warnings:[]}};
}
(async()=>{
 for(const j of[{key:'v10',t:true},{key:'v10-notext',t:false}]){
  const sc=build(j.t);fs.writeFileSync(OUT+'/scene-'+j.key+'.json',JSON.stringify(sc,null,2));
  console.log(j.key,'elements',sc.elements.length);
  for(const kind of['gia','png']){
   const r=await fetch('https://qx.070077.xyz/api/export/'+kind,{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({scene:sc,giaGroupName:'police-'+j.key})});
   const b=Buffer.from(await r.arrayBuffer());console.log(' ',kind,r.status,b.length);
   if(r.ok)fs.writeFileSync(OUT+'/police-'+j.key+(kind==='gia'?'.gia':'.png'),b);else console.log(b.toString('utf8').slice(0,200));
  }
 }
})();
