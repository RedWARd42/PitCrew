import {createHash} from 'node:crypto';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {existsSync} from 'node:fs';
import {z} from 'zod';
import {ProcedureSchema} from '../../packages/contracts';
import compiled from '../../data/procedures/compiled.json';
import sources from '../../data/procedures/sources.json';
import {compilePdf} from './provider';

export const MAX_PDF_BYTES=10*1024*1024;
export class CompilerError extends Error{constructor(message:string,public status=400){super(message);}}
function rootPath(){const cwd=process.cwd();if(existsSync(join(cwd,'data','procedures','sources.json')))return cwd;return resolve(cwd,'../..');}
export const compilerSources=()=>sources.map(source=>({...source,downloadUrl:`/api/procedures/compile?source=${encodeURIComponent(source.procedureId)}`}));
export async function sourcePdf(id:string){const source=sources.find(s=>s.procedureId===id);if(!source)throw new CompilerError('Unknown seed source',404);return {bytes:await readFile(join(rootPath(),'data','procedures','source',source.filename)),filename:source.filename};}
export async function readPdfUpload(request:Request){
 const type=request.headers.get('content-type')??'';if(!type.toLowerCase().startsWith('multipart/form-data'))throw new CompilerError('Upload a PDF using multipart/form-data');
 const maxBody=MAX_PDF_BYTES+65536;if(Number(request.headers.get('content-length')??0)>maxBody)throw new CompilerError('PDF must be at most 10 MB',413);
 const reader=request.body?.getReader();if(!reader)throw new CompilerError('Upload body is required');
 const chunks:Uint8Array[]=[];let size=0;while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>maxBody){await reader.cancel();throw new CompilerError('PDF must be at most 10 MB',413);}chunks.push(value);}
 const buffer=Buffer.concat(chunks.map(chunk=>Buffer.from(chunk)));let form:FormData;try{form=await new Response(buffer,{headers:{'content-type':type}}).formData();}catch{throw new CompilerError('Invalid multipart upload');}
 const file=form.get('file');if(!(file instanceof Blob))throw new CompilerError('A PDF file field named file is required');if(file.size>MAX_PDF_BYTES)throw new CompilerError('PDF must be at most 10 MB',413);if(file.size===0)throw new CompilerError('PDF is empty');
 const bytes=new Uint8Array(await file.arrayBuffer());if(Buffer.from(bytes.subarray(0,5)).toString('ascii')!=='%PDF-')throw new CompilerError('File is not a PDF');
 const title=z.string().min(1).max(200).parse(form.get('title')??('name' in file?file.name:'Uploaded procedure'));
 return {bytes,title};
}
export async function compileUpload(bytes:Uint8Array,title:string,cacheMode:'only'|'prefer'|'live'){
 if(bytes.length>MAX_PDF_BYTES)throw new CompilerError('PDF must be at most 10 MB',413);
 const sourceHash=createHash('sha256').update(bytes).digest('hex');const known=sources.find(s=>s.sourceHash===sourceHash);
 let procedure:z.infer<typeof ProcedureSchema>;let mode:'deterministic-seed'|'live';
 if(known){const expected=compiled.find(p=>p.id===known.procedureId);if(!expected)throw new CompilerError('Compiled seed revision unavailable',500);procedure=ProcedureSchema.parse({...expected,approved:false});mode='deterministic-seed';}
 else {if(cacheMode==='only')throw new CompilerError('Offline compiler recognizes only the exact seeded PDF hashes. Select live inference to extract a new PDF.',422);if(!process.env.NVIDIA_API_KEY)throw new CompilerError('Live extraction requires NVIDIA_API_KEY configured on the server',503);try{procedure=await compilePdf(bytes,title);}catch{throw new CompilerError('Live PDF extraction failed. Verify the vision model endpoint supports PDF input; no procedure was approved.',502);}mode='live';}
 const artifact={id:`compile-${sourceHash.slice(0,16)}`,sourceHash,title,mode,source:known?.filename??'uploaded PDF',superseded:known?.superseded??false,procedure:ProcedureSchema.parse({...procedure,approved:false}),reviewRequired:true,notice:mode==='deterministic-seed'?'Exact seed PDF recognized by SHA-256; loaded the reviewed seed JSON. No model extraction was performed.':'Model-extracted draft. A qualified human must review all targets, preconditions and source labels before approval.'};
 const dir=join(rootPath(),'data','runtime','compiler');await mkdir(dir,{recursive:true});await writeFile(join(dir,`${sourceHash}.json`),JSON.stringify(artifact,null,2));return artifact;
}
