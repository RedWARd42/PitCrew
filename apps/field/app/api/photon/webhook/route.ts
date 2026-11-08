import {initializeStore} from '../../../../../../services/core/store';
import {photonWebhook} from '../../../../../../services/comms/photon';
import {answerPlantQuestion} from '../../../../../../services/agents';
import {parsePhotonWebhook} from '../../../../../../services/comms/photon-beta';
export const runtime='nodejs';
export async function POST(request:Request){
 try{
 if(process.env.PHOTON_PROJECT_ID?.startsWith('pho_prj_')){
  const event=await parsePhotonWebhook(request);const store=await initializeStore();await store.photonEvent(event);void store.flushCommunications().catch(()=>undefined);return Response.json({received:true});
 }
 const store=await initializeStore();return await photonWebhook(request,{ack:async(warningId,readback,personId)=>{const warning=store.state.warnings.find(w=>w.id===warningId);if(!warning||warning.ownerId!==personId)throw new Error('Only the assigned owner can acknowledge');await store.command({type:'ack',warningId,readback});},question:async(text)=>answerPlantQuestion(store.state,text).answer});}
 catch{return Response.json({error:'Photon is unavailable or not configured'},{status:503});}
}
