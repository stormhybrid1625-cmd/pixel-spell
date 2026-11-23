// Pixel Spell — magic circle generator (single source: preview PNG + later Luau point lists)
const fs = require('fs'), zlib = require('zlib'), path = require('path');

// ---------- PNG ----------
function crc32(buf){let c,crc=0xffffffff;for(let n=0;n<buf.length;n++){c=(crc^buf[n])&0xff;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;crc=(crc>>>8)^c;}return (crc^0xffffffff)>>>0;}
function chunk(t,d){const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc32(td));return Buffer.concat([l,td,c]);}
function png(w,h,rgb){const raw=Buffer.alloc((w*3+1)*h);for(let y=0;y<h;y++){raw[y*(w*3+1)]=0;rgb.copy(raw,y*(w*3+1)+1,y*w*3,(y+1)*w*3);}
 const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=2;ih[10]=0;ih[11]=0;ih[12]=0;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}

// ---------- grid ----------
// level: 1 = core (brightest strokes), 2 = mid (rings), 3 = edge (faint details)
function Grid(n){this.n=n;this.c=(n-1)/2;this.px=new Map();}
Grid.prototype.set=function(x,y,lv,layer){x=Math.round(x);y=Math.round(y);if(x<0||y<0||x>=this.n||y>=this.n)return;const k=x+','+y;const o=this.px.get(k);if(!o||lv<o.lv)this.px.set(k,{x,y,lv,layer});};
Grid.prototype.line=function(x0,y0,x1,y1,lv,L){const d=Math.max(Math.abs(x1-x0),Math.abs(y1-y0))*1.5+1;for(let i=0;i<=d;i++){const t=i/d;this.set(x0+(x1-x0)*t,y0+(y1-y0)*t,lv,L);}};
Grid.prototype.ring=function(r,lv,L,dash,duty,rot){const steps=Math.ceil(r*8);for(let i=0;i<steps;i++){const a=i/steps*Math.PI*2+(rot||0);if(dash){const f=(i/steps*dash)%1;if(f>(duty||0.5))continue;}this.set(this.c+Math.cos(a)*r,this.c+Math.sin(a)*r,lv,L);}};
// unit-space helpers (y up) for sigils
function U(g,cx,cy,s){return{
 P:(x,y)=>[cx+x*s,cy-y*s],
 line(a,b,lv,L){const p=this.P(...a),q=this.P(...b);g.line(p[0],p[1],q[0],q[1],lv,L);},
 poly(pts,lv,L,closed=true){for(let i=0;i<pts.length-(closed?0:1);i++)this.line(pts[i],pts[(i+1)%pts.length],lv,L);},
 circ(x,y,r,lv,L){const p=this.P(x,y);const rr=r*s;const st=Math.max(12,Math.ceil(rr*8));for(let i=0;i<st;i++){const a=i/st*Math.PI*2;g.set(p[0]+Math.cos(a)*rr,p[1]+Math.sin(a)*rr,lv,L);}},
 dot(x,y,lv,L){const p=this.P(x,y);g.set(p[0],p[1],lv,L);},
 bez(a,c,b,lv,L){let prev=a;for(let i=1;i<=24;i++){const t=i/24,u=1-t;const p=[u*u*a[0]+2*u*t*c[0]+t*t*b[0],u*u*a[1]+2*u*t*c[1]+t*t*b[1]];this.line(prev,p,lv,L);prev=p;}},
};}
const tri=(up,r=1)=>[0,1,2].map(i=>{const a=(up?90:-90)+i*120;return[Math.cos(a*Math.PI/180)*r,Math.sin(a*Math.PI/180)*r];});

