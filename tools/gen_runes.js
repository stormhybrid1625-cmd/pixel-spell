// gen_runes.js — RUNES DE MODIFICATEURS gravées sur les cercles magiques.
// Une rune UNIQUE par modificateur (clé = Id de la carte). Les points sous la rune = nombre d'empilements (stack).
// Sortie : planche d'aperçu + un PNG transparent par rune (sprites/circles/runes/<ID>.png) pour l'import Roblox.
const fs = require('fs'), path = require('path'), zlib = require('zlib');

function Grid(n){this.n=n;this.c=(n-1)/2;this.px=new Map();}
Grid.prototype.set=function(x,y,lv){x=Math.round(x);y=Math.round(y);if(x<0||y<0||x>=this.n||y>=this.n)return;const k=x+','+y;const o=this.px.get(k);if(!o||lv<o.lv)this.px.set(k,{x,y,lv});};
Grid.prototype.line=function(x0,y0,x1,y1,lv){const d=Math.max(Math.abs(x1-x0),Math.abs(y1-y0))*1.5+1;for(let i=0;i<=d;i++){const t=i/d;this.set(x0+(x1-x0)*t,y0+(y1-y0)*t,lv);}};
function U(g,cx,cy,s){return{P:(x,y)=>[cx+x*s,cy-y*s],
 line(a,b,lv=1){const p=this.P(...a),q=this.P(...b);g.line(p[0],p[1],q[0],q[1],lv);},
 poly(pts,lv=1,closed=true){for(let i=0;i<pts.length-(closed?0:1);i++)this.line(pts[i],pts[(i+1)%pts.length],lv);},
 circ(x,y,r,lv=1,a0=0,a1=Math.PI*2){const p=this.P(x,y);const rr=r*s;const st=Math.max(10,Math.ceil(rr*8*(a1-a0)/(Math.PI*2)));for(let i=0;i<=st;i++){const a=a0+(a1-a0)*i/st;g.set(p[0]+Math.cos(a)*rr,p[1]-Math.sin(a)*rr,lv);}},
 dot(x,y,lv=1){const p=this.P(x,y);g.set(p[0],p[1],lv);},
 bez(a,c,b,lv=1){let prev=a;for(let i=1;i<=24;i++){const t=i/24,v=1-t;const p=[v*v*a[0]+2*v*t*c[0]+t*t*b[0],v*v*a[1]+2*v*t*c[1]+t*t*b[1]];this.line(prev,p,lv);prev=p;}},
 arrow(tip,dx,dy,len=0.3,lv=2){const n=Math.hypot(dx,dy);dx/=n;dy/=n;const bx=tip[0]-dx*len,by=tip[1]-dy*len;this.line(tip,[bx-dy*len,by+dx*len],lv);this.line(tip,[bx+dy*len,by-dx*len],lv);}};}

const sq=(u,r,lv)=>u.poly([[-r,-r],[r,-r],[r,r],[-r,r]],lv);
const fork=(u,n)=>{u.line([0,-0.95],[0,-0.1]);for(let i=0;i<n;i++){const x=n==1?0:-0.8+1.6*i/(n-1);u.line([0,-0.1],[x,0.9]);u.dot(x,0.9,2);}};
const hourglass=u=>{u.line([-0.7,0.95],[0.7,0.95]);u.line([-0.7,-0.95],[0.7,-0.95]);u.line([-0.6,0.95],[0.6,-0.95]);u.line([0.6,0.95],[-0.6,-0.95]);};

