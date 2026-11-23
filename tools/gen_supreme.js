// gen_supreme.js — cercle magique de rang SUPRÊME (aperçu PNG). Réutilise les outils de gen_circles.js.
// Plus grand (grille 193) et plus riche que le Supérieur : double cadre, 2 bandes de runes, 8 cercles satellites
// portant le sigil de l'élément, dodécagramme (2 hexagrammes croisés) + couronne de rayons, grand sigil central.
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const { SIGILS } = require('./gen_circles.js');

function Grid(n){this.n=n;this.c=(n-1)/2;this.px=new Map();}
Grid.prototype.set=function(x,y,lv,layer){x=Math.round(x);y=Math.round(y);if(x<0||y<0||x>=this.n||y>=this.n)return;const k=x+','+y;const o=this.px.get(k);if(!o||lv<o.lv)this.px.set(k,{x,y,lv,layer});};
Grid.prototype.line=function(x0,y0,x1,y1,lv,L){const d=Math.max(Math.abs(x1-x0),Math.abs(y1-y0))*1.5+1;for(let i=0;i<=d;i++){const t=i/d;this.set(x0+(x1-x0)*t,y0+(y1-y0)*t,lv,L);}};
Grid.prototype.ring=function(r,lv,L,dash,duty,rot){const steps=Math.ceil(r*8);for(let i=0;i<steps;i++){const a=i/steps*Math.PI*2+(rot||0);if(dash){const f=(i/steps*dash)%1;if(f>(duty||0.5))continue;}this.set(this.c+Math.cos(a)*r,this.c+Math.sin(a)*r,lv,L);}};
function U(g,cx,cy,s){return{P:(x,y)=>[cx+x*s,cy-y*s],
 line(a,b,lv,L){const p=this.P(...a),q=this.P(...b);g.line(p[0],p[1],q[0],q[1],lv,L);},
 poly(pts,lv,L,closed=true){for(let i=0;i<pts.length-(closed?0:1);i++)this.line(pts[i],pts[(i+1)%pts.length],lv,L);},
 circ(x,y,r,lv,L){const p=this.P(x,y);const rr=r*s;const st=Math.max(12,Math.ceil(rr*8));for(let i=0;i<st;i++){const a=i/st*Math.PI*2;g.set(p[0]+Math.cos(a)*rr,p[1]+Math.sin(a)*rr,lv,L);}},
 dot(x,y,lv,L){const p=this.P(x,y);g.set(p[0],p[1],lv,L);},
 bez(a,c,b,lv,L){let prev=a;for(let i=1;i<=24;i++){const t=i/24,u=1-t;const p=[u*u*a[0]+2*u*t*c[0]+t*t*b[0],u*u*a[1]+2*u*t*c[1]+t*t*b[1]];this.line(prev,p,lv,L);prev=p;}}};}
function rng(seed){return()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};}
function makeRune(r){const segs=[];const nodes=[[0,0],[2,0],[0,2],[1,2],[2,2],[0,4],[2,4],[1,0],[1,4]];segs.push([[1,0],[1,4]]);
 const k=3+Math.floor(r()*3);for(let i=0;i<k;i++){const a=nodes[Math.floor(r()*nodes.length)],b=nodes[Math.floor(r()*nodes.length)];if(a!==b)segs.push([a,b]);}if(r()<0.4)segs.shift();return segs;}
function runeBand(g,r,count,seed,lv,L){const R=rng(seed);for(let i=0;i<count;i++){const a=i/count*Math.PI*2;const rad=[Math.cos(a),Math.sin(a)],tan=[-Math.sin(a),Math.cos(a)];
 for(const[p,q]of makeRune(R)){const map=([x,y])=>{const uu=(x-1)*1.5,vv=(y-2)*1.05;return[g.c+rad[0]*(r+vv)+tan[0]*uu,g.c+rad[1]*(r+vv)+tan[1]*uu];};const A=map(p),B=map(q);g.line(A[0],A[1],B[0],B[1],lv,L);}}}

