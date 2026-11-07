'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const logic = require('./public_place_logic');
function publishedQuery(db) {
 return db.collection('places').where('schemaVersion','==',1).where('active','==',true).where('deleted','==',false).where('moderationStatus','==','published');
}
// Exported handlers accept an injected DB for read-only integration tests.
function createPlaceHandler(db) {
 return async (req,res) => {
  if (!['GET','HEAD'].includes(req.method)) return res.set('Allow','GET, HEAD').status(405).send('Method not allowed');
  res.set('Vary','Accept-Language').set('Content-Type','text/html; charset=utf-8').set('X-Content-Type-Options','nosniff');
  res.set('Cache-Control','public, max-age=300, s-maxage=600');
  const lang=logic.chooseLanguage(req.get('Accept-Language'),req.query?.lang);
  const match=(req.path||'').match(/^\/l\/([A-Za-z0-9_-]{1,128})\/?$/);const id=match?.[1]||'';
  try {
   const snap=id?await db.collection('places').doc(id).get():null;
   const data=snap?.exists?snap.data():null;let related=[];
   if(logic.isPublished(data) && data.cityName){
    try {const pool=await publishedQuery(db).where('cityName','==',data.cityName).limit(7).get();related=pool.docs.map(d=>({id:d.id,data:d.data()}));}
    catch(error){console.warn('publicPlaces related query unavailable',error.code||'unknown');}
   }
   const page=logic.renderPlacePage({id,data,language:lang,related});return res.status(page.status).send(page.html);
  } catch(error){console.error('renderPublicPlacePage',error.code||'unknown');return res.set('Cache-Control','no-store').status(503).send('Temporarily unavailable');}
 };
}
function createSitemapHandler(db){return async(req,res)=>{
 if(!['GET','HEAD'].includes(req.method))return res.set('Allow','GET, HEAD').status(405).send('Method not allowed');
 try{
  const rows=[];let last=null;
  // Read pages, not an 80-item catalog. A sitemap shard holds <= 50k URLs (5/locale).
  for(;;){let q=publishedQuery(db).orderBy(admin.firestore.FieldPath.documentId()).limit(500);if(last)q=q.startAfter(last);const snap=await q.get();
   for(const d of snap.docs)rows.push({id:d.id,data:d.data()});
   if(snap.size<500)break;last=snap.docs[snap.docs.length-1];
  }
  const xml=logic.buildPlacesSitemapResponse(rows,req.query?.page);
  if(xml===null)return res.set('Cache-Control','no-store').status(404).send('Not found');
  return res.set('Content-Type','application/xml; charset=utf-8').set('Cache-Control','public, max-age=300, s-maxage=600').status(200).send(xml);
 }catch(error){console.error('renderPlacesSitemap',error.code||error.message);return res.set('Cache-Control','no-store').status(503).send('Temporarily unavailable');}
};}
exports.createPlaceHandler=createPlaceHandler;
exports.createSitemapHandler=createSitemapHandler;
exports.renderPublicPlacePage=onRequest({region:'us-central1',invoker:'public',cors:false},(req,res)=>createPlaceHandler(admin.firestore())(req,res));
exports.renderPlacesSitemap=onRequest({region:'us-central1',invoker:'public',cors:false},(req,res)=>createSitemapHandler(admin.firestore())(req,res));
