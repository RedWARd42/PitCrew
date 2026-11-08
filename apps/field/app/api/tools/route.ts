import {initializeStore} from '../../../../../services/core/store';
import {executeTool,toolDefinitions} from '../../../../../services/agents/tools';
export const dynamic='force-dynamic';
export async function GET(){return Response.json(toolDefinitions);}
export async function POST(request:Request){try{const body=await request.json();if(typeof body.name!=='string')return Response.json({error:'Tool name is required'},{status:400});const store=await initializeStore();const result=await executeTool(store.state,body.name,body.input??{},command=>store.command(command),(name,input)=>store.advisoryTool(name,input));return Response.json({result});}catch(e){return Response.json({error:e instanceof Error?e.message:'Tool failed'},{status:400});}}
