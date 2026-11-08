import { InvestigationSchema, FieldAnswer } from './investigation';
import { z } from 'zod';
export const Severity = z.enum(['info','watch','critical']);
export const AssetSchema = z.object({id:z.string(),name:z.string(),type:z.string(),zone:z.string(),criticality:z.number(),status:z.string(),routeOrder:z.number(),metric:z.string(),unit:z.string(),baseline:z.number(),value:z.number(),history:z.array(z.number()),feeds:z.array(z.string())});
export type Asset = z.infer<typeof AssetSchema>;
export const PersonSchema=z.object({id:z.string(),name:z.string(),role:z.string(),onCall:z.boolean()});
export const NoteSchema=z.object({id:z.string(),assetId:z.string(),author:z.string(),text:z.string(),ts:z.string(),structured:z.object({component:z.string(),symptom:z.string(),severity:Severity,followUp:z.boolean()})});
export const WarningSchema=z.object({id:z.string(),assetId:z.string(),title:z.string(),severity:Severity,ownerId:z.string(),dueAt:z.string(),state:z.enum(['open','owned','escalated','resolved']),escalationLevel:z.number(),readback:z.string(),evidence:z.array(z.string()),nextAction:z.string(),createdAt:z.string()});
export type Warning=z.infer<typeof WarningSchema>;
export const ActionSchema=z.object({type:z.enum(['inspect','open_breaker','bypass','stop']),target:z.string()});
export type Action=z.infer<typeof ActionSchema>;
export const StepSchema=z.object({number:z.number(),text:z.string(),action:ActionSchema,preconditions:z.array(z.string()),hazards:z.array(z.string()),verification:z.string()});
export const ProcedureSchema=z.object({id:z.string(),title:z.string(),assetTypes:z.array(z.string()),version:z.number(),approved:z.boolean(),steps:z.array(StepSchema)});
export type Procedure=z.infer<typeof ProcedureSchema>;
export const TraceSchema=z.object({id:z.string(),agent:z.string(),trigger:z.string(),mode:z.enum(['deterministic','cached','live','fallback']),model:z.string(),latencyMs:z.number(),plan:z.array(z.string()),steps:z.array(z.object({tool:z.string(),input:z.unknown(),result:z.unknown(),summary:z.string(),latencyMs:z.number()})),summary:z.string(),ts:z.string()});
export type Trace=z.infer<typeof TraceSchema>;
export const MessageSchema=z.object({id:z.string(),personId:z.string(),entityId:z.string(),channel:z.enum(['terminal','imessage','voice','group']),direction:z.enum(['inbound','outbound']),text:z.string(),status:z.enum(['queued','sending','sent','read','acked','failed','simulated']),ts:z.string(),provider:z.string().optional(),providerMessageId:z.string().optional(),callTokenHash:z.string().optional(),callExpiresAt:z.string().optional()});
export type Message=z.infer<typeof MessageSchema>;
export const IncidentSchema=z.object({id:z.string(),title:z.string(),hypothesis:z.string(),severity:Severity,ownerId:z.string(),assetIds:z.array(z.string()),alarmCount:z.number(),etaMinutes:z.number().nullable(),confidence:z.tuple([z.number(),z.number()]).nullable(),assumptions:z.array(z.string()),procedureId:z.string(),createdAt:z.string()});
export const HandoverItemSchema=z.object({id:z.string(),assetId:z.string(),severity:Severity,summary:z.string(),action:z.string(),contingency:z.string(),confirmed:z.boolean(),readback:z.string()});
export const EventType=z.enum(['reading.new','drift.detected','alarm.raised','incident.opened','warning.created','warning.acked','warning.escalated','procedure.step_checked','handover.drafted','handover.confirmed','message.inbound','message.outbound']);
export const EventSchema=z.object({id:z.string(),type:EventType,ts:z.string(),payload:z.record(z.string(),z.unknown())});
export const ScenarioSchema=z.object({id:z.enum(['S1','S2','S3','S4','S5']),title:z.string(),seed:z.number(),timeline:z.array(z.object({at:z.number(),fault:z.string(),assetId:z.string(),value:z.number().optional()})),expected:z.array(z.string())});
export const ToolInputSchema=z.object({assetId:z.string().optional(),sensorId:z.string().optional(),assetIds:z.array(z.string()).optional(),query:z.string().optional(),action:ActionSchema.optional(),limit:z.number().optional(),text:z.string().optional(),personId:z.string().optional(),warningId:z.string().optional()});
export const toolNames=['get_asset','get_live_state','get_trend','compare_siblings','check_sensor_sanity','get_topology','simulate_action','get_active_work','project_time_to_limit','correlate_alarms','search_procedures','get_notes','add_note','get_roster','create_warning','assign_owner','set_deadline','create_work_order','notify','start_escalation','open_incident_chat','place_call'] as const;
export const CommandSchema=z.discriminatedUnion('type',[
 z.object({type:z.literal('investigate'),assetId:z.string(),useModel:z.boolean().default(false)}),
 z.object({type:z.literal('field_answer'),investigationId:z.string(),revision:z.number().int().nonnegative(),answer:FieldAnswer}),
 z.object({type:z.literal('take_ownership'),warningId:z.string()}),
 z.object({type:z.literal('scenario'),id:ScenarioSchema.shape.id}),z.object({type:z.literal('reset')}),z.object({type:z.literal('step'),seconds:z.number().min(1).max(604800)}),z.object({type:z.literal('pause'),paused:z.boolean()}),z.object({type:z.literal('cache'),mode:z.enum(['only','prefer','live'])}),
 z.object({type:z.literal('reading'),assetId:z.string(),value:z.number().finite()}),z.object({type:z.literal('note'),assetId:z.string(),text:z.string().min(1).max(4000)}),
 z.object({type:z.literal('complete_inspection'),assetId:z.string()}),
 z.object({type:z.literal('ack'),warningId:z.string(),readback:z.string().min(8).max(1000)}),z.object({type:z.literal('read'),messageId:z.string()}),
 z.object({type:z.literal('check'),procedureId:z.string(),assetId:z.string(),step:z.number().int().positive()}),z.object({type:z.literal('advance'),runId:z.string(),overrideReason:z.string().max(2000).optional()}),
 z.object({type:z.literal('handover')}),z.object({type:z.literal('confirm'),itemId:z.string(),readback:z.string().min(8)}),z.object({type:z.literal('send_handover')})]);
