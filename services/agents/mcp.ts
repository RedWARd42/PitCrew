import {McpServer} from '@modelcontextprotocol/sdk/server/mcp.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {ToolInputSchema,toolNames} from '../../packages/contracts';
import {executeTool,mutationSchemas,type MutationName} from './tools';
import {getStore} from '../core/store';
const server=new McpServer({name:'groundtruth',version:'1.0.0'});
for(const name of toolNames)server.registerTool(name,{description:`Advisory plant tool: ${name}`,inputSchema:(name in mutationSchemas?mutationSchemas[name as MutationName]:ToolInputSchema).shape},async (input:unknown)=>{try{const store=getStore();const result=await executeTool(store.state,name,input,command=>store.command(command),(toolName,value)=>store.advisoryTool(toolName,value));return {content:[{type:'text' as const,text:JSON.stringify(result)}]};}catch(error){return {isError:true,content:[{type:'text' as const,text:error instanceof Error?error.message:'Tool failed'}]};}});
await server.connect(new StdioServerTransport());

