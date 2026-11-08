import { createHash } from 'node:crypto';
import { z } from 'zod';
import { ProcedureSchema, WarningSchema, IncidentSchema, HandoverItemSchema, NoteSchema, type PlantState, type Trace } from '../../packages/contracts';
import { detectDrift, checkSensorSanity, simulateAction, projectTimeToLimit, correlateAlarms } from '../core/engines';
import {scenarioAlarms} from '../sim';
import {structuredAgent,runToolWorkflow} from './provider';

export function trace(state:PlantState,agent:string,trigger:string,steps:Trace['steps'],summary:string):Trace {
 const digest=createHash('sha256').update(JSON.stringify({agent,trigger,clock:state.clock,steps})).digest('hex').slice(0,12);
 return {id:`trace-${digest}`,agent,trigger,mode:'deterministic',model:'deterministic advisory workflow',latencyMs:0,plan:steps.map(s=>s.summary),steps,summary,ts:state.clock};
}
/** Enrich a workflow explanation without letting a model change a verdict or plant state. */
export async function augmentTrace(state:PlantState,input:Trace):Promise<Trace>{
 if(state.cacheMode==='only'||input.mode!=='deterministic')return input;
 if(/Investigator|Coordinator/.test(input.agent))return runToolWorkflow(state,input);
 const narration=await structuredAgent({agent:input.agent,input:{trigger:input.trigger,evidence:input.steps,deterministicDecision:input.summary},schema:z.object({summary:z.string().min(1).max(2000)}),fallback:()=>({summary:input.summary}),cacheMode:state.cacheMode,reasoning:/Guardian|Coordinator/.test(input.agent)});
 return {...input,summary:narration.output.summary,mode:narration.mode==='fallback'?'fallback':narration.mode,model:narration.model,latencyMs:narration.latencyMs};
}
const step=(tool:string,input:unknown,result:unknown,summary:string):Trace['steps'][number]=>({tool,input,result,summary,latencyMs:0});
function assetFor(state:PlantState,id:string){const asset=state.assets.find(a=>a.id===id);if(!asset)throw new Error(`Unknown asset: ${id}`);return asset;}

export async function investigate(state:PlantState,assetId:string){
 const asset=assetFor(state,assetId),drift=detectDrift(asset.history,asset.baseline);
 const peers=state.assets.filter(a=>a.type===asset.type&&a.id!==assetId);
 const sanity=peers.length?checkSensorSanity(asset.value,peers.map(a=>a.value)):{confidence:.7,agreesWithNeighbors:false,energyBalanceOk:true,reason:'No independent sibling sensor available; trend is provisional and requires local verification'};
 const notes=state.notes.filter(n=>n.assetId===assetId);
 const steps=[step('get_trend',{assetId},drift,'Compare the latest reading with its own baseline'),step('check_sensor_sanity',{assetId},sanity,'Check neighbors before trusting a sensor'),step('compare_siblings',{assetId},peers.map(a=>({id:a.id,value:a.value})),'Check whether the change is unit-specific'),step('get_notes',{assetId},notes.map(n=>n.text),'Bring forward observations from previous shifts'),step('get_active_work',{assetId},state.workOrders.filter(w=>w.assetId===assetId),'Check ongoing maintenance')];
 if(sanity.confidence<0.5){
 const workOrder={id:`wo-calibrate-${assetId}`,assetId,title:`Calibrate ${asset.name} ${asset.metric} sensor`,state:'open'};
 steps.push(step('create_work_order',{assetId},workOrder,'Create calibration work rather than an equipment warning'));
 return {workOrder,trace:trace(state,'Investigator',`drift:${assetId}`,steps,`${sanity.reason}. Equipment warning suppressed; verify and calibrate the sensor.`)};
 }
 const battery=/BAT|battery/i.test(asset.id+asset.type),owner=state.people.find(p=>/mechanical/i.test(p.role))??state.people.find(p=>!p.onCall)??state.people[0];
 if(!owner)throw new Error('No roster available');
 const projection=projectTimeToLimit(asset.history,asset.baseline+(battery?asset.baseline*.25:4));
 const dueAt=new Date(Date.parse(state.clock)+(battery?7*86400000:2*3600000)).toISOString();
 const evidence=[`${asset.metric} ${asset.value.toFixed(2)} ${asset.unit}; ${(asset.value-asset.baseline).toFixed(2)} ${asset.unit} vs baseline ${asset.baseline.toFixed(2)}`,...(peers.length?[`Sibling comparison: ${peers.map(a=>`${a.id} ${a.value.toFixed(2)} ${a.unit}`).join('; ')}`]:['Checked against this asset’s historical baseline']),...notes.map(n=>`Pinned note: ${n.text}`),`Sensor confidence ${(sanity.confidence*100).toFixed(0)}%: ${sanity.reason}`];
 const warning=WarningSchema.parse({id:`warning-${assetId}`,assetId,title:battery?'Battery string impedance is creeping upward':`${asset.name}: ${asset.metric.toLowerCase()} drift`,severity:state.scenario==='S3'?'critical':'watch',ownerId:owner.id,dueAt,state:'open',escalationLevel:0,readback:'',evidence,nextAction:battery?'Inspect string 3 connections and repeat impedance test within seven days':asset.type==='chiller'?'Inspect pump B bearing and verify flow before end of shift':'Verify the rising supply temperature locally and follow the chiller restart emergency procedure',createdAt:state.clock});
 steps.push(step('project_time_to_limit',{assetId},projection,'Estimate urgency with stated assumptions'),step('search_procedures',{assetType:asset.type},state.procedures.filter(p=>p.assetTypes.includes(asset.type)).map(p=>p.title),'Find the approved inspection procedure'),step('get_roster',{},owner,'Select the on-shift mechanical technician'),step('create_warning',{assetId},warning,'Create one warning with evidence and a deadline'),step('start_escalation',{warningId:warning.id},{ownerId:owner.id,ladder:['owner','chief','voice']},'Start the read-back escalation ladder'));
 return {warning,trace:trace(state,'Investigator',`drift:${assetId}`,steps,`${warning.title}. ${warning.nextAction}. Assigned to ${owner.name}.`)};
}

