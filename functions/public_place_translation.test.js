"use strict";
const test = require("node:test"); const assert = require("node:assert/strict");
const fs = require("node:fs");
const {createPlaceHandler} = require("./public_places");
const c = require("./place_description_cache");
const original = "Original português 🍔";
const place = {schemaVersion:1,active:true,deleted:false,moderationStatus:"published",description:original,name:"John",cityName:"Toronto"};
function response(){return{headers:{},set(k,v){this.headers[k]=v;return this},status(v){this.code=v;return this},send(v){this.body=v;return this}};}
function dbFor(row, {broken=false, data=place}={}) {
 const reads=[];
 const db={collection(name){return{
  doc(id){return{get:async()=>{reads.push([name,id]);if(name===c.CACHE){if(broken)throw Error("offline");return{exists:!!row,data:()=>row};}return{exists:true,data:()=>data};}}},
  where(){return this},orderBy(){return this},limit(){return this},get:async()=>({docs:[],size:0})
 };}};
 return {db,reads};
}
for(const lang of ['pt-BR','pt-PT','en','es','fr']) test(`page uses only cached translation for ${lang}`,async()=>{
 const row={status:'ready',sourceHash:c.hash(original),targetLanguage:c.language(lang),sourceLanguage:lang.startsWith('pt')?'en':'pt',text:'Cached translated <safe>'};
 const {db,reads}=dbFor(row);const res=response();
 await createPlaceHandler(db)({method:'GET',path:'/l/JohnID',query:{},get:()=>`${lang};q=1,en;q=0.5`},res);
 assert.equal(res.code,200);assert.ok(res.body.includes('Cached translated &lt;safe&gt;'));
 assert.equal(res.headers.Vary,'Accept-Language');assert.ok(res.headers['Cache-Control'].includes('s-maxage=600'));
 assert.ok(reads.some(([name,id])=>name===c.CACHE&&id===c.cacheId('JohnID',c.language(lang),c.hash(original))));
});
for(const mode of ['missing','failed','reserved','stale','same','broken'])test(`page falls back to original: ${mode}`,async()=>{
 let row={status:'ready',sourceHash:c.hash(original),targetLanguage:'en',sourceLanguage:'pt',text:'WRONG TEXT'};
 if(mode==='missing')row=null;
 if(['failed','reserved'].includes(mode))row.status=mode;
 if(mode==='stale')row.sourceHash=c.hash('Old');
 if(mode==='same')row.sourceLanguage='en';
 const {db}=dbFor(row,{broken:mode==='broken'});const res=response();
 await createPlaceHandler(db)({method:'GET',path:'/l/JohnID',query:{lang:'en'},get:()=>''},res);
 assert.equal(res.code,200);assert.ok(res.body.includes(original));assert.ok(!res.body.includes('WRONG TEXT'));
});
test('unpublished page never reads translation cache',async()=>{
 const {db,reads}=dbFor(null,{data:{...place,active:false}});const res=response();
 await createPlaceHandler(db)({method:'GET',path:'/l/JohnID',query:{},get:()=>''},res);
 assert.equal(res.code,404);assert.ok(!reads.some(([name])=>name===c.CACHE));
});
test('public cache helper imports no API/client and contains no writes',()=>{
 const source=fs.readFileSync('place_description_cache.js','utf8');
 assert.doesNotMatch(source,/google-auth|translation.googleapis|\.set\(|runTransaction/);
});
