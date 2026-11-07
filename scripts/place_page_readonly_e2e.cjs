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
 constructor(collection,filters=[],limit=500,order=[]){this.collection=collection;this.filters=filters;this.count=limit;this.order=order;}
 where(field,op,value){return new Query(this.collection,[...this.filters,{fieldFilter:{field:{fieldPath:field},op:op==='>='?'GREATER_THAN_OR_EQUAL':'EQUAL',value:value instanceof Date?{timestampValue:value.toISOString()}:typeof value==='boolean'?{booleanValue:value}:typeof value==='number'?{integerValue:String(value)}:{stringValue:value}}}],this.count,this.order);}
 limit(n){return new Query(this.collection,this.filters,n,this.order);}
 orderBy(field,direction='asc'){return new Query(this.collection,this.filters,this.count,[...this.order,{field:{fieldPath:typeof field==='string'?field:'__name__'},direction:direction==='desc'?'DESCENDING':'ASCENDING'}]);}
 startAfter(){throw new Error('Production fixture exceeded local E2E pagination bound');}
 async get(){const q={from:[{collectionId:this.collection}],where:{compositeFilter:{op:'AND',filters:this.filters}},limit:this.count};if(this.order.length)q.orderBy=this.order;const audit={kind:'query',query:q};reads.push(audit);const raw=await request(base+':runQuery',{method:'POST',body:JSON.stringify({structuredQuery:q})});const docs=raw.filter(r=>r.document).map(r=>doc(r.document));audit.returnedDocs=docs.length;return{docs,size:docs.length};}
 doc(id){return{get:async()=>{reads.push({kind:'GET',collection:this.collection,id});try{return doc(await request(base+'/'+this.collection+'/'+id));}catch(e){if(e.code===404)return{exists:false};throw e;}}};}
}
const db={collection(name){if(!['places','events','config'].includes(name))throw new Error('Read scope violation');return new Query(name);}};
function response(){return{headers:{},statusCode:0,body:'',set(k,v){this.headers[k]=v;return this;},status(n){this.statusCode=n;return this;},send(v){this.body=v;return this;}};}
(async()=>{
 const dir=path.resolve(__dirname,'../e2e');fs.mkdirSync(dir,{recursive:true});const id='hPGFEU4iQbDJXItOwQhV';const summary={};
 for(const lang of ['pt-BR','en']){const res=response();await createPlaceHandler(db)({method:'GET',path:'/l/'+id,query:{lang},get:()=>lang},res);if(res.statusCode!==200)throw new Error('Unexpected page status '+res.statusCode);fs.writeFileSync(path.join(dir,'john-v2-'+lang+'.html'),res.body);const title=res.body.match(/<title>(.*?)<\/title>/)[1];const image=res.body.match(/property="og:image" content="([^"]+)"/)[1].replace(/&amp;/g,'&');const imgRes=await fetch(image,{method:'HEAD'});const ld=JSON.parse(res.body.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);if(!Array.isArray(ld.image)||ld.image.length!==5||ld.image[0]!==image)throw new Error('Real JSON-LD gallery mismatch');summary[lang]={status:res.statusCode,title,headers:res.headers,imageStatus:imgRes.status,imageType:imgRes.headers.get('content-type'),jsonLdImages:ld.image.length,relatedKind:res.body.match(/id="related-places" data-kind="([^"]+)"/)?.[1],galleryPhotos:(res.body.match(/alt="John Burger — (?:foto|photo) \d+"/g)||[]).length,relatedCards:((res.body.split('id="related-places"')[1]||'').split('</section>')[0].match(/class="ev-card"/g)||[]).length};
 }
 const realDoc=await db.collection('places').doc(id).get();const photos=require('../functions/public_place_logic').photosOf(realDoc.data());summary.photos=[];
 for(let i=0;i<photos.length;i++){const r=await fetch(photos[i],{method:'HEAD'});summary.photos.push({photo:i+1,status:r.status,contentType:r.headers.get('content-type')});if(r.status!==200)throw new Error('Photo failed '+(i+1));}
 const res=response();await createSitemapHandler(db)({method:'GET'},res);fs.writeFileSync(path.join(dir,'sitemap-locais.xml'),res.body);summary.sitemap={status:res.statusCode,urls:(res.body.match(/<url>/g)||[]).length};
 const nf=renderPlacePage({id:'missing',data:null});fs.writeFileSync(path.join(dir,'404.html'),nf.html);summary.notFound=nf.status;
 fs.writeFileSync(path.join(dir,'readonly-v2-e2e.json'),JSON.stringify({summary,reads},null,2));console.log(JSON.stringify(summary,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
