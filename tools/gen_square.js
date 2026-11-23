const fs=require('fs'),zlib=require('zlib'),path=require('path');
function crc32(b){let c,r=0xffffffff;for(let n=0;n<b.length;n++){c=(r^b[n])&0xff;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;r=(r>>>8)^c;}return (r^0xffffffff)>>>0;}
function chunk(t,d){const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc32(td));return Buffer.concat([l,td,c]);}
const W=16,raw=Buffer.alloc((W*4+1)*W);for(let y=0;y<W;y++){raw[y*(W*4+1)]=0;for(let x=0;x<W;x++){const i=y*(W*4+1)+1+x*4;raw[i]=255;raw[i+1]=255;raw[i+2]=255;raw[i+3]=255;}}
const ih=Buffer.alloc(13);ih.writeUInt32BE(W,0);ih.writeUInt32BE(W,4);ih[8]=8;ih[9]=6;
fs.writeFileSync(path.join(process.argv[2],'square.png'),Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]));