export function guardProcedure(state:PlantState,procedureId:string,assetId:string,stepNumber:number){
 assetFor(state,assetId);
 const procedure=state.procedures.find(p=>p.id===procedureId);if(!procedure)throw new Error('Unknown procedure');
 const selected=procedure.steps.find(s=>s.number===stepNumber);if(!selected)throw new Error('Unknown procedure step');
 const impact=simulateAction(state.assets,selected.action);
 const unmet=selected.preconditions.filter(p=>p==='retain_last_source'?impact.verdict!=='GO':!evaluatePredicate(p,state));
 const verdict=(!procedure.approved||impact.verdict==='HOLD'||unmet.length)?'HOLD' as const:'GO' as const;
 const reasoning=!procedure.approved?'Procedure revision has not been approved. Review the latest version.':impact.verdict==='HOLD'?impact.reason:unmet.length?`Preconditions not established: ${unmet.join('; ')}`:impact.reason;
 const steps=[step('get_live_state',{assetIds:state.assets.map(a=>a.id)},state.assets.map(a=>({id:a.id,status:a.status})),'Read current plant state'),step('get_active_work',{assetId},state.workOrders,'Check active maintenance'),step('simulate_action',selected.action,impact,'Compute source loss without operating equipment'),step('evaluate_preconditions',{predicates:selected.preconditions},{unmet},'Check every machine predicate')];
 return {verdict,reasoning,trace:trace(state,'Procedure Guardian',`${procedureId}:${stepNumber}`,steps,`${verdict}: ${reasoning}`)};
}
/** Unknown predicates fail closed. Seed predicates use these explicit forms. */
export function evaluatePredicate(predicate:string,state:PlantState):boolean{
 if(predicate==='true'||predicate==='advisory_only')return true;
 if(predicate==='temperature_below_62'){const supply=state.assets.find(a=>a.id==='CDU-1');return !!supply&&supply.value<62;}
 const online=/^online\(([^)]+)\)$/.exec(predicate);if(online)return ['online','running','normal'].includes(state.assets.find(a=>a.id===online[1])?.status??'');
 const notBypass=/^state\(([^)]+)\)\s*!=\s*["']?bypass["']?$/.exec(predicate);if(notBypass){const a=state.assets.find(a=>a.id===notBypass[1]);return !!a&&a.status!=='bypass';}
 const alt=/^alt_feed_ok\(([^)]+)\)$/.exec(predicate);if(alt){const a=state.assets.find(a=>a.id===alt[1]);return !!a&&a.feeds.some(id=>['running','online','normal'].includes(state.assets.find(x=>x.id===id)?.status??''));}
 return false;
}