// ---------- une rune par modificateur (espace -1..1, y vers le haut) ----------
const RUNES = {
 // Puissance
 DAMAGE_PLUS(u){u.poly([[0,1],[-0.7,0],[0.7,0]]);u.line([-0.3,0],[-0.3,-0.55]);u.line([0.3,0],[0.3,-0.55]);u.line([-0.75,-0.55],[0.75,-0.55],2);},
 EXPLOSIVE(u){u.circ(0,0,0.38);for(let i=0;i<8;i++){const a=i*Math.PI/4;u.line([Math.cos(a)*0.6,Math.sin(a)*0.6],[Math.cos(a)*0.95,Math.sin(a)*0.95],2);}},
 DETONATE(u){u.line([-0.9,0],[0.9,0]);u.line([0,-0.9],[0,0.9]);u.line([-0.55,-0.55],[0.55,0.55],2);u.line([-0.55,0.55],[0.55,-0.55],2);u.circ(0,0,0.25,1);},
 KNOCKBACK(u){u.line([-0.85,-0.9],[-0.85,0.9],2);u.poly([[-0.4,0.6],[0.1,0],[-0.4,-0.6]],1,false);u.poly([[0.2,0.6],[0.7,0],[0.2,-0.6]],1,false);},
 HEAVY(u){u.poly([[-0.45,0.2],[0.45,0.2],[0.8,-0.9],[-0.8,-0.9]]);u.circ(0,0.55,0.3,2);u.line([-0.4,-0.45],[0.4,-0.45],2);},
 // Taille
 SIZE_PLUS(u){sq(u,0.9,1);sq(u,0.3,2);},
 SIZE_PLUS_2(u){sq(u,0.9,1);sq(u,0.55,2);sq(u,0.2,2);},
 SIZE_PLUS_3(u){sq(u,0.9,1);sq(u,0.62,2);sq(u,0.36,2);u.dot(0,0,1);},
 // Temps
 SPEED_PLUS(u){u.line([-0.9,0.45],[0.2,0.45],2);u.line([-0.6,0],[0.85,0]);u.line([-0.9,-0.45],[0.2,-0.45],2);u.arrow([0.85,0],1,0,0.4,1);},
 QUICK(u){u.poly([[0.35,1],[-0.4,0.05],[0.25,0.05],[-0.35,-1]],1,false);u.arrow([-0.35,-1],-0.6,-1,0.3,2);},
 RECHARGE_DOWN(u){u.circ(0,0,0.75,1,0.5,Math.PI*2-0.1);u.arrow([Math.cos(0.5)*0.75,Math.sin(0.5)*0.75],-0.5,1,0.35,2);u.dot(0,0,2);},
 DURATION_PLUS(u){hourglass(u);u.line([-0.2,-0.7],[0.2,-0.7],2);u.line([-0.35,-0.8],[0.35,-0.8],2);},
 DURATION_ZERO(u){hourglass(u);u.line([-1,-1],[1,1],2);},
 // Trajectoire
 SPIRAL(u){let prev=[0,0];for(let i=1;i<=80;i++){const a=i/80*Math.PI*4.2,r=i/80*0.95;const p=[Math.cos(a)*r,Math.sin(a)*r];u.line(prev,p);prev=p;}},
 WAVE(u){let prev=[-0.95,0];for(let i=1;i<=40;i++){const x=-0.95+1.9*i/40;const p=[x,Math.sin(i/40*Math.PI*3)*0.5];u.line(prev,p);prev=p;}u.arrow(prev,1,-0.6,0.3);},
 ORBIT(u){u.circ(0,0,0.85,2);u.circ(0,0,0.2,1);u.dot(0,0);u.circ(0.6,0.6,0.15,1);},
 BOOMERANG(u){u.bez([-0.8,0.7],[0.95,0.5],[0.6,0]);u.bez([0.6,0],[0.95,-0.5],[-0.8,-0.7]);u.arrow([-0.8,-0.7],-1,-0.1,0.35,2);},
 HOMING(u){u.circ(0,0,0.6);u.dot(0,0,1);u.circ(0,0,0.1,1);for(const[a,b]of[[[0,0.95],[0,0.7]],[[0,-0.95],[0,-0.7]],[[0.95,0],[0.7,0]],[[-0.95,0],[-0.7,0]]])u.line(a,b,2);},
 // Traversée
 BOUNCE(u){u.line([-0.95,-0.85],[0.95,-0.85],2);u.line([-0.8,0.9],[0,-0.75]);u.line([0,-0.75],[0.8,0.9]);u.arrow([0.8,0.9],0.5,1,0.3);},
 PIERCE(u){u.line([0,-0.95],[0,0.95],2);u.line([-0.95,0],[0.95,0]);u.arrow([0.95,0],1,0,0.35,1);},
 IGNORE_OBSTACLES(u){for(const x of[-0.45,0.15]){for(let y=-0.9;y<0.95;y+=0.45)u.line([x,y],[x,y+0.2],2);}u.line([-0.95,0.05],[0.9,0.05]);u.arrow([0.9,0.05],1,0,0.35,1);},
 // Division
 DIVIDE_2(u){fork(u,2);},
 DIVIDE_3(u){fork(u,3);},
 DIVIDE_4(u){fork(u,4);},
 FRAGMENT(u){sq(u,0.22,1);for(const[x,y]of[[1,1],[-1,1],[1,-1],[-1,-1]]){u.poly([[x*0.55,y*0.5],[x*0.9,y*0.6],[x*0.65,y*0.9]],2);}},
 // Déclencheur
 ADD_TRIGGER(u){u.circ(-0.3,0,0.55,1,0.6,Math.PI*2-0.6);u.line([0.15,0],[0.95,0]);u.arrow([0.95,0],1,0,0.3,1);u.dot(-0.3,0,2);},
 ADD_TIMER(u){u.circ(0,-0.1,0.8);u.line([0,-0.1],[0,0.45],2);u.line([0,-0.1],[0.35,-0.3],2);u.line([-0.2,0.95],[0.2,0.95]);},
 ADD_EXPIRE(u){u.line([-0.95,0],[0.4,0]);u.line([0.4,-0.6],[0.4,0.6],2);for(const a of[-0.8,0,0.8])u.line([0.55,Math.sin(a)*0.25],[0.55+Math.cos(a)*0.4,Math.sin(a)*0.7],2);},
 CAST_HOLD(u){u.poly([[-0.5,0.9],[-0.85,0.9],[-0.85,-0.9],[-0.5,-0.9]],1,false);u.poly([[0.5,0.9],[0.85,0.9],[0.85,-0.9],[0.5,-0.9]],1,false);u.circ(0,0,0.25,2);u.dot(0,0,1);},
 // Mana
 ADD_MANA(u){u.line([0,1],[-0.58,-0.2]);u.line([0,1],[0.58,-0.2]);u.circ(0,-0.35,0.6,1,Math.PI-0.25,Math.PI*2+0.25);u.dot(-0.2,-0.15,2);},
 TRAIL_FIRE(u){u.circ(0.55,0,0.35,1);u.line([0.15,0.55],[-0.6,0.55],2);u.line([0.1,0],[-0.95,0],2);u.line([0.15,-0.55],[-0.6,-0.55],2);u.dot(-0.85,0.55,2);u.dot(-0.85,-0.55,2);},
 // Croissance (procédural)
 BRANCH_PLUS(u){u.line([0,-0.95],[0,0.95]);u.line([0,-0.1],[-0.6,0.45]);u.line([0,-0.1],[0.6,0.45]);u.line([0,0.45],[-0.4,0.85],2);u.line([0,0.45],[0.4,0.85],2);u.line([-0.45,-0.95],[0.45,-0.95],2);},
 CAGE(u){u.line([-0.85,0.9],[0.85,0.9],2);u.line([-0.85,-0.9],[0.85,-0.9],2);for(const x of[-0.7,-0.23,0.23,0.7])u.line([x,0.9],[x,-0.9]);},
};
const ORDER=[['Puissance',['DAMAGE_PLUS','EXPLOSIVE','DETONATE','KNOCKBACK','HEAVY']],['Taille',['SIZE_PLUS','SIZE_PLUS_2','SIZE_PLUS_3']],
 ['Temps',['SPEED_PLUS','QUICK','RECHARGE_DOWN','DURATION_PLUS','DURATION_ZERO']],['Trajectoire',['SPIRAL','WAVE','ORBIT','BOOMERANG','HOMING']],
 ['Traversée',['BOUNCE','PIERCE','IGNORE_OBSTACLES']],['Division',['DIVIDE_2','DIVIDE_3','DIVIDE_4','FRAGMENT']],
 ['Déclencheur',['ADD_TRIGGER','ADD_TIMER','ADD_EXPIRE','CAST_HOLD']],['Mana',['ADD_MANA','TRAIL_FIRE']],['Croissance',['BRANCH_PLUS','CAGE']]];