// ---------- element sigils: simple symbolic glyphs ----------
const SIGILS={
 Neutral(u){u.circ(0,0,0.55,1);u.dot(0,0,1);},
 Fire(u){// alchemical fire: triangle + core ring + rising stroke + 3 heat rays above apex
   const T=[[0,0.55],[-0.95,-0.9],[0.95,-0.9]];u.poly(T,1);
   u.poly([[0,0.05],[-0.5,-0.68],[0.5,-0.68]],2);u.line([0,0.05],[0,0.38],2);
   u.line([0,0.7],[0,1.02],2);u.line([-0.28,0.62],[-0.55,0.88],2);u.line([0.28,0.62],[0.55,0.88],2);},
 Ice(u){for(let i=0;i<3;i++){const a=i*Math.PI/3+Math.PI/2;const x=Math.cos(a),y=Math.sin(a);u.line([-x,-y],[x,y],1);
   for(const sg of[1,-1]){const bx=x*0.6*sg,by=y*0.6*sg;const n=[-y,x];u.line([bx,by],[bx+(x*sg*0.28)+n[0]*0.22,by+(y*sg*0.28)+n[1]*0.22],2);u.line([bx,by],[bx+(x*sg*0.28)-n[0]*0.22,by+(y*sg*0.28)-n[1]*0.22],2);}}},
 Lightning(u){u.poly([[0,1],[0.62,0],[0,-1],[-0.62,0]],2);u.poly([[0.18,0.72],[-0.22,0.06],[0.22,-0.06],[-0.18,-0.72]],1,undefined,false);},
 Nature(u){u.line([0,-0.95],[0,0.95],1);u.bez([0,0.1],[0.55,0.15],[0.6,0.7],2);u.bez([0,0.1],[0.05,0.65],[0.6,0.7],2);
   u.bez([0,-0.35],[-0.55,-0.3],[-0.6,0.25],2);u.bez([0,-0.35],[-0.05,0.2],[-0.6,0.25],2);u.line([-0.35,-0.95],[0.35,-0.95],2);},
 Toxic(u){// three open crescents around a core ring (simplified hazard mark)
   u.circ(0,0,0.2,1);for(let i=0;i<3;i++){const a=Math.PI/2+i*2*Math.PI/3;const cx=Math.cos(a)*0.55,cy=Math.sin(a)*0.55;
     const p=(t)=>[cx+Math.cos(a+t)*0.42,cy+Math.sin(a+t)*0.42];let prev=p(-2.3);for(let k=1;k<=20;k++){const q=p(-2.3+4.6*k/20);u.line(prev,q,1);prev=q;}
     u.line([Math.cos(a)*0.2,Math.sin(a)*0.2],[Math.cos(a)*0.4,Math.sin(a)*0.4],2);}},
 Arcane(u){u.circ(0,0,0.42,2);u.line([0,-1],[0,1],1);u.line([-0.7,0],[0.7,0],1);for(const[x,y]of[[0.6,0.6],[-0.6,0.6],[0.6,-0.6],[-0.6,-0.6]])u.dot(x,y,1);},
 Chaos(u){u.circ(0,0,0.25,1);for(let i=0;i<8;i++){const a=i*Math.PI/4;const c=Math.cos(a),s=Math.sin(a);u.line([c*0.3,s*0.3],[c,s],1);
   const n=[-s,c];u.line([c,s],[c*0.78+n[0]*0.14,s*0.78+n[1]*0.14],2);u.line([c,s],[c*0.78-n[0]*0.14,s*0.78-n[1]*0.14],2);}},
 Steel(u){u.circ(-0.22,-0.22,0.5,1);const d=Math.SQRT1_2;u.line([-0.22+0.5*d,-0.22+0.5*d],[0.85,0.85],1);u.line([0.85,0.85],[0.4,0.85],2);u.line([0.85,0.85],[0.85,0.4],2);},
};

// ---------- procedural runes (tiny 3x5 stroke glyphs, seeded) ----------
function rng(seed){return()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};}
function makeRune(r){// segments on a 3x5 node lattice (x 0..2, y 0..4)
 const segs=[];const nodes=[[0,0],[2,0],[0,2],[1,2],[2,2],[0,4],[2,4],[1,0],[1,4]];
 segs.push([[1,0],[1,4]].map(p=>p)); // spine (most runes have one)
 const k=3+Math.floor(r()*3);for(let i=0;i<k;i++){const a=nodes[Math.floor(r()*nodes.length)],b=nodes[Math.floor(r()*nodes.length)];if(a!==b)segs.push([a,b]);}
 if(r()<0.4)segs.shift();return segs;}
function runeBand(g,r,count,seed,lv,L){const R=rng(seed);for(let i=0;i<count;i++){const a=i/count*Math.PI*2;const rad=[Math.cos(a),Math.sin(a)],tan=[-Math.sin(a),Math.cos(a)];
  const rune=makeRune(R);for(const[p,q]of rune){const map=([x,y])=>{const uu=(x-1)*1.5,vv=(y-2)*1.05;return[g.c+rad[0]*(r+vv)+tan[0]*uu,g.c+rad[1]*(r+vv)+tan[1]*uu];};
   const A=map(p),B=map(q);g.line(A[0],A[1],B[0],B[1],lv,L);}}}

