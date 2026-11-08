import {existsSync} from 'node:fs';
import {createHmac,randomUUID} from 'node:crypto';

async function main(){
 if(existsSync('.env'))process.loadEnvFile('.env');
 const origin=new URL(process.env.APP_URL??'http://localhost:3000').origin;
 const secret=process.env.PHOTON_WEBHOOK_SECRET,projectId=process.env.PHOTON_PROJECT_ID;
 if(!secret?.startsWith('whsec_')||!projectId)throw new Error('Configure the Photon Beta destination signing secret and project ID.');
 const request=(url:string,init:RequestInit={})=>fetch(url,{...init,headers:{'ngrok-skip-browser-warning':'1',...init.headers},signal:AbortSignal.timeout(30000)});
 const local=await request('http://127.0.0.1:3000/api/health');if(!local.ok)throw new Error('Local app health failed.');
 console.log(`Local health HTTP ${local.status}`);
 // The real operator token goes ONLY to localhost, never to ngrok.
 const localLogin=await request('http://127.0.0.1:3000/api/auth',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({token:process.env.DIRECTOR_TOKEN})});
 if(!localLogin.ok)throw new Error(`Local login with public Origin failed (${localLogin.status}).`);
 console.log(`Local login with configured public Origin HTTP ${localLogin.status}; credentials stayed on localhost.`);
 const publicLogin=await request(`${origin}/api/auth`,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({token:'deliberately-invalid-setup-probe-not-a-secret'})});
 const loginBody=await publicLogin.json() as {error?:string};
 if(publicLogin.status!==401||loginBody.error!=='Invalid access token')throw new Error(`Public origin test failed (${publicLogin.status}).`);
 console.log('Public login with a deliberately invalid non-secret value HTTP 401: origin check passed and token validation was reached.');
 const id=`setup-verification-${randomUUID()}`,timestamp=String(Math.floor(Date.now()/1000));
 const raw=JSON.stringify({id,type:'groundtruth.verification',apiVersion:process.env.PHOTON_WEBHOOK_API_VERSION??'2026-07-01',source:'groundtruth.setup',timestamp:new Date().toISOString(),data:{projectId,object:{id:'synthetic-setup-probe'}}});
 const signature=createHmac('sha256',Buffer.from(secret.slice(6),'base64')).update(`${id}.${timestamp}.${raw}`).digest('base64');
 const headers={'Content-Type':'application/json','webhook-id':id,'webhook-timestamp':timestamp,'webhook-signature':`v1,${signature}`};
 const valid=await request(`${origin}/api/photon/webhook`,{method:'POST',headers,body:raw});
 const validBody=await valid.json() as {received?:boolean};
 if(!valid.ok||validBody.received!==true)throw new Error(`Signed setup probe rejected (${valid.status}).`);
 console.log(`Public synthetic signed webhook HTTP ${valid.status}: accepted and audited. No actual Photon message or call was sent.`);
 const tampered=await request(`${origin}/api/photon/webhook`,{method:'POST',headers,body:raw+' '});
 if(tampered.ok)throw new Error('Tampered webhook was incorrectly accepted.');
 console.log(`Tampered webhook HTTP ${tampered.status}: rejected.`);
 console.log('This verifies receiver configuration with the local signing secret, not actual Photon-origin delivery or equality with Photon’s stored secret.');
}
void main().catch(error=>{console.error(error instanceof Error?error.message:'Setup verification failed');process.exitCode=1;});
