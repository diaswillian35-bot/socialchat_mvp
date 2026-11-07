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
