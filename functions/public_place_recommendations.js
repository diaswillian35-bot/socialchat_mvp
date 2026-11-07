'use strict';
// Read-only recommendation policy, sharing the public event landing gates.
const {isPublished,validId,safeHttps}=require('./public_place_logic');
const text=v=>typeof v==='string'?v.trim():'';
const folded=v=>text(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
function dateMillis(raw){try{const d=raw?.toDate?raw.toDate():raw instanceof Date?raw:new Date(raw);return raw==null||!Number.isFinite(d.getTime())?0:d.getTime();}catch{return 0;}}
function coordinates(d){return typeof d.latitude==='number'&&typeof d.longitude==='number'&&Math.abs(d.latitude)<=90&&Math.abs(d.longitude)<=180?[d.latitude,d.longitude]:null;}
function distance(a,b){const rad=x=>x*Math.PI/180;const [p,q]=a.map(rad),[r,s]=b.map(rad);const h=Math.sin((r-p)/2)**2+Math.cos(p)*Math.cos(r)*Math.sin((s-q)/2)**2;return 6371*2*Math.asin(Math.sqrt(Math.min(1,h)));}
function pickPlaceRecommendations(id,current,cityRows=[],otherRows=[]){
 const seen=new Set([id]);const eligible=r=>validId(r.id)&&isPublished(r.data)&&!seen.has(r.id);
 const sameCountry=r=>!current.countryCode||!r.data.countryCode||folded(r.data.countryCode)===folded(current.countryCode);
 const take=rows=>rows.filter(r=>{if(!eligible(r))return false;seen.add(r.id);return true;});
 const local=take(cityRows.filter(r=>r.data.cityName===current.cityName&&sameCountry(r))).slice(0,6);
 if(local.length>=3)return local;
 // Proximity is only a ranking signal; coordinates are never serialized here.
 const origin=coordinates(current);
 const other=otherRows.filter(r=>r.data.cityName!==current.cityName).slice().sort((a,b)=>{
  const ac=coordinates(a.data),bc=coordinates(b.data);
  if(origin&&ac&&bc)return distance(origin,ac)-distance(origin,bc)||dateMillis(b.data.updatedAt)-dateMillis(a.data.updatedAt);
  if(origin&&!!ac!==!!bc)return ac?-1:1;
  return dateMillis(b.data.updatedAt)-dateMillis(a.data.updatedAt)||a.id.localeCompare(b.id);
 });
 return [...local,...take(other)].slice(0,6);
}
function isUpcomingPublicEvent(d,nowMs=Date.now()){
 if(!d||d.isActive!==true||d.isPublic===false||d.deleted===true||d.archived===true)return false;
 const status=text(d.status).toLowerCase();
 // Fail closed for explicit editorial states; preserve the landing's active legacy contract.
 if(status&&!['approved','published'].includes(status))return false;
 if(d.visibility!=null&&text(d.visibility).toLowerCase()!=='public')return false;
 if(d.moderationStatus!=null&&!['approved','published'].includes(text(d.moderationStatus).toLowerCase()))return false;
 if(d.seoIndexable===false||d.isDemo===true||d.demo===true||d.isTest===true||d.testEvent===true)return false;
 const start=dateMillis(d.startAt),end=dateMillis(d.endAt);
 return start>nowMs&&(!end||end>=start);
}
function pickEventRecommendations(current,rows=[],nowMs=Date.now()){
 const seen=new Set();const eligible=rows.filter(r=>{
  if(!validId(r.id)||seen.has(r.id)||!isUpcomingPublicEvent(r.data,nowMs))return false;
  if(current.countryCode&&folded(r.data.countryCode)!==folded(current.countryCode))return false;
  seen.add(r.id);return true;
 });
 const local=r=>folded(r.data.city||r.data.cityName)===folded(current.cityName);
 eligible.sort((a,b)=>Number(local(b))-Number(local(a))||dateMillis(a.data.startAt)-dateMillis(b.data.startAt)||a.id.localeCompare(b.id));
 return eligible.slice(0,6);
}
function eventCard(r,lang){
 const d=r.data;const start=dateMillis(d.startAt);let date='';
 try{date=new Intl.DateTimeFormat(lang,{dateStyle:'medium',timeStyle:'short',timeZone:text(d.eventTimeZone)||'UTC'}).format(start);}catch{date=new Intl.DateTimeFormat(lang,{dateStyle:'medium',timeZone:'UTC'}).format(start);}
 return{id:r.id,title:text(d.title),city:text(d.city||d.cityName),category:text(d.category||d.type),image:safeHttps(d.coverUrl)||(Array.isArray(d.photoUrls)?d.photoUrls.map(safeHttps).find(Boolean):'')||'',date};
}
module.exports={dateMillis,distance,pickPlaceRecommendations,isUpcomingPublicEvent,pickEventRecommendations,eventCard};
