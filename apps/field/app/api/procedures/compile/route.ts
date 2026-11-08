import {CompilerError,compilerSources,sourcePdf,readPdfUpload,compileUpload} from '../../../../../../services/agents/compiler-api';
import {initializeStore} from '../../../../../../services/core/store';
export const dynamic='force-dynamic';
export const runtime='nodejs';
// API access is enforced centrally by middleware, including HttpOnly sessions.

export async function GET(request:Request){try{const source=new URL(request.url).searchParams.get('source');if(!source)return Response.json({sources:compilerSources()});const pdf=await sourcePdf(source);return new Response(pdf.bytes,{headers:{'content-type':'application/pdf','content-disposition':`inline; filename="${pdf.filename}"`,'cache-control':'private, max-age=3600'}});}catch(error){return failure(error);}}
export async function POST(request:Request){try{const {bytes,title}=await readPdfUpload(request);const store=await initializeStore();const artifact=await compileUpload(bytes,title,store.state.cacheMode);return Response.json(artifact,{status:201});}catch(error){return failure(error);}}
function failure(error:unknown){return Response.json({error:error instanceof Error?error.message:'Procedure compilation failed'},{status:error instanceof CompilerError?error.status:400});}


