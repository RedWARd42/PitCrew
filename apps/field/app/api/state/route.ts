import {initializeStore} from '../../../../../services/core/store';
import {StateSchema} from '../../../../../packages/contracts';
export const dynamic='force-dynamic';
export async function GET(){const store=await initializeStore();return Response.json(StateSchema.parse(store.state),{headers:{'Cache-Control':'no-store'}});}
