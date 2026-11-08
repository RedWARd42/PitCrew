import {z} from 'zod';
import {ToolInputSchema,toolNames,mutationSchemas,parseAdvisoryMutation,type MutationName,type PlantState,type Command} from '../../packages/contracts';
export {mutationSchemas,MutationToolSchema,parseAdvisoryMutation} from '../../packages/contracts';
export type {MutationName} from '../../packages/contracts';
import {detectDrift,checkSensorSanity,simulateAction,projectTimeToLimit,rankRounds} from '../core/engines';
import {answerPlantQuestion} from './index';
export const toolDefinitions=toolNames.map(name=>({name,description:`Groundtruth advisory tool: ${name.replaceAll('_',' ')}`,inputSchema:z.toJSONSchema(name in mutationSchemas?mutationSchemas[name as MutationName]:ToolInputSchema)}));
export type ToolName=typeof toolNames[number];
export async function executeTool(state:PlantState,name:string,raw:unknown,dispatch?:(command:Command)=>Promise<PlantState>,advisoryGateway?:(name:string,input:unknown)=>Promise<unknown>):Promise<unknown>{
 if(!toolNames.includes(name as ToolName))throw new Error(`Unknown tool ${name}`);
 if(name in mutationSchemas){const validated=parseAdvisoryMutation(name,raw);if(!advisoryGateway)throw new Error('Audited advisory mutation gateway unavailable');return advisoryGateway(validated.name,validated.input);}
 const input=ToolInputSchema.parse(raw),asset=state.assets.find(a=>a.id===(input.assetId??input.sensorId));
 const requireAsset=()=>{if(!asset)throw new Error('A valid assetId is required');return asset;};
 switch(name){
 case 'get_asset':return {asset:requireAsset(),warnings:state.warnings.filter(w=>w.assetId===asset!.id),notes:state.notes.filter(n=>n.assetId===asset!.id)};
 case 'get_live_state':return state.assets.filter(a=>!input.assetIds||input.assetIds.includes(a.id));
 case 'get_trend':{const a=requireAsset();return {series:a.history,baseline:a.baseline,unit:a.unit,...detectDrift(a.history,a.baseline)};}
 case 'compare_siblings':{const a=requireAsset();return state.assets.filter(x=>x.type===a.type&&x.id!==a.id).map(x=>({id:x.id,value:x.value,unit:x.unit}));}
 case 'check_sensor_sanity':{const a=requireAsset();return checkSensorSanity(a.value,state.assets.filter(x=>x.type===a.type&&x.id!==a.id).map(x=>x.value).concat(a.baseline));}
 case 'get_topology':return state.assets.map(a=>({id:a.id,feeds:a.feeds,status:a.status}));
 case 'simulate_action':if(!input.action)throw new Error('action is required');return simulateAction(state.assets,input.action);
 case 'get_active_work':return {workOrders:state.workOrders.filter(w=>!input.assetIds||input.assetIds.includes(w.assetId)),procedureRuns:state.runs.filter(r=>!r.completed&&(!input.assetIds||input.assetIds.includes(r.assetId)))};
 case 'project_time_to_limit':{const a=requireAsset();if(input.limit===undefined)throw new Error('limit is required');return projectTimeToLimit(a.history,input.limit);}
 case 'correlate_alarms':return {incidents:state.incidents,alarms:state.incidents.reduce((n,i)=>n+i.alarmCount,0),warning:'Returns already correlated incident evidence; raw alarm stream is owned by the simulator.'};
 case 'search_procedures':return state.procedures.filter(p=>!input.query||`${p.title} ${p.assetTypes.join(' ')}`.toLowerCase().includes(input.query.toLowerCase()));
 case 'get_notes':return state.notes.filter(n=>!input.assetId||n.assetId===input.assetId);
 case 'get_roster':return {clock:state.clock,people:state.people,rounds:rankRounds(state.assets,state.warnings,state.notes)};
 case 'add_note':if(!dispatch)throw new Error('Mutation gateway unavailable');if(!input.text)throw new Error('text is required');return dispatch({type:'note',assetId:requireAsset().id,text:input.text});
 default:return answerPlantQuestion(state,input.query??'');
 }
}
