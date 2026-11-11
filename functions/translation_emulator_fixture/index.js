"use strict";
// This fixture must NEVER be deployed. All writes and provider responses are demo-local.
if(process.env.FUNCTIONS_EMULATOR!=="true" || !/^127\.0\.0\.1:/.test(process.env.FIRESTORE_EMULATOR_HOST||""))
 throw new Error("emulator_only_fixture");
const admin=require("firebase-admin");const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {verifiedAdultOnCall}=require("../social_age_guard");
const {translatePlaceDescriptionHandler}=require("../place_description_translate");
admin.initializeApp({projectId:"demo-remdy-place-translate"});
const db=admin.firestore();
const {FieldValue}=require("firebase-admin/firestore");
exports.translatePlaceDescription=verifiedAdultOnCall(onCall,{region:"us-central1"},req=>
 translatePlaceDescriptionHandler(req,{db,enabled:true,translate:async(text,target)=>{
  console.log("MOCK provider start",target);
  try { await db.doc("testMetrics/provider").set({calls:FieldValue.increment(1)},{merge:true}); }
  catch(error) { console.error("MOCK-only metric failure",error); throw error; }
  console.log("MOCK provider completed");
  return{text:`mock-${target}`,sourceLanguage:"pt"};
 }}),{getFirestore:()=>db,HttpsError});
// Build 44: gatilho de tradução única na aprovação, com provedor MOCK.
const {onDocumentWritten}=require("firebase-functions/v2/firestore");
const i18n=require("../place_description_i18n");
const mockMetric=async(kind)=>db.doc("testMetrics/approval").set({[kind]:FieldValue.increment(1)},{merge:true});
exports.onPlaceDescriptionApproved=onDocumentWritten({document:"places/{placeId}",region:"us-central1"},async(event)=>{
 const before=event.data?.before?.exists?event.data.before.data():null;
 const after=event.data?.after?.exists?event.data.after.data():null;
 // Isola o E2E antigo do callable (EmulatorPlace): o gatilho só age nos docs Approval*.
 if(!event.params.placeId.startsWith("Approval"))return;
 if(!i18n.shouldHandleWrite(before,after))return;
 const r=await i18n.translatePlaceOnApproval(event.params.placeId,{db,enabled:true,
  detect:async()=>{await mockMetric("detect");return "pt";},
  translate:async(text,target)=>{await mockMetric("translate");return{text:`mock-approval-${target}`,sourceLanguage:"pt"};}});
 console.log("MOCK onPlaceDescriptionApproved",r.outcome);
});
