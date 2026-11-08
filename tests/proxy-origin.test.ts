import {afterEach,describe,it,expect,vi} from 'vitest';
import {POST} from '../apps/field/app/api/auth/route';
import {isAllowedRequestOrigin} from '../apps/field/lib/request-origin';
import {middleware} from '../apps/field/middleware';
afterEach(()=>vi.unstubAllEnvs());
describe('configured ngrok origin',()=>{
 it('accepts the exact public APP_URL behind the localhost upstream',async()=>{
  vi.stubEnv('APP_URL','https://my-app.ngrok-free.dev');vi.stubEnv('DIRECTOR_TOKEN','local-test-token');
  const response=await POST(new Request('http://localhost:3000/api/auth',{method:'POST',headers:{Origin:'https://my-app.ngrok-free.dev','Content-Type':'application/json'},body:JSON.stringify({token:'local-test-token'})}));
  expect(response.status).toBe(200);expect(response.headers.get('set-cookie')).toContain('Secure');expect(response.headers.get('set-cookie')).toContain('HttpOnly');
 });
 it('still rejects unrelated and deceptive origin hosts',()=>{
  expect(isAllowedRequestOrigin('https://evil.example','http://localhost:3000','https://my-app.ngrok-free.dev')).toBe(false);
  expect(isAllowedRequestOrigin('https://my-app.ngrok-free.dev.evil.example','http://localhost:3000','https://my-app.ngrok-free.dev')).toBe(false);
  expect(isAllowedRequestOrigin('null','http://localhost:3000','https://my-app.ngrok-free.dev')).toBe(false);
 });
 it('does not accept a forged forwarded host as a configured origin',async()=>{
  vi.stubEnv('APP_URL','https://my-app.ngrok-free.dev');vi.stubEnv('DIRECTOR_TOKEN','local-test-token');
  const response=await POST(new Request('http://localhost:3000/api/auth',{method:'POST',headers:{Origin:'https://evil.example','x-forwarded-host':'evil.example'},body:JSON.stringify({token:'local-test-token'})}));expect(response.status).toBe(403);
 });
 it('validates the token after allowing the public origin',async()=>{
  vi.stubEnv('APP_URL','https://my-app.ngrok-free.dev');vi.stubEnv('DIRECTOR_TOKEN','local-test-token');
  const response=await POST(new Request('http://localhost:3000/api/auth',{method:'POST',headers:{Origin:'https://my-app.ngrok-free.dev'},body:JSON.stringify({token:'incorrect'})}));expect(response.status).toBe(401);
 });
 it('also accepts same-app mutations through the configured proxy origin',()=>{
  vi.stubEnv('APP_URL','https://my-app.ngrok-free.dev');vi.stubEnv('DIRECTOR_TOKEN','local-test-token');
  const request={nextUrl:new URL('http://localhost:3000/api/command'),headers:new Headers({Origin:'https://my-app.ngrok-free.dev',Authorization:'Bearer local-test-token'}),cookies:{get:()=>undefined},method:'POST'} as unknown as Parameters<typeof middleware>[0];expect(middleware(request).status).toBe(200);
 });
 it('preserves local same-origin development when APP_URL is absent',()=>{expect(isAllowedRequestOrigin('http://localhost:3000','http://localhost:3000','')).toBe(true);});
});
