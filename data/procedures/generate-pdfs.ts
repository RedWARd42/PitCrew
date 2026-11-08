import {writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {procedures} from '../../services/sim';

// Small, dependency-free PDF writer used only to author fictional demo source documents.
const escape=(s:string)=>s.replaceAll('\\','\\\\').replaceAll('(','\\(').replaceAll(')','\\)').replace(/[^\x20-\x7e]/g,'-');
const wrap=(s:string,width=85)=>s.match(new RegExp(`.{1,${width}}(?:\\s|$)|\\S+`,'g'))?.map(x=>x.trim())??[s];
function buildPdf(id:string,title:string,revision:number,approved:boolean,steps:typeof procedures[number]['steps']){
 const commands:string[]=[];
 const text=(x:number,y:number,s:string,size=10,font='F1')=>commands.push(`BT /${font} ${size} Tf ${x} ${y} Td (${escape(s)}) Tj ET`);
 const line=(x:number,y:number,x2:number,y2:number)=>commands.push(`${x} ${y} m ${x2} ${y2} l S`);
 commands.push('0.12 0.18 0.22 rg');commands.push('36 694 540 62 re f');commands.push('1 1 1 rg');text(50,733,'GROUNDTRUTH / NMC2 DAL-1',12,'F2');text(50,712,`METHOD OF PROCEDURE  |  ${id}  |  REV ${revision}`,10);commands.push('0.12 0.18 0.22 rg');
 let y=669;for(const row of wrap(title,65)){text(40,y,row,17,'F2');y-=22;}
 text(40,y-3,'FICTIONAL TRAINING DOCUMENT - NOT AN OPERATING INSTRUCTION',9,'F2');y-=27;
 text(40,y,`Document status: ${approved?'Reviewed seed revision':'SUPERSEDED - DO NOT EXECUTE'}     Site: Hall 2     Permit: DEMO-026`,9);y-=22;
 text(40,y,'Prerequisites / sign-off',11,'F2');y-=17;
 text(40,y,'Qualified technician, current work permit, local indications and chief engineer approval.',9);y-=15;
 text(40,y,'Read-back required before each step. Guardian advice never operates plant equipment.',9);y-=25;
 text(40,y,'One-line context (simplified; verify actual field labels)',10,'F2');y-=38;
 const power=/UPS|PDU/.test(id);const labels=power?['UPS-1 / A','PDU-4 / B','Row D','UPS-2 / B']:/BAT/.test(id)?['UPS-2 DC bus','VRLA string 3','Cell test taps','Impedance meter']:/CDU/.test(id)?['CHW loop','Plate exchanger','CDU filter','Row D supply']:/PUMP/.test(id)?['CHW header','P-2 duty','Isolation valves','P-3 standby']:['CH-1','CH-2','CHW header','CH-3 standby'];
 labels.forEach((label,i)=>{const x=40+i*135;commands.push(`${x} ${y} 120 28 re S`);text(x+5,y+10,label,8);if(i<3)line(x+120,y+14,x+135,y+14);});
 y-=26;text(40,y,power?'Margin note: UPS-2 bypass can leave Row D dependent on PDU-4.':/BAT/.test(id)?'Margin note: normal string voltage does not rule out cell impedance degradation.':/CDU/.test(id)?'Margin note: verify an independent coolant path before any flow interruption.':'Margin note: confirm flow and restart temperature limits before requesting a restart.',8);y-=25;
 commands.push('0.92 0.94 0.95 rg');commands.push(`40 ${y-6} 532 23 re f`);commands.push('0.12 0.18 0.22 rg');text(47,y+2,'STEP',9,'F2');text(92,y+2,'ACTION / VERIFICATION',9,'F2');y-=26;
 for(const step of steps){const rows=wrap(step.text,80);const verification=wrap(`Verify: ${step.verification}`,83);text(47,y,String(step.number),10,'F2');for(const row of rows){text(92,y,row,9);y-=13;}for(const row of verification){text(92,y,row,8);y-=12;}if(step.preconditions.length){text(92,y,`Gate: ${step.preconditions.join('; ')}`,8,'F2');y-=12;}y-=8;line(40,y+3,572,y+3);y-=12;}
 text(40,45,'Prepared: Operations training team | Reviewed: Shift lead | 2026-11-07',8);text(40,31,'Stop if labels, version, plant state or permit do not match. Record uncertainty and contact the chief.',8);text(541,31,'1 / 1',8);
 const stream=commands.join('\n');const objects=[`<< /Type /Catalog /Pages 2 0 R >>`,`<< /Type /Pages /Kids [3 0 R] /Count 1 >>`,`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>`,`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>`,`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>`,`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`];
 let pdf='%PDF-1.4\n';const offsets=[0];objects.forEach((obj,i)=>{offsets.push(Buffer.byteLength(pdf));pdf+=`${i+1} 0 obj\n${obj}\nendobj\n`;});const start=Buffer.byteLength(pdf);pdf+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.slice(1).map(o=>`${String(o).padStart(10,'0')} 00000 n \n`).join('')}trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`;return Buffer.from(pdf);
}
mkdirSync('data/procedures/source',{recursive:true});
const sources=procedures.map(p=>{const pdf=buildPdf(p.id,p.title,p.version,p.approved,p.steps);const filename=`${p.id}-rev${p.version}.pdf`;writeFileSync(`data/procedures/source/${filename}`,pdf);return {procedureId:p.id,title:p.title,filename,revision:p.version,sourceHash:createHash('sha256').update(pdf).digest('hex'),bytes:pdf.length,superseded:!p.approved};});
writeFileSync('data/procedures/sources.json',JSON.stringify(sources,null,2));
console.log(`Generated ${sources.length} fictional source PDFs and SHA-256 manifest.`);