// ---------- circles ----------
function superior(element,seed){const n=129,g=new Grid(n),c=g.c;
 // layer A: outer frame + runes (rotates slowly)
 g.ring(62,2,'A');g.ring(59.5,3,'A',48,0.55);runeBand(g,53.8,26,seed,1,'A');g.ring(48,2,'A');
 for(let i=0;i<44;i++){const a=i/44*Math.PI*2;g.line(c+Math.cos(a)*48,c+Math.sin(a)*48,c+Math.cos(a)*(i%4==0?45:46.5),c+Math.sin(a)*(i%4==0?45:46.5),3,'A');}
 // layer B: hexagram + node circles (counter-rotates)
 const R=44,v=[];for(let i=0;i<6;i++){const a=-Math.PI/2+i*Math.PI/3;v.push([c+Math.cos(a)*R,c+Math.sin(a)*R]);}
 for(let i=0;i<6;i++){const p=v[i],q=v[(i+2)%6];g.line(p[0],p[1],q[0],q[1],1,'B');}
 for(const[x,y]of v){const u=U(g,x,y,5);u.circ(0,0,1,2,'B');u.dot(0,0,1,'B');}
 g.ring(36,3,'B',60,0.5);
 // layer C: inner ring + sigil (still)
 g.ring(26,2,'C');g.ring(23.5,3,'C');
 for(let i=0;i<12;i++){const a=i/12*Math.PI*2;g.line(c+Math.cos(a)*26,c+Math.sin(a)*26,c+Math.cos(a)*30,c+Math.sin(a)*30,2,'C');}
 SIGILS[element](U(g,c,c,17));
 for(const p of g.px.values())if(!p.layer)p.layer='C';
 return g;}
function sigilOnly(element){const g=new Grid(41);SIGILS[element](U(g,g.c,g.c,17));return g;}

// ---------- render ----------
const PAL={Neutral:['f0f0f4','a6a6b0','4c4c56'],Nature:['d6ffd8','34c46a','1c6a3c'],Lightning:['ffffff','ffe94f','3a6cff'],Chaos:['f4ff6b','ff3ccf','6a2a90'],
 Arcane:['fbe8ff','c56bff','5a2a9e'],Toxic:['f8ffa0','c8ee1c','6a7a0c'],Fire:['fff3a1','ff8f26','c8301c'],Steel:['ffffff','c9d2e6','5a6480'],Ice:['f0fdff','8fe3ff','2f7fd6']};
const hex=h=>[parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)];
function Canvas(w,h){this.w=w;this.h=h;this.b=Buffer.alloc(w*h*3);for(let i=0;i<w*h;i++){this.b[i*3]=10;this.b[i*3+1]=10;this.b[i*3+2]=16;}}
Canvas.prototype.add=function(x,y,col,a){if(x<0||y<0||x>=this.w||y>=this.h)return;const i=(y*this.w+x)*3;for(let k=0;k<3;k++)this.b[i+k]=Math.min(255,this.b[i+k]+col[k]*a);};
Canvas.prototype.put=function(x,y,col){if(x<0||y<0||x>=this.w||y>=this.h)return;const i=(y*this.w+x)*3;for(let k=0;k<3;k++)this.b[i+k]=Math.max(this.b[i+k],col[k]);};
function draw(cv,g,ox,oy,s,el){const P=PAL[el].map(hex);
 for(const p of g.px.values()){const col=P[p.lv-1];// soft halo (dim, no bloom)
  for(let dy=-s;dy<2*s;dy++)for(let dx=-s;dx<2*s;dx++)cv.add(ox+p.x*s+dx,oy+p.y*s+dy,P[2],0.05);}
 for(const p of g.px.values()){const col=P[p.lv-1];for(let dy=0;dy<s-1||dy==0;dy++)for(let dx=0;dx<s-1||dx==0;dx++)cv.put(ox+p.x*s+dx,oy+p.y*s+dy,col);}}