function supreme(element, seed){
 const n=193, g=new Grid(n), c=g.c;
 // A — cadre extérieur : double anneau, bande de runes, crans, 8 cercles satellites avec le sigil (tourne lentement)
 g.ring(95,2,'A'); g.ring(92.5,3,'A',72,0.5); g.ring(90,2,'A');
 runeBand(g,84.5,36,seed,1,'A'); g.ring(79,2,'A');
 for(let i=0;i<64;i++){const a=i/64*Math.PI*2;const r1=79,r2=(i%8==0)?73:(i%2==0?75.5:77);g.line(c+Math.cos(a)*r1,c+Math.sin(a)*r1,c+Math.cos(a)*r2,c+Math.sin(a)*r2,3,'A');}
 for(let i=0;i<8;i++){const a=-Math.PI/2+i*Math.PI/4;const x=c+Math.cos(a)*95,y=c+Math.sin(a)*95;
  const u=U(g,x,y,7.5);u.circ(0,0,1,1,'A');u.circ(0,0,1.18,3,'A');SIGILS[element](U(g,x,y,4.6));}
 // B — dodécagramme (2 hexagrammes croisés), couronne de rayons, 2e bande de runes (contre-rotation)
 const R=68;
 for(const off of[0,Math.PI/6]){const v=[];for(let i=0;i<6;i++){const a=-Math.PI/2+off+i*Math.PI/3;v.push([c+Math.cos(a)*R,c+Math.sin(a)*R]);}
  for(let i=0;i<6;i++){const p=v[i],q=v[(i+2)%6];g.line(p[0],p[1],q[0],q[1],off?2:1,'B');}}
 for(let i=0;i<12;i++){const a=-Math.PI/2+i*Math.PI/6;const u=U(g,c+Math.cos(a)*R,c+Math.sin(a)*R,4);u.circ(0,0,1,2,'B');u.dot(0,0,1,'B');}
 g.ring(58,3,'B',90,0.5); runeBand(g,52,24,seed+99,2,'B'); g.ring(47,2,'B');
 for(let i=0;i<24;i++){const a=i/24*Math.PI*2;g.line(c+Math.cos(a)*47,c+Math.sin(a)*47,c+Math.cos(a)*(i%2?43:40),c+Math.sin(a)*(i%2?43:40),3,'B');}
 // C — cœur : triple anneau, petites orbites, GRAND sigil (fixe)
 g.ring(36,1,'C'); g.ring(33.5,3,'C'); g.ring(31,2,'C');
 for(let i=0;i<6;i++){const a=i/6*Math.PI*2;g.set(c+Math.cos(a)*38.5,c+Math.sin(a)*38.5,1,'C');}
 SIGILS[element](U(g,c,c,24));
 for(const p of g.px.values())if(!p.layer)p.layer='C';
 return g;
}

// ---------- rendu PNG (même palette que gen_circles) ----------
function crc32(buf){let c,crc=0xffffffff;for(let n=0;n<buf.length;n++){c=(crc^buf[n])&0xff;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;crc=(crc>>>8)^c;}return (crc^0xffffffff)>>>0;}
function chunk(t,d){const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc32(td));return Buffer.concat([l,td,c]);}
function png(w,h,rgb){const raw=Buffer.alloc((w*3+1)*h);for(let y=0;y<h;y++){raw[y*(w*3+1)]=0;rgb.copy(raw,y*(w*3+1)+1,y*w*3,(y+1)*w*3);}
 const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=2;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
const PAL={Nature:['d6ffd8','34c46a','1c6a3c'],Lightning:['ffffff','ffe94f','3a6cff'],Arcane:['fbe8ff','c56bff','5a2a9e'],Toxic:['f8ffa0','c8ee1c','6a7a0c'],Fire:['fff3a1','ff8f26','c8301c'],Ice:['f0fdff','8fe3ff','2f7fd6']};
const hex=h=>[parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)];
function Canvas(w,h){this.w=w;this.h=h;this.b=Buffer.alloc(w*h*3);for(let i=0;i<w*h;i++){this.b[i*3]=10;this.b[i*3+1]=10;this.b[i*3+2]=16;}}
Canvas.prototype.add=function(x,y,col,a){if(x<0||y<0||x>=this.w||y>=this.h)return;const i=(y*this.w+x)*3;for(let k=0;k<3;k++)this.b[i+k]=Math.min(255,this.b[i+k]+col[k]*a);};
Canvas.prototype.put=function(x,y,col){if(x<0||y<0||x>=this.w||y>=this.h)return;const i=(y*this.w+x)*3;for(let k=0;k<3;k++)this.b[i+k]=Math.max(this.b[i+k],col[k]);};
function draw(cv,g,ox,oy,s,el){const P=PAL[el].map(hex);
 for(const p of g.px.values())for(let dy=-s;dy<2*s;dy++)for(let dx=-s;dx<2*s;dx++)cv.add(ox+p.x*s+dx,oy+p.y*s+dy,P[2],0.05);
 for(const p of g.px.values()){const col=P[p.lv-1];for(let dy=0;dy<s-1||dy==0;dy++)for(let dx=0;dx<s-1||dx==0;dx++)cv.put(ox+p.x*s+dx,oy+p.y*s+dy,col);}}

const show=process.argv.slice(2).length?process.argv.slice(2):['Fire','Arcane'];
const S=3, cellW=193*S+24, W=show.length*cellW+8, H=193*S+32;
const cv=new Canvas(W,H);
show.forEach((e,i)=>draw(cv,supreme(e,11+i*17),8+i*cellW+8,16,S,e));
const out=path.join(__dirname,'supreme_preview.png');fs.writeFileSync(out,png(W,H,cv.b));
console.log(out, W+'x'+H, show.map(e=>e+':'+supreme(e,1).px.size).join(' '));
module.exports={supreme};
