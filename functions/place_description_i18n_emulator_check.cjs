"use strict";
// Build 44 E2E (emulador demo): tradução única na aprovação. Zero chamadas reais.
const assert=require("node:assert/strict");
const PROJECT="demo-remdy-place-translate";
if(!/^127\.0\.0\.1:/.test(process.env.FIRESTORE_EMULATOR_HOST||"") || process.env.GCLOUD_PROJECT!==PROJECT)
 throw Error("Refusing non-demo or non-loopback Firestore");
const admin=require("firebase-admin");admin.initializeApp({projectId:PROJECT});const db=admin.firestore();
const c=require("./place_description_cache");const {LIMITS,periods}=require("./place_description_translate");
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function waitFor(fn,label,ms=20000){const end=Date.now()+ms;while(Date.now()<end){const v=await fn();if(v)return v;await sleep(250);}throw Error("timeout "+label);}
const metrics=async()=>(await db.doc("testMetrics/approval").get()).data()||{};
(async()=>{
 const {day}=periods(new Date());const dayRef=db.doc(`placeDescriptionTranslationUsage/day_${day}`);
 // Cap compartilhado com o callable: cheio => aprova, não traduz, marca "quota".
 await dayRef.set({characters:LIMITS.daily});
 const q=db.doc("places/ApprovalQuota");
 await q.set({schemaVersion:1,active:true,deleted:false,moderationStatus:"published",description:"Texto que não cabe hoje"});
 const qi=await waitFor(async()=>(await q.get()).data().descriptionI18n,"quota status");
 assert.equal(qi.status,"quota");assert.equal((await q.get()).data().moderationStatus,"published");
 assert.equal((await metrics()).translate||0,0);console.log("PASS shared daily cap: no provider call, approval kept, status quota");
 await dayRef.set({characters:0});
 const ref=db.doc("places/ApprovalPlace");
 const text="Café com pão de queijo feito na hora";
 await ref.set({schemaVersion:1,active:false,deleted:false,moderationStatus:"pending",status:"pending",description:text,coverUrl:"x"});
 await sleep(1500);
 assert.equal((await ref.get()).data().descriptionI18n,undefined);
 assert.equal((await metrics()).translate||0,0);console.log("PASS pending place is never translated");
 await ref.update({moderationStatus:"published",status:"approved",active:true});
 const i18n=await waitFor(async()=>(await ref.get()).data().descriptionI18n,"approval translation");
 assert.equal(i18n.status,"ready");assert.equal(i18n.sourceLanguage,"pt");assert.equal(i18n.sourceHash,c.hash(text));
 assert.deepEqual(Object.keys(i18n.texts).sort(),["en","es","fr"]);
 assert.equal((await ref.get()).data().description,text);
 let m=await metrics();assert.equal(m.translate,3);assert.equal(m.detect,1);
 console.log("PASS approval translates once into en/es/fr, original untouched");
 assert.equal(await c.readCachedDescription(db,"ApprovalPlace",text,"en"),"mock-approval-en");
 console.log("PASS /l/ cache mirror readable without page changes");
 await ref.update({phone:"123"});await sleep(2500);
 m=await metrics();assert.equal(m.translate,3);console.log("PASS unrelated edit does not re-translate");
 // Dono edita: volta para pending; aprovação traduz de novo só o novo texto.
 const edited="Café, pão de queijo e bolo caseiro";
 await ref.update({description:edited,moderationStatus:"pending",status:"pending",active:false});await sleep(1500);
 assert.equal((await metrics()).translate,3);
 await ref.update({moderationStatus:"published",status:"approved",active:true});
 await waitFor(async()=>(await ref.get()).data().descriptionI18n?.sourceHash===c.hash(edited),"re-translation");
 m=await metrics();assert.equal(m.translate,6);assert.equal(m.detect,2);
 console.log("PASS changed description re-translated once after re-approval");
 const base=`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${PROJECT}/databases/(default)/documents/places/ApprovalPlace`;
 const pub=await fetch(base);assert.equal(pub.status,200);
 assert.ok(JSON.stringify(await pub.json()).includes("mock-approval-en"));console.log("PASS published place (with translations) readable by public rules");
 const w=await fetch(`${base}?updateMask.fieldPaths=descriptionI18n`,{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({fields:{descriptionI18n:{mapValue:{fields:{status:{stringValue:"ready"}}}}}})});
 assert.equal(w.status,403);console.log("PASS client cannot write descriptionI18n (existing rules)");
 console.log("PASS approval E2E: 8 checks; zero real API calls, demo data only");
 await db.terminate();
})().catch(e=>{console.error(e);process.exitCode=1;});