export async function coordinator(state:PlantState){
 const correlation=correlateAlarms(scenarioAlarms(state));
 const cluster=correlation.clusters[0];if(!cluster)throw new Error('No correlated alarm cluster');
 const supply=state.assets.find(a=>/CHW|supply/i.test(a.metric))??state.assets.find(a=>a.id==='CH-3');
 const projection=projectTimeToLimit(supply?.history??[54,54.5,55],62);
 const chief=state.people.find(p=>p.onCall)??state.people[0];if(!chief)throw new Error('No incident owner');
 const incident=IncidentSchema.parse({id:'INC-0042',title:'Hall 2 cooling interruption',hypothesis:cluster.rootCause,severity:'critical',ownerId:chief.id,assetIds:cluster.assetIds,alarmCount:cluster.alarmCount,etaMinutes:projection.etaMinutes,confidence:projection.confidence,assumptions:projection.assumptions,procedureId:state.procedures.find(p=>/restart/i.test(p.title))?.id??'chiller-restart',createdAt:state.clock});
 const steps=[step('correlate_alarms',{windowSeconds:90},correlation,'Collapse downstream symptoms into one incident'),step('get_live_state',{assetIds:incident.assetIds},state.assets.filter(a=>incident.assetIds.includes(a.id)),'Verify the cooling train state'),step('project_time_to_limit',{limit:62},projection,'Project the restart limit from recent supply readings'),step('search_procedures',{query:'chiller restart'},incident.procedureId,'Surface the matching emergency procedure'),step('get_roster',{},chief,'Assign the on-call chief'),step('open_incident_chat',{roles:['chief','vendor','tenant']},{simulated:true},'Request a role-based incident conversation')];
 return {incident,trace:trace(state,'Incident Coordinator','alarm-flood',steps,`${incident.hypothesis} ${projection.etaMinutes===null?'No reliable ETA available.':`Approximately ${projection.etaMinutes.toFixed(0)} minutes to 62°F.`}`)};
}

export function structureNote(state:PlantState,assetId:string,text:string){
 assetFor(state,assetId);const component=/pump\s*[a-z]/i.exec(text)?.[0]??'equipment';
 const structured=NoteSchema.shape.structured.parse({component,symptom:text,severity:/smoke|fire|leak/i.test(text)?'critical':/rattle|vibrat|noise/i.test(text)?'watch':'info',followUp:/rattle|vibrat|noise|leak|check|inspect/i.test(text)});
 return {structured,trace:trace(state,'Field Scribe',`note:${assetId}`,[step('structure_note',{assetId,text},structured,'Extract component, symptom, severity and follow-up')],`Pinned observation for ${assetId}: ${text}`)};
}