// stack = nombre d'empilements (points sous la rune, seulement si >= 2)
function rune(id,stack=1){const g=new Grid(25);const u=U(g,g.c,g.c-2,8);RUNES[id](u);if(stack>=2)for(let i=0;i<stack;i++)u.dot((i-(stack-1)/2)*0.42,-1.35,1);return g;}

// ---------- PNG ----------
function crc32(buf){let c,crc=0xffffffff;for(let n=0;n<buf.length;n++){c=(crc^buf[n])&0xff;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;crc=(crc>>>8)^c;}return (crc^0xffffffff)>>>0;}
function chunk(t,d){const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc32(td));return Buffer.concat([l,td,c]);}
function png(w,h,px,ch){const raw=Buffer.alloc((w*ch+1)*h);for(let y=0;y<h;y++){raw[y*(w*ch+1)]=0;px.copy(raw,y*(w*ch+1)+1,y*w*ch,(y+1)*w*ch);}
 const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=ch==4?6:2;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}

if(require.main===module){
 const COL=[[255,232,170],[230,170,90]];
 const S=6,cell=25*S+18,cols=5,W=cols*cell+20,H=ORDER.length*cell+20;
 const b=Buffer.alloc(W*H*3);for(let i=0;i<W*H;i++){b[i*3]=12;b[i*3+1]=11;b[i*3+2]=18;}
 const put=(x,y,c)=>{if(x<0||y<0||x>=W||y>=H)return;const i=(y*W+x)*3;b[i]=c[0];b[i+1]=c[1];b[i+2]=c[2];};
 ORDER.forEach(([_,ids],row)=>ids.forEach((id,k)=>{const g=rune(id,1);const ox=10+k*cell+9,oy=10+row*cell+9;
  for(let y=-2;y<25*S+2;y++)for(let x=-2;x<25*S+2;x++)if(x<0||y<0||x>=25*S||y>=25*S)put(ox+x,oy+y,[40,36,52]);
  for(const p of g.px.values()){const c=COL[p.lv-1]||COL[1];for(let dy=0;dy<S-1;dy++)for(let dx=0;dx<S-1;dx++)put(ox+p.x*S+dx,oy+p.y*S+dy,c);}}));
 const out=path.join(__dirname,'..','sprites','circles','runes_modificateurs.png');fs.writeFileSync(out,png(W,H,b,3));
 // export individuel : blanc sur transparent (teinté en jeu), 25px x4 = 100px, sans points (les points sont posés en jeu)
 const dir=path.join(__dirname,'..','sprites','circles','runes');fs.mkdirSync(dir,{recursive:true});
 for(const id of Object.keys(RUNES)){const g=rune(id,1),Z=4,n=25*Z;const a=Buffer.alloc(n*n*4);
  for(const p of g.px.values()){const v=p.lv==1?255:200;for(let dy=0;dy<Z;dy++)for(let dx=0;dx<Z;dx++){const i=((p.y*Z+dy)*n+p.x*Z+dx)*4;a[i]=v;a[i+1]=v;a[i+2]=v;a[i+3]=255;}}
  fs.writeFileSync(path.join(dir,id+'.png'),png(n,n,a,4));}
 // ATLAS : 6 colonnes x 100 px (blanc/transparent) -> une seule image Roblox, découpée par ImageRectOffset
 const ids=Object.keys(RUNES),C=6,Z=4,n=100,AW=C*n,AH=Math.ceil(ids.length/C)*n,at=Buffer.alloc(AW*AH*4),idx={};
 ids.forEach((id,k)=>{const g=rune(id,1),ox=(k%C)*n,oy=Math.floor(k/C)*n;idx[id]=[ox,oy];
  for(const p of g.px.values()){const v=p.lv==1?255:205;for(let dy=0;dy<Z;dy++)for(let dx=0;dx<Z;dx++){const i=((oy+p.y*Z+dy)*AW+ox+p.x*Z+dx)*4;at[i]=v;at[i+1]=v;at[i+2]=v;at[i+3]=255;}}});
 fs.writeFileSync(path.join(dir,'atlas.png'),png(AW,AH,at,4));
 fs.writeFileSync(path.join(dir,'atlas.lua'),'return {'+ids.map(id=>`${id}={${idx[id][0]},${idx[id][1]}}`).join(',')+'}');
 console.log(out,W+'x'+H,ids.length+' runes, atlas '+AW+'x'+AH);
}
module.exports={RUNES,ORDER,rune};