// sheet: row of 9 sigils + row of superior circles
const els=['Neutral','Fire','Ice','Lightning','Nature','Toxic','Arcane','Chaos','Steel'];
const S1=3,cell=41*S1+16,circS=3,circW=129*circS+24;
const W=Math.max(els.length*cell,3*circW)+16,H=cell+16+2*(129*circS+24)+8;
const cv=new Canvas(W,H);
els.forEach((e,i)=>draw(cv,sigilOnly(e),8+i*cell+8,8,S1,e));
const show=['Fire','Ice','Lightning','Nature','Arcane','Toxic'];
show.forEach((e,i)=>draw(cv,superior(e,7+i*13),8+(i%3)*circW+12,cell+16+Math.floor(i/3)*(129*circS+24)+12,circS,e));
const out=path.join(__dirname,'sheet_v1.png');fs.writeFileSync(out,png(W,H,cv.b));
const counts=show.map(e=>e+':'+superior(e,1).px.size).join(' ');
console.log(out,W+'x'+H,counts);
module.exports={superior,sigilOnly,SIGILS};

// ---------- export: white RGBA layer textures + sampled points (Luau) ----------
function pngRGBA(w,h,px){const raw=Buffer.alloc((w*4+1)*h);for(let y=0;y<h;y++){raw[y*(w*4+1)]=0;px.copy(raw,y*(w*4+1)+1,y*w*4,(y+1)*w*4);}
 const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=6;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
const LVA=[255,235,150],LVG=[255,215,170];
function texture(pts,n,S){const w=n*S,b=Buffer.alloc(w*w*4);for(const p of pts){for(let dy=0;dy<S;dy++)for(let dx=0;dx<S;dx++){const i=((p.y*S+dy)*w+p.x*S+dx)*4;const g=LVG[p.lv-1];b[i]=g;b[i+1]=g;b[i+2]=g;b[i+3]=Math.max(b[i+3],LVA[p.lv-1]);}}return pngRGBA(w,w,b);}
function sample(pts,n,k){const a=[...pts];const out=[];const step=Math.max(1,a.length/k);for(let i=0;i<a.length&&out.length<k;i+=step){const p=a[Math.floor(i)];out.push([+((p.x-(n-1)/2)/((n-1)/2)).toFixed(3),+((p.y-(n-1)/2)/((n-1)/2)).toFixed(3),p.lv]);}return out;}
const ex=path.join(__dirname,'export');if(!fs.existsSync(ex))fs.mkdirSync(ex);
const base=superior('Neutral',7);base.px.forEach((p,k)=>{}); // sigil drawn in C; rebuild C without sigil
const g2=new Grid(129);{const c=g2.c;g2.ring(26,2,'C');g2.ring(23.5,3,'C');for(let i=0;i<12;i++){const a=i/12*Math.PI*2;g2.line(c+Math.cos(a)*26,c+Math.sin(a)*26,c+Math.cos(a)*30,c+Math.sin(a)*30,2,'C');}}
const L={A:[...base.px.values()].filter(p=>p.layer==='A'),B:[...base.px.values()].filter(p=>p.layer==='B'),C:[...g2.px.values()]};
const lua=['-- generated by scratchpad/circles/gen.js — do not hand edit','local D = { Grid = 129, SigilGrid = 41, SigilScale = 17/64, Layers = {}, Sigils = {} }'];
for(const k of['A','B','C']){fs.writeFileSync(path.join(ex,'sup_'+k+'.png'),texture(L[k],129,4));lua.push('D.Layers.'+k+' = '+JSON.stringify(sample(L[k],129,k==='A'?140:k==='B'?110:60)).replace(/\[/g,'{').replace(/\]/g,'}'));}
for(const e of els){const s=sigilOnly(e);const pts=[...s.px.values()];fs.writeFileSync(path.join(ex,'sigil_'+e+'.png'),texture(pts,41,8));lua.push('D.Sigils.'+e+' = '+JSON.stringify(sample(pts,41,40)).replace(/\[/g,'{').replace(/\]/g,'}'));}
lua.push('D.Palette = '+JSON.stringify(PAL).replace(/"(\w+)":/g,'$1 = ').replace(/\[/g,'{').replace(/\]/g,'}'));
lua.push('return D');fs.writeFileSync(path.join(ex,'CircleData.lua'),lua.join('\n'));
console.log('exported',Object.fromEntries(Object.entries(L).map(([k,v])=>[k,v.length])));
