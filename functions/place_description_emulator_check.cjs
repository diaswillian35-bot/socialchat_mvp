"use strict";
const assert=require("node:assert/strict");
const PROJECT="demo-remdy-place-translate";
if(!/^127\.0\.0\.1:/.test(process.env.FIRESTORE_EMULATOR_HOST||"") || process.env.GCLOUD_PROJECT!==PROJECT)
 throw Error("Refusing non-demo or non-loopback Firestore");
const admin=require("firebase-admin");admin.initializeApp({projectId:PROJECT});const db=admin.firestore();
const c=require("./place_description_cache");const {LIMITS,periods}=require("./place_description_translate");
function token(uid){const enc=d=>Buffer.from(JSON.stringify(d)).toString("base64url");return `${enc({alg:"none",typ:"JWT"})}.${enc({aud:PROJECT,iss:`https://securetoken.google.com/${PROJECT}`,sub:uid,user_id:uid,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,firebase:{sign_in_provider:"custom",identities:{}}})}.`;}
async function call(lang,text,uid="adult"){
 const res=await fetch(`http://127.0.0.1:5107/${PROJECT}/us-central1/translatePlaceDescription`,{method:"POST",headers:{"Content-Type":"application/json",...(uid?{Authorization:`Bearer ${token(uid)}`}:{})},body:JSON.stringify({data:{placeId:"EmulatorPlace",language:lang,sourceHash:c.hash(text)}})});
 return{status:res.status,body:await res.json()};
}
(async()=>{
 const original="Descrição 🍔 original";
 await db.doc("users/adult").set({ageVerificationStatus:"verified"});
 await db.doc("users/pending").set({ageVerificationStatus:"pending"});
 await db.doc("places/EmulatorPlace").set({schemaVersion:1,active:true,deleted:false,moderationStatus:"published",description:original});
 assert.equal((await call("en",original,null)).status,401);console.log("PASS unauthenticated denied");
 assert.equal((await call("en",original,"pending")).status,403);console.log("PASS adult guard denies pending");
 const responses=await Promise.all(Array.from({length:8},()=>call("en",original)));
 console.log("Concurrent results",JSON.stringify(responses));
 console.log("Metrics",(await db.doc("testMetrics/provider").get()).data());
 assert.ok(responses.every(r=>r.status===200));assert.ok(responses.some(r=>r.body.result.translated));
 assert.equal((await db.doc("testMetrics/provider").get()).data().calls,1);console.log("PASS concurrent callable: exactly one mocked provider request");
 assert.equal((await call("en",original)).body.result.text,"mock-en");
 assert.equal((await call("pt-PT",original)).body.result.reason,"same_language");
 assert.equal((await db.doc("testMetrics/provider").get()).data().calls,1);console.log("PASS cached view and same-language original avoid provider");
 assert.equal(await c.readCachedDescription(db,"EmulatorPlace",original,"en"),"mock-en");
 const edited="Descrição alterada";await db.doc("places/EmulatorPlace").update({description:edited});
 assert.equal((await call("en",original)).body.result.translated,false);
 assert.equal(await c.readCachedDescription(db,"EmulatorPlace",edited,"en"),null);
 assert.equal((await call("en",edited)).body.result.text,"mock-en");
 assert.equal((await db.doc("testMetrics/provider").get()).data().calls,2);console.log("PASS edit invalidates old hash and translates once for new hash");
 const {day}=periods(new Date());await db.doc(`placeDescriptionTranslationUsage/day_${day}`).set({characters:LIMITS.daily});
 assert.equal((await call("fr",edited)).body.result.reason,"reserved_or_quota");
 assert.equal((await db.doc("testMetrics/provider").get()).data().calls,2);console.log("PASS atomic quota prevents new provider request");
 const url=`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/${c.CACHE}/${c.cacheId("EmulatorPlace","en",c.hash(edited))}`;
 const denied=await fetch(url);assert.equal(denied.status,403);console.log("PASS public direct cache reads denied by existing rules");
 const deniedWrite=await fetch(url,{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({fields:{status:{stringValue:"ready"}}})});
 assert.equal(deniedWrite.status,403);console.log("PASS public direct cache writes denied by existing rules");
 console.log("PASS emulator E2E: all 9 checks; zero real API calls, demo data only");
 await db.terminate();
})().catch(e=>{console.error(e);process.exitCode=1;});
