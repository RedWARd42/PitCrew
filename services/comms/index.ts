import type { Message, PlantState, Warning } from '../../packages/contracts';
import {voiceIsLive} from './elevenlabs';

function audit(state:PlantState,action:string,detail:string){state.audit.push({id:`audit-${state.audit.length+1}`,ts:state.clock,action,detail});}
export function enqueue(state:PlantState,personId:string,entityId:string,text:string,channel:Message['channel']='terminal'):Message {
 const simulated=channel==='terminal'||(channel==='voice'&&!voiceIsLive());
 const message:Message={id:`msg-${state.messages.length+1}`,personId,entityId,channel,direction:'outbound',text,status:simulated?'simulated':'queued',ts:state.clock};
 state.messages.push(message);audit(state,'message.outbound',`${message.id}: ${channel} to ${personId}`);return message;
}
export function notifyWarning(state:PlantState,warning:Warning){
 if(state.messages.some(m=>m.entityId===warning.id&&m.direction==='outbound'))return;
 enqueue(state,warning.ownerId,warning.id,`${warning.severity.toUpperCase()} · ${warning.title}. Action due ${warning.dueAt}. Reply: own ${warning.id} <your next action and deadline>.`,process.env.COMMS_MODE==='live'?'imessage':'terminal');
}
export function acknowledge(state:PlantState,warning:Warning,readback:string){
 if(!readback.trim()||readback.trim().length<8)throw new Error('A concrete read-back is required.');
 warning.state='owned';warning.readback=readback;
 state.messages.push({id:`msg-${state.messages.length+1}`,personId:warning.ownerId,entityId:warning.id,channel:'terminal',direction:'inbound',text:readback,status:'acked',ts:state.clock});
 for(const m of state.messages.filter(m=>m.entityId===warning.id&&m.direction==='outbound'))m.status='acked';
 audit(state,'warning.acked',`${warning.id}: ${readback}`);
}
export function processEscalations(state:PlantState){
 for(const warning of state.warnings){
  if(warning.state==='owned'||warning.state==='resolved')continue;
  notifyWarning(state,warning);
  const elapsed=(Date.parse(state.clock)-Date.parse(warning.createdAt))/1000;
  const initial=state.messages.find(m=>m.entityId===warning.id&&m.direction==='outbound');
  if(elapsed>=20&&warning.escalationLevel===0&&initial?.status==='read'){
   warning.escalationLevel=1;enqueue(state,warning.ownerId,warning.id,'Read, not acknowledged. Reply with your next action and deadline.');audit(state,'warning.nudged',warning.id);
  }
  if(elapsed>=45&&warning.escalationLevel<2){
   warning.escalationLevel=2;warning.state='escalated';warning.ownerId='dev';
   enqueue(state,'dev',warning.id,`Escalated: ${warning.title}. No read-back from the first owner. Please take ownership.`,process.env.COMMS_MODE==='live'?'imessage':'terminal');
   enqueue(state,'dev',warning.id,voiceIsLive()?`${warning.title}. ${warning.nextAction}. Say “I own it” followed by your next action and deadline.`:`SIMULATED CALL · ${warning.title}. ${warning.nextAction}. Say “I own it” followed by your next action. No phone call was placed.`,'voice');
   audit(state,'warning.escalated',`${warning.id}: owner → chief → ${voiceIsLive()?'ElevenLabs call queued':'simulated voice call'}`);
  }
 }
}
export function sendHandover(state:PlantState){
 const text=state.handover.map(i=>`${i.id} · ${i.assetId}: ${i.summary}. Action: ${i.action}. Contingency: ${i.contingency}.`).join('\n');
 enqueue(state,'alex','handover',`I-PASS · Incoming shift\n${text}\nConfirm each critical item in the app with a read-back.`,process.env.COMMS_MODE==='live'?'imessage':'terminal');
}
export interface DeliveryAdapter{send(message:Message):Promise<void>}
/** Idempotent per process. Failed deliveries remain visible and are never silently retried. */
export async function flushOutbound(state:PlantState,adapter?:DeliveryAdapter,checkpoint?:()=>Promise<void>){
 if(!adapter)return;
 for(const message of state.messages){
  if(message.status!=='queued')continue;
  message.status='sending';await checkpoint?.();
  try{await adapter.send(message);message.status='sent';audit(state,message.channel==='voice'?'voice.request_accepted':'message.delivered',message.id);}
  catch{message.status='failed';audit(state,'message.failed',`${message.id}: delivery failed; use phone mirror`);}
  await checkpoint?.();
 }
}
