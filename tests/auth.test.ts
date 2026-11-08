import {afterEach,describe,expect,it,vi} from 'vitest';
import {middleware} from '../apps/field/middleware';
type MiddlewareRequest=Parameters<typeof middleware>[0];
function request(path='/api/state',options:{token?:string;cookie?:string;method?:string;origin?:string}={}):MiddlewareRequest{
 const headers=new Headers();if(options.token)headers.set('authorization',`Bearer ${options.token}`);if(options.origin)headers.set('origin',options.origin);
 return {nextUrl:new URL(`https://plant.example${path}`),headers,cookies:{get:()=>options.cookie?{value:options.cookie}:undefined},method:options.method??'GET'} as unknown as MiddlewareRequest;
}
afterEach(()=>vi.unstubAllEnvs());
describe('operational access boundary',()=>{
 it('keeps local demo accessible without configured secrets',()=>{vi.stubEnv('DEMO_MODE','1');vi.stubEnv('DIRECTOR_TOKEN','');expect(middleware(request()).status).toBe(200);});
 it('fails closed in live mode if access is not configured',()=>{vi.stubEnv('DEMO_MODE','0');vi.stubEnv('DIRECTOR_TOKEN','');expect(middleware(request()).status).toBe(503);});
 it('requires authentication for operational reads and event streams',()=>{vi.stubEnv('DIRECTOR_TOKEN','correct-secret');expect(middleware(request()).status).toBe(401);expect(middleware(request('/api/events')).status).toBe(401);});
 it('accepts the operator cookie for SSE and a bearer for API clients',()=>{vi.stubEnv('DIRECTOR_TOKEN','correct-secret');expect(middleware(request('/api/events',{cookie:'correct-secret'})).status).toBe(200);expect(middleware(request('/api/state',{token:'correct-secret'})).status).toBe(200);});
 it('rejects cross-origin authenticated mutation',()=>{vi.stubEnv('DIRECTOR_TOKEN','correct-secret');expect(middleware(request('/api/command',{token:'correct-secret',method:'POST',origin:'https://attacker.example'})).status).toBe(403);});
 it('allows only the non-operational health endpoint without auth',()=>{vi.stubEnv('DIRECTOR_TOKEN','correct-secret');expect(middleware(request('/api/health')).status).toBe(200);});
});
