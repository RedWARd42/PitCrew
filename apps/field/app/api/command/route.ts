import {initializeStore} from '../../../../../services/core/store';
import {CommandSchema,StateSchema} from '../../../../../packages/contracts';
export const dynamic='force-dynamic';
export async function POST(request:Request){try{const body=CommandSchema.safeParse(await request.json());if(!body.success)return Response.json({error:'Invalid command',details:body.error.flatten()},{status:400});const store=await initializeStore();const state=await store.command(body.data);void store.flushCommunications().catch(()=>undefined);return Response.json(StateSchema.parse(state));}catch(error){return Response.json({error:error instanceof Error?error.message:'Command failed'},{status:409});}}