export type Command=z.infer<typeof CommandSchema>;
export const StateSchema=z.object({investigations:z.array(InvestigationSchema).default([]),clock:z.string(),scenario:z.string().nullable(),paused:z.boolean(),cacheMode:z.enum(['only','prefer','live']),assets:z.array(AssetSchema),people:z.array(PersonSchema),notes:z.array(NoteSchema),warnings:z.array(WarningSchema),incidents:z.array(IncidentSchema),procedures:z.array(ProcedureSchema),messages:z.array(MessageSchema),traces:z.array(TraceSchema),handover:z.array(HandoverItemSchema),workOrders:z.array(z.object({id:z.string(),assetId:z.string(),title:z.string(),state:z.string()})),runs:z.array(z.object({id:z.string(),procedureId:z.string(),assetId:z.string(),step:z.number(),verdict:z.enum(['GO','HOLD']),reasoning:z.string(),overrideReason:z.string().optional(),completed:z.boolean()})),audit:z.array(z.object({id:z.string(),ts:z.string(),action:z.string(),detail:z.string()}))});
export type PlantState=z.infer<typeof StateSchema>;
export interface TelemetrySource {snapshot(assetIds?:string[]):Asset[];subscribe(listener:(asset:Asset)=>void):()=>void;}
export const apiContract={state:{method:'GET',path:'/api/state'},command:{method:'POST',path:'/api/command'},events:{method:'GET',path:'/api/events'},tools:{method:'POST',path:'/api/tools'},health:{method:'GET',path:'/api/health'}} as const;
export const SeedSiteSchema=z.object({id:z.string(),name:z.string(),zone:z.string(),clock:z.iso.datetime(),seed:z.number().int(),assets:z.array(z.string()),people:z.array(PersonSchema)});
export const mutationSchemas={
 create_warning:z.object({warning:WarningSchema}),
 assign_owner:z.object({warningId:z.string(),personId:z.string()}),
 set_deadline:z.object({warningId:z.string(),dueAt:z.iso.datetime()}),
 create_work_order:z.object({assetId:z.string(),title:z.string().min(4).max(500)}),
 notify:z.object({personId:z.string(),text:z.string().min(1).max(2000),warningId:z.string().optional()}),
 start_escalation:z.object({warningId:z.string()}),
 open_incident_chat:z.object({incidentId:z.string()}),
 place_call:z.object({personId:z.string(),text:z.string().min(1).max(2000),warningId:z.string()})
} as const;
export type MutationName=keyof typeof mutationSchemas;
export const MutationToolSchema=z.discriminatedUnion('name',[
 z.object({name:z.literal('create_warning'),input:mutationSchemas.create_warning}),z.object({name:z.literal('assign_owner'),input:mutationSchemas.assign_owner}),z.object({name:z.literal('set_deadline'),input:mutationSchemas.set_deadline}),z.object({name:z.literal('create_work_order'),input:mutationSchemas.create_work_order}),z.object({name:z.literal('notify'),input:mutationSchemas.notify}),z.object({name:z.literal('start_escalation'),input:mutationSchemas.start_escalation}),z.object({name:z.literal('open_incident_chat'),input:mutationSchemas.open_incident_chat}),z.object({name:z.literal('place_call'),input:mutationSchemas.place_call})]);
export const parseAdvisoryMutation=(name:string,input:unknown)=>MutationToolSchema.parse({name,input});
