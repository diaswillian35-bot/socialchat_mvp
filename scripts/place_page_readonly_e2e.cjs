// Local handler integration with REAL Firestore GET / read-only runQuery.
// Never writes Firestore, creates no users, and does not log the access token.
const fs=require('node:fs');const path=require('node:path');const cp=require('node:child_process');
const {createPlaceHandler,createSitemapHandler}=require('../functions/public_places');
const {renderPlacePage}=require('../functions/public_place_logic');
const base='https://firestore.googleapis.com/v1/projects/socialchatmvp/databases/(default)/documents';
const env={...process.env,CLOUDSDK_PYTHON:'/Volumes/REMDY_SSD/python/bin/python3',CLOUDSDK_CONFIG:'/Volumes/REMDY_SSD/gcloud_config'};
const token=cp.execFileSync('/Volumes/REMDY_SSD/google-cloud-sdk/bin/gcloud',['auth','print-access-token'],{env,encoding:'utf8'}).trim();
const reads=[];
function decode(v){if('mapValue'in v)return Object.fromEntries(Object.entries(v.mapValue.fields||{}).map(([k,x])=>[k,decode(x)]));if('arrayValue'in v)return(v.arrayValue.values||[]).map(decode);if('integerValue'in v)return Number(v.integerValue);return Object.values(v)[0];}
function doc(raw){return{id:raw.name.split('/').pop(),exists:true,data:()=>Object.fromEntries(Object.entries(raw.fields||{}).map(([k,v])=>[k,decode(v)]))};}
async function request(url,opts={}){const r=await fetch(url,{...opts,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'}});if(!r.ok){const s=await r.text();throw Object.assign(new Error(s),{code:r.status});}return r.json();}
class Query{
 constructor(filters=[],limit=500,order=false){this.filters=filters;this.count=limit;this.order=order;}
 where(field,op,value){return new Query([...this.filters,{fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:typeof value==='boolean'?{booleanValue:value}:typeof value==='number'?{integerValue:String(value)}:{stringValue:value}}}],this.count,this.order);}
 limit(n){return new Query(this.filters,n,this.order);}
 orderBy(){return new Query(this.filters,this.count,true);}
 startAfter(){throw new Error('Production fixture exceeded local E2E pagination bound');}
 async get(){const q={from:[{collectionId:'places'}],where:{compositeFilter:{op:'AND',filters:this.filters}},limit:this.count};if(this.order)q.orderBy=[{field:{fieldPath:'__name__'},direction:'ASCENDING'}];reads.push({kind:'query',query:q});const raw=await request(base+':runQuery',{method:'POST',body:JSON.stringify({structuredQuery:q})});const docs=raw.filter(r=>r.document).map(r=>doc(r.document));return{docs,size:docs.length};}
 doc(id){return{get:async()=>{reads.push({kind:'GET',id});try{return doc(await request(base+'/places/'+id));}catch(e){if(e.code===404)return{exists:false};throw e;}}};}
}
const db={collection(name){if(name!=='places')throw new Error('Read scope violation');return new Query();}};
function response(){return{headers:{},statusCode:0,body:'',set(k,v){this.headers[k]=v;return this;},status(n){this.statusCode=n;return this;},send(v){this.body=v;return this;}};}
(async()=>{
 const dir=path.resolve(__dirname,'../e2e');fs.mkdirSync(dir,{recursive:true});const id='hPGFEU4iQbDJXItOwQhV';const summary={};
 for(const lang of ['pt-BR','en']){const res=response();await createPlaceHandler(db)({method:'GET',path:'/l/'+id,query:{lang},get:()=>lang},res);if(res.statusCode!==200)throw new Error('Unexpected page status '+res.statusCode);fs.writeFileSync(path.join(dir,'john-'+lang+'.html'),res.body);const title=res.body.match(/<title>(.*?)<\/title>/)[1];const image=res.body.match(/property="og:image" content="([^"]+)"/)[1].replace(/&amp;/g,'&');const imgRes=await fetch(image,{method:'HEAD'});summary[lang]={status:res.statusCode,title,headers:res.headers,imageStatus:imgRes.status,imageType:imgRes.headers.get('content-type'),relatedCards:((res.body.split('id="related-places"')[1]||'').split('</section>')[0].match(/class="ev-card"/g)||[]).length};
 }
 const res=response();await createSitemapHandler(db)({method:'GET'},res);fs.writeFileSync(path.join(dir,'sitemap-locais.xml'),res.body);summary.sitemap={status:res.statusCode,urls:(res.body.match(/<url>/g)||[]).length};
 const nf=renderPlacePage({id:'missing',data:null});fs.writeFileSync(path.join(dir,'404.html'),nf.html);summary.notFound=nf.status;
 fs.writeFileSync(path.join(dir,'readonly-e2e.json'),JSON.stringify({summary,reads},null,2));console.log(JSON.stringify(summary,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
