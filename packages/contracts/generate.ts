import {z} from 'zod';
import {writeFileSync} from 'node:fs';
import {CommandSchema,StateSchema,ToolInputSchema,toolNames,mutationSchemas,type MutationName} from './index';
writeFileSync('packages/contracts/openapi.json',JSON.stringify({openapi:'3.1.0',info:{title:'Groundtruth API',version:'1.0.0'},paths:{'/api/state':{get:{responses:{'200':{description:'Plant snapshot',content:{'application/json':{schema:z.toJSONSchema(StateSchema)}}}}}},'/api/command':{post:{requestBody:{required:true,content:{'application/json':{schema:z.toJSONSchema(CommandSchema)}}},responses:{'200':{description:'Updated snapshot'},'400':{description:'Validation error'},'409':{description:'Invalid state transition'}}}},'/api/events':{get:{responses:{'200':{description:'SSE snapshots'}}}}}},null,2));
writeFileSync('packages/contracts/tools.json',JSON.stringify(toolNames.map(name=>({name,inputSchema:z.toJSONSchema(name in mutationSchemas?mutationSchemas[name as MutationName]:ToolInputSchema)})),null,2));