export function draftHandover(state:PlantState){
 const items:z.infer<typeof HandoverItemSchema>[]=[];
 for(const w of state.warnings.filter(w=>w.state!=='resolved'))items.push({id:`handover-${w.id}`,assetId:w.assetId,severity:w.severity,summary:w.title,action:`${w.nextAction}. Owner: ${state.people.find(p=>p.id===w.ownerId)?.name??w.ownerId}; due ${w.dueAt}`,contingency:'Escalate to the chief if conditions worsen or the deadline is at risk.',confirmed:false,readback:''});
 for(const i of state.incidents)items.push({id:`handover-${i.id}`,assetId:i.assetIds[0]??'CH-1',severity:i.severity,summary:i.title,action:`Follow ${i.procedureId}; contact ${state.people.find(p=>p.id===i.ownerId)?.name??i.ownerId}.`,contingency:i.hypothesis,confirmed:false,readback:''});
 for(const n of state.notes.filter(n=>n.structured.followUp&&!items.some(i=>i.assetId===n.assetId)))items.push({id:`handover-${n.id}`,assetId:n.assetId,severity:n.structured.severity,summary:n.text,action:`Inspect ${n.structured.component} and record findings.`,contingency:'Contact the on-call chief if the condition deteriorates.',confirmed:false,readback:''});
 for(const r of state.runs.filter(r=>r.overrideReason))items.push({id:`handover-${r.id}`,assetId:r.assetId,severity:'critical',summary:`Procedure override: ${r.overrideReason}`,action:'Review the override and verify the plant state with the outgoing technician.',contingency:r.reasoning,confirmed:false,readback:''});
 for(const r of state.runs.filter(r=>!r.completed&&!r.overrideReason))items.push({id:`handover-run-${r.id}`,assetId:r.assetId,severity:r.verdict==='HOLD'?'critical':'watch',summary:`Unfinished procedure: ${state.procedures.find(p=>p.id===r.procedureId)?.title??r.procedureId}; step ${r.step}`,action:'Receive a read-back from the outgoing technician before resuming at the checked step.',contingency:r.reasoning,confirmed:false,readback:''});
 for(const w of state.workOrders.filter(w=>w.state!=='resolved'&&w.state!=='closed'))items.push({id:`handover-work-${w.id}`,assetId:w.assetId,severity:'watch',summary:`Open work order: ${w.title}`,action:'Assign follow-up during the incoming shift and record inspection findings.',contingency:'Escalate if the verification cannot be completed within the shift.',confirmed:false,readback:''});
 for(const a of state.assets.filter(a=>a.status==='bypass'||a.status==='isolated'))items.push({id:`handover-maintenance-${a.id}`,assetId:a.id,severity:'critical',summary:`Maintenance context: ${a.name} is ${a.status}`,action:'Verify the maintenance permit and alternate source before any procedure.',contingency:'Stop work if another source becomes unavailable; contact the chief.',confirmed:false,readback:''});
 for(const investigation of state.investigations.filter((item,index,all)=>!all.slice(index+1).some(later=>later.assetId===item.assetId))) {
   const evidence=investigation.answers.map(a=>`${a.checkId}: ${a.value!==undefined?`${a.value} ${investigation.telemetry.unit}`:a.condition}${a.detail?` (${a.detail})`:''}`).join('; ');
   items.push({id:`handover-${investigation.id}`,assetId:investigation.assetId,severity:'watch',summary:`Investigation: ${investigation.summary} Field evidence: ${evidence||'not yet collected'}.`,action:investigation.nextCheck?`Continue field check: ${investigation.nextCheck.replaceAll('_',' ')}.`:investigation.nextAction,contingency:'Cause remains provisional. Recheck current telemetry and escalate deteriorating conditions.',confirmed:false,readback:''});
 }
 items.sort((a,b)=>(state.assets.find(x=>x.id===a.assetId)?.routeOrder??99)-(state.assets.find(x=>x.id===b.assetId)?.routeOrder??99));
 return {items:items.map(i=>HandoverItemSchema.parse(i)),trace:trace(state,'Handover Writer','shift-end',[step('gather_open_items',{},items,'Gather warnings, incidents, notes, overrides, active maintenance and unfinished work'),step('order_walking_route',{},items.map(i=>i.assetId),'Order I-PASS items along the incoming walking route')],`${items.length} I-PASS items require receiver read-back.`)};
}

export function compileProcedure(input:unknown){return ProcedureSchema.parse(input);}
export function answerPlantQuestion(state:PlantState,query:string){const matches=state.assets.filter(a=>query.toLowerCase().includes(a.id.toLowerCase())||query.toLowerCase().includes(a.name.toLowerCase()));const assets=matches.length?matches:state.assets.filter(a=>a.status!=='online'&&a.status!=='running');return {answer:assets.map(a=>`${a.name}: ${a.status}; ${a.value} ${a.unit}. Open warnings: ${state.warnings.filter(w=>w.assetId===a.id&&w.state!=='resolved').map(w=>`${w.title} (${state.people.find(p=>p.id===w.ownerId)?.name??w.ownerId})`).join('; ')||'none'}.`).join('\n')||'No matching assets. Ask using an asset ID.',citations:assets.map(a=>({assetId:a.id,asOf:state.clock}))};}
