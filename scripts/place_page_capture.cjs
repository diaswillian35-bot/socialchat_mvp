// Local screenshot harness. An isolated headless profile on the SSD, no logins.
const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process');
const root=path.resolve(__dirname,'..');const version=process.env.PLACE_PAGE_VERSION||'v2';const out='/Users/macbookairm1/remdy_e2e/place_page';
const child=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--remote-debugging-port=0','--disable-background-networking','--disable-default-apps','--no-first-run','--no-default-browser-check','--user-data-dir='+path.join(root,'e2e/chrome-'+version+'-profile'),'about:blank'],{stdio:['ignore','ignore','pipe']});
const timer=setTimeout(()=>{child.kill();process.exitCode=1;console.error('Screenshot timed out');},90000);
(async()=>{const endpoint=await new Promise((resolve,reject)=>{let out='';child.stderr.on('data',b=>{out+=b;const m=out.match(/DevTools listening on (ws:\/\/[^\s]+)/);if(m)resolve(m[1]);});child.on('error',reject);});
 const ws=new WebSocket(endpoint);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});let seq=0;const pending=new Map(),listeners=[];
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}}else for(const f of listeners)f(m);};
 const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params,sessionId}));});const proofs={};
 const configs=version==='v3'?[{name:'desktop-pt-BR',lang:'pt-BR',width:1280,height:900,mobile:false},{name:'mobile-pt-BR',lang:'pt-BR',width:390,height:844,mobile:true},{name:'physical-fixture',lang:'pt-BR',width:1280,height:900,mobile:false,input:'place-v3-physical-fixture.html',expectedPhotos:0}]:[{name:'desktop-pt-BR',lang:'pt-BR',width:1280,height:900,mobile:false},{name:'mobile-pt-BR',lang:'pt-BR',width:390,height:844,mobile:true},{name:'desktop-en',lang:'en',width:1280,height:900,mobile:false}];
 for(const config of configs){  const {targetId}=await send('Target.createTarget',{url:'about:blank'});const {sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
  await send('Emulation.setDeviceMetricsOverride',{width:config.width,height:config.height,deviceScaleFactor:1,mobile:config.mobile},sessionId);await send('Page.enable',{},sessionId);
  const loaded=new Promise(r=>listeners.push(m=>{if(m.sessionId===sessionId&&m.method==='Page.loadEventFired')r();}));await send('Page.navigate',{url:'file://'+path.join(root,'e2e/'+(config.input||'john-'+version+'-'+config.lang+'.html'))},sessionId);await loaded;
  // Scroll to trigger lazy-loading as a reader would; production HTML stays lazy.
  const result=await send('Runtime.evaluate',{expression:`(async()=>{for(let y=0;y<document.body.scrollHeight;y+=600){scrollTo(0,y);await new Promise(r=>setTimeout(r,140));}await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));scrollTo(0,0);await new Promise(r=>setTimeout(r,200));const g=document.getElementById('galeria'),r=document.getElementById('related-places'),p=document.getElementById('place-primary-action');return JSON.stringify({width:innerWidth,bodyWidth:document.body.scrollWidth,height:document.body.scrollHeight,galleryPhotos:g?g.querySelectorAll('img').length:0,galleryY:g?g.getBoundingClientRect().top:0,primaryText:p?.innerText,primaryHref:p?.querySelector('a')?.href,primaryClass:p?.querySelector('a')?.className,primaryY:p?.getBoundingClientRect().top,relatedKind:r.dataset.kind,relatedCards:r.querySelectorAll('.ev-card').length,relatedText:r.innerText,relatedY:r.getBoundingClientRect().top,images:Array.from(document.images).map(i=>({width:i.naturalWidth,complete:i.complete}))})})()`,awaitPromise:true,returnByValue:true},sessionId);
  const proof=JSON.parse(result.result.value);if(proof.width!==config.width||proof.bodyWidth>config.width||proof.galleryPhotos!==(config.expectedPhotos??5)||proof.images.some(i=>!i.width))throw new Error(JSON.stringify(proof));proofs[config.name]=proof;
  const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y:0,width:config.width,height:proof.height,scale:1}},sessionId);fs.writeFileSync(path.join(out,'john-'+version+'-'+(version==='v3'?'full-':'')+config.name+'.png'),Buffer.from(shot.data,'base64'));
  if(version==='v3'){
   if(!proof.primaryText||!proof.primaryHref)throw new Error('Primary action missing');
   const y=Math.max(0,proof.primaryY-160);const area=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y,width:config.width,height:Math.min(proof.height-y,420),scale:1}},sessionId);fs.writeFileSync(path.join(out,'john-v3-'+config.name+'.png'),Buffer.from(area.data,'base64'));
  }
  if(version==='v2'&&config.name==='desktop-pt-BR'){
   const y=Math.max(0,proof.galleryY-20);const detail=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y,width:config.width,height:Math.min(proof.height-y,proof.relatedY-y+320),scale:1}},sessionId);fs.writeFileSync(path.join(out,'john-v2-gallery-related-pt-BR.png'),Buffer.from(detail.data,'base64'));
  }
  await send('Target.closeTarget',{targetId});console.log(config.name,proof);
 }
 fs.writeFileSync(path.join(root,'e2e/browser-'+version+'-proof.json'),JSON.stringify(proofs,null,2));fs.copyFileSync(path.join(root,'e2e/browser-'+version+'-proof.json'),path.join(out,'browser-'+version+'-proof.json'));
 await send('Browser.close');ws.close();clearTimeout(timer);
})().catch(e=>{console.error(e);clearTimeout(timer);child.kill();process.exitCode=1;});
