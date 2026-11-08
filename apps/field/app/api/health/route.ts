export async function GET(){return Response.json({ok:true,service:'pitcrew',mode:process.env.DEMO_MODE==='0'?'live':'demo'});}
