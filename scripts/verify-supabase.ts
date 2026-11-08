import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createInitialState} from '../services/sim';
import {StateSchema} from '../packages/contracts';

async function main(){
const envPath=resolve('.env');
if(existsSync(envPath))process.loadEnvFile(envPath);
const url=process.env.SUPABASE_URL?.replace(/\/$/,''),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!url||!key){console.error('Configure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in root .env. No request was sent.');process.exitCode=1;}
else{
 const expectedProject='https://hrkuvnanhchdvinviaii.supabase.co';
 if(url!==expectedProject)throw new Error('Verification is scoped to the existing Groundtruth project. Check SUPABASE_URL.');
 const id=`setup-check-${randomUUID()}`;
 const headers={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
 const endpoint=`${url}/rest/v1/plant_snapshot`;
 const call=async(path:string,init:RequestInit={})=>{
  const response=await fetch(path,{...init,headers:{...headers,...init.headers},signal:AbortSignal.timeout(10000)});
  if(!response.ok){
   const problem=await response.json().catch(()=>null) as {code?:unknown;message?:unknown}|null;
   const code=typeof problem?.code==='string'?problem.code:'unknown';
   const message=typeof problem?.message==='string'?problem.message.slice(0,300):'Check migration, grants, and server key.';
   throw new Error(`Supabase verification request failed (${response.status}, ${code}): ${message}`);
  }
  return response;
 };
 let created=false;
 try{
  const seed=StateSchema.parse(createInitialState());
  await call(endpoint,{method:'POST',body:JSON.stringify({id,data:seed})});created=true;
  const updated={...seed,paused:!seed.paused};
  await call(endpoint,{method:'POST',headers:{Prefer:'resolution=merge-duplicates'},body:JSON.stringify({id,data:updated})});
  const response=await call(`${endpoint}?id=eq.${encodeURIComponent(id)}&select=data`);
  const rows:unknown=await response.json();
  if(!Array.isArray(rows)||rows.length!==1)throw new Error('Verification row was not returned.');
  const loaded=StateSchema.parse(rows[0].data);
  if(loaded.clock!==seed.clock||loaded.assets.length!==seed.assets.length||loaded.paused!==updated.paused)throw new Error('Snapshot round-trip did not match the updated seed.');
  console.log('PASS: server-only Data API snapshot insert/upsert/read and Zod validation.');
 }finally{
  if(created){await call(`${endpoint}?id=eq.${encodeURIComponent(id)}`,{method:'DELETE'});console.log('Removed the isolated temporary verification record.');}
 }
 if(process.argv.includes('--initialize')){
  const response=await call(`${endpoint}?id=eq.dal-1&select=data`);
  const rows:unknown=await response.json();
  if(!Array.isArray(rows))throw new Error('Unexpected snapshot response.');
  if(rows.length){StateSchema.parse(rows[0].data);console.log('Existing dal-1 snapshot preserved.');}
  else{
   const seed=StateSchema.parse(createInitialState());
   await call(endpoint,{method:'POST',headers:{Prefer:'resolution=ignore-duplicates'},body:JSON.stringify({id:'dal-1',data:seed})});
   console.log('Initialized dal-1 only if absent; concurrent existing data is preserved.');
  }
 }
 if(process.argv.includes('--app-roundtrip')){
  if(process.env.DEMO_MODE!=='0')throw new Error('App round-trip requires DEMO_MODE=0.');
  const {initializeStore}=await import('../services/core/store');
  const {loadPersistedState}=await import('../services/core/persistence');
  const store=await initializeStore();
  try{
   const state=await store.command({type:'pause',paused:store.state.paused});
   const loaded=await loadPersistedState();
   if(!loaded||JSON.stringify(loaded)!==JSON.stringify(state))throw new Error('App persistence round-trip did not match the committed state.');
   console.log('PASS: actual app store hydration, audited command persistence, and reload.');
  }finally{store.dispose();}
 }
}
}
void main().catch(error=>{console.error(error instanceof Error?error.message:'Supabase verification failed');process.exitCode=1;});
