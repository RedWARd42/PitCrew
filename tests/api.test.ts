import {describe,it,expect,beforeEach} from 'vitest';
import {POST} from '../apps/field/app/api/command/route';
import {GET} from '../apps/field/app/api/state/route';
import {StateSchema} from '../packages/contracts';
import {getStore} from '../services/core/store';
const request=(body:unknown)=>new Request('http://localhost/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
beforeEach(async()=>{await getStore().command({type:'reset'});});
describe('API contract',()=>{
 it('returns a validated plant snapshot',async()=>{const response=await GET();expect(response.status).toBe(200);expect(StateSchema.safeParse(await response.json()).success).toBe(true);});
 it('rejects an invalid command before changing state',async()=>{const before=structuredClone(getStore().state);const response=await POST(request({type:'reading',assetId:'CH-3',value:'unsafe'}));expect(response.status).toBe(400);expect(getStore().state).toEqual(before);});
 it('delivers the drift-to-warning slice and requires concrete read-back',async()=>{const response=await POST(request({type:'scenario',id:'S1'}));const state=StateSchema.parse(await response.json());expect(state.warnings[0].assetId).toBe('CH-3');expect(state.messages).not.toHaveLength(0);const denied=await POST(request({type:'ack',warningId:state.warnings[0].id,readback:'own'}));expect(denied.status).toBe(400);const ack=await POST(request({type:'ack',warningId:state.warnings[0].id,readback:'I will inspect pump B by 02:30.'}));expect(StateSchema.parse(await ack.json()).warnings[0].state).toBe('owned');});
 it('rolls back unknown assets with a conflict response',async()=>{const response=await POST(request({type:'note',assetId:'unknown',text:'Check the pump'}));expect(response.status).toBe(409);expect(getStore().state.notes.some(n=>n.assetId==='unknown')).toBe(false);});
});
