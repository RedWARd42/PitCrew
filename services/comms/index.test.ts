import {describe,it,expect} from 'vitest';
import type {PlantState,Warning} from '../../packages/contracts';
import {processEscalations,acknowledge,flushOutbound} from './index';
const warning:Warning={id:'w1',assetId:'CH-3',title:'Drift',severity:'watch',ownerId:'maria',dueAt:'2026-11-08T08:00:00Z',state:'open',escalationLevel:0,readback:'',evidence:[],nextAction:'Check bearing',createdAt:'2026-11-08T06:00:00Z'};
function fixture(){return {clock:'2026-11-08T06:00:00Z',warnings:[structuredClone(warning)],messages:[],audit:[]} as unknown as PlantState;}
describe('compressed escalation ladder',()=>{
 it('nudges a read message at 20s and escalates once at 45s',()=>{const s=fixture();processEscalations(s);s.messages[0].status='read';s.clock='2026-11-08T06:00:20Z';processEscalations(s);expect(s.warnings[0].escalationLevel).toBe(1);s.clock='2026-11-08T06:00:45Z';processEscalations(s);expect(s.warnings[0].ownerId).toBe('dev');expect(s.messages.filter(m=>m.channel==='voice')).toHaveLength(1);processEscalations(s);expect(s.messages.filter(m=>m.channel==='voice')).toHaveLength(1);});
 it('stops escalation after read-back',()=>{const s=fixture();processEscalations(s);acknowledge(s,s.warnings[0],"I will inspect pump B by 02:30");s.clock='2026-11-08T07:00:00Z';processEscalations(s);expect(s.messages.filter(m=>m.channel==='voice')).toHaveLength(0);expect(s.warnings[0].state).toBe('owned');});
 it('marks transport failures without claiming delivery',async()=>{const s=fixture();processEscalations(s);s.messages[0].status='queued';await flushOutbound(s,{send:async()=>{throw new Error('offline');}});expect(s.messages[0].status).toBe('failed');});
});
