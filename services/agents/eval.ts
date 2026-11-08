import {strict as assert} from 'node:assert';
import {createInitialState,applyScenario} from '../sim';
import {investigate,guardProcedure,coordinator,draftHandover,structureNote,augmentTrace} from './index';
let failed=0;
for(const id of ['S1','S2','S3','S4','S5']){
 try{
 const state=createInitialState();state.cacheMode=process.env.EVAL_LIVE==='1'?'live':'only';applyScenario(state,id);
 if(id==='S1'){const {warning,trace}=await investigate(state,'CH-3');assert(warning);assert.equal(warning.ownerId,'maria');assert.match(warning.evidence.join(' '),/rattle/i);assert.match(warning.evidence.join(' '),/Sibling/);assert(Date.parse(warning.dueAt)-Date.parse(state.clock)<8*3600000);assert(trace.steps.length>=7);state.warnings.push(warning);assert(draftHandover(state).items.length>0);assert(structureNote(state,'CH-3','pump B rattles').structured.followUp);if(process.env.EVAL_LIVE==='1'){const enriched=await augmentTrace(state,trace);assert.equal(enriched.mode,'live','Live evaluation requires successful inference, not a fallback');}}
 if(id==='S2'){const hold=guardProcedure(state,'MOP-UPS','UPS-2',6);assert.equal(hold.verdict,'HOLD');assert.match(hold.reasoning,/Row D loses its last source/);state.assets.find(a=>a.id==='UPS-2')!.status='online';assert.equal(guardProcedure(state,'MOP-UPS','UPS-2',6).verdict,'GO');for(let i=0;i<20;i++)assert.equal(guardProcedure(state,'MOP-UPS','UPS-2',i%5+1).verdict,'GO');}
 if(id==='S3'){const {incident}=await coordinator(state);assert(incident.alarmCount>=40);assert.match(incident.hypothesis,/Voltage dip/);assert(incident.etaMinutes!==null&&Math.abs(incident.etaMinutes-14)/14<=.2);}
 if(id==='S4'){const {warning}=await investigate(state,'BAT-3');assert(warning);assert(Date.parse(warning.dueAt)-Date.parse(state.clock)>=7*86400000);}
 if(id==='S5'){const r=await investigate(state,'CRAH-1');assert(!r.warning);assert(r.workOrder);assert.match(r.workOrder.title,/Calibrate/);}
 console.log(`PASS ${id}`);
 }catch(error){failed++;console.error(`FAIL ${id}: ${error instanceof Error?error.message:error}`);}
}
if(failed)process.exitCode=1;
