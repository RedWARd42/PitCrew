import {Spectrum,app as appCard,edit,poll,rename} from 'spectrum-ts';
import {imessage} from 'spectrum-ts/providers/imessage';
import {contacts,allowedPhone} from './contacts';
import type {Message,PlantState} from '../../packages/contracts';
import type {DeliveryAdapter} from './index';

function assertLive(){if(process.env.COMMS_MODE!=='live')throw new Error('Photon live delivery is disabled');if(!process.env.PHOTON_PROJECT_ID||!process.env.PHOTON_PROJECT_SECRET)throw new Error('Photon project credentials are missing');if(process.env.PHOTON_PROJECT_ID.startsWith('pho_prj_'))throw new Error('Beta project credentials cannot be used with Stable Spectrum');}
async function createPhoton(){assertLive();return Spectrum({projectId:process.env.PHOTON_PROJECT_ID!,projectSecret:process.env.PHOTON_PROJECT_SECRET!,webhookSecret:process.env.PHOTON_WEBHOOK_SECRET,providers:[imessage.config()]});}
let instance:ReturnType<typeof createPhoton>|undefined;
export function getPhoton(){return instance??=createPhoton().catch(error=>{instance=undefined;throw error;});}
type Photon=Awaited<ReturnType<typeof createPhoton>>;
async function createDm(client:Photon,phone:string){const provider=imessage(client);return provider.space.create(await provider.user(phone));}
type Space=Awaited<ReturnType<typeof createDm>>;
const spaces=new Map<string,Space>();
async function sendCard(space:Space,url:string){return space.send(appCard(url,{live:true}));}
const cards=new Map<string,NonNullable<Awaited<ReturnType<typeof sendCard>>>>();
async function dm(client:Photon,personId:string){const phone=allowedPhone(personId);const key=`dm:${phone}`;const existing=spaces.get(key);if(existing)return existing;const space=await createDm(client,phone);spaces.set(key,space);return space;}
export const photonAdapter:DeliveryAdapter={async send(message:Message){
 assertLive();if(message.channel==='voice')throw new Error('SIP worker is not configured; call remains simulated');
 const client=await getPhoton(),space=await dm(client,message.personId);
 // Keep sensitive evidence inside the app; external messages contain a minimal brief.
 const url=new URL(message.entityId==='handover'?'/handover':`/warnings/${encodeURIComponent(message.entityId)}`,process.env.APP_URL??'http://localhost:3000');
 if(url.hostname==='localhost')throw new Error('Live app cards require an authenticated public HTTPS app URL');
 if(url.protocol!=='https:')throw new Error('Live app cards require HTTPS');
 const key=`${message.personId}:${message.entityId}`;
 const previous=cards.get(key);
 if(previous){await space.send(edit(appCard(url.toString(),{live:true}),previous));}
 else{await space.send('Groundtruth: an operations item needs your read-back. Open the secure app for details.');const card=await sendCard(space,url.toString());if(card)cards.set(key,card);await space.send(poll('Can you take ownership?','Open app and own','Need help'));}
}};
export async function openIncidentGroup(state:PlantState,incidentId:string){
 const client=await getPhoton(),provider=imessage(client);
 const people=['maria','dev','sam','priya'];
 const users=await Promise.all(people.map(async id=>provider.user(allowedPhone(id))));
 const group=await provider.space.create(users);await group.send(rename(`${incidentId} · Operations response`));await group.send('Groundtruth incident response. Open the authenticated app for operational details.');spaces.set(`incident:${incidentId}`,group);return group;
}
const seen=new Set<string>();
/** SDK verifies the exact raw-body signature and replay window before invoking this handler. */
export async function photonWebhook(request:Request,callbacks:{ack:(warningId:string,readback:string,personId:string)=>Promise<void>;question:(text:string)=>Promise<string>}){
 if(!process.env.PHOTON_WEBHOOK_SECRET)return new Response('Webhook is not configured',{status:503});
 const client=await getPhoton();
 return client.webhook(request,async(space,message)=>{
  if(seen.has(message.id))return;
  const personId=Object.entries(contacts()).find(([,phone])=>phone===message.sender?.id)?.[0];
  if(!personId)return;allowedPhone(personId);
  if(message.content.type!=='text')return;
  const match=/^own\s+(\S+)\s+(.{8,1000})$/i.exec(message.content.text.trim());
  if(match){await callbacks.ack(match[1],match[2],personId);seen.add(message.id);await space.send('Ownership recorded with your read-back.');}
  else{seen.add(message.id);await space.send(await callbacks.question(message.content.text));}
 });
}
