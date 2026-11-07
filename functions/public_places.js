'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const logic = require('./public_place_logic');
const recommendations = require('./public_place_recommendations');
const {readCachedDescription} = require('./place_description_cache');
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
   const data=snap?.exists?snap.data():null;let selected={places:[],events:[]};
   if(logic.isPublished(data)){
    const nowMs=Date.now();let cityRows=[],pool=[];
    if(data.cityName)try{
     const snap=await publishedQuery(db).where('cityName','==',data.cityName).limit(7).get();cityRows=snap.docs.map(d=>({id:d.id,data:d.data()}));
    }catch(error){console.warn('publicPlaces city query unavailable',error.code||'unknown');}
    selected.places=recommendations.pickPlaceRecommendations(id,data,cityRows);
    if(selected.places.length<3)try{
     const snap=await publishedQuery(db).orderBy('updatedAt','desc').limit(24).get();pool=snap.docs.map(d=>({id:d.id,data:d.data()}));
     selected.places=recommendations.pickPlaceRecommendations(id,data,cityRows,pool);
    }catch(error){console.warn('publicPlaces recent query unavailable',error.code||'unknown');}
    if(!selected.places.length){
     // Respect the same global public-events switch as renderPublicEventPage.
     let publicEventsOnline=false;
     try{const config=await db.collection('config').doc('publicEvents').get();publicEventsOnline=config.exists&&config.data()?.enabled===true;}catch(error){console.warn('publicPlaces event switch unavailable',error.code||'unknown');}
     if(publicEventsOnline){
     const upcoming=()=>{
      let q=db.collection('events').where('isActive','==',true);
      if(data.countryCode)q=q.where('countryCode','==',String(data.countryCode).toLowerCase());
      return q.where('startAt','>=',new Date(nowMs)).orderBy('startAt','asc');
     };
     let eventRows=[];
     if(data.cityName)try{
      const snap=await upcoming().where('city','==',data.cityName).limit(16).get();eventRows=snap.docs.map(d=>({id:d.id,data:d.data()}));
     }catch(error){console.warn('publicPlaces city events query unavailable',error.code||'unknown');}
     if(recommendations.pickEventRecommendations(data,eventRows,nowMs).length<3)try{
      const snap=await upcoming().limit(40).get();eventRows.push(...snap.docs.map(d=>({id:d.id,data:d.data()})));
     }catch(error){console.warn('publicPlaces national events query unavailable',error.code||'unknown');}
     selected.events=recommendations.pickEventRecommendations(data,eventRows,nowMs).map(r=>recommendations.eventCard(r,lang));
     }
    }
   }
   let renderData=data;
   if(logic.isPublished(data)&&typeof data.description==='string'&&data.description){
    try{
     const translated=await readCachedDescription(db,id,data.description,lang);
     if(translated!==null)renderData={...data,description:translated};
    }catch(_){/* Cache unavailable: original. Never invoke translation here. */}
   }
   const page=logic.renderPlacePage({id,data:renderData,language:lang,recommendations:selected});return res.status(page.status).send(page.html);
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
