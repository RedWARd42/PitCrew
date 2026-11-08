/** Accept the local request origin or the explicitly configured public app origin.
 * Proxy headers are deliberately not treated as an arbitrary origin allowlist.
 */
export function isAllowedRequestOrigin(origin:string|null,requestOrigin:string,appUrl=process.env.APP_URL){
 if(!origin)return true;
 if(origin===requestOrigin)return true;
 if(!appUrl)return false;
 try{
  const configured=new URL(appUrl);
  if(!['http:','https:'].includes(configured.protocol)||configured.username||configured.password)return false;
  return origin===configured.origin;
 }catch{return false;}
}
