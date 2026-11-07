'use strict';
// Same store destinations as appDownloadRedirect (f8922ad); no place contacts.
const APP_STORE_URL='https://apps.apple.com/br/app/id6780296747';
const PLAY_STORE_URL='https://play.google.com/store/apps/details?id=com.remdy.app';
const DOWNLOAD_REDIRECT='https://us-central1-socialchatmvp.cloudfunctions.net/appDownloadRedirect';
function buildPlaceAppLinks(id){
 if(typeof id!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(id))throw new TypeError('Invalid place ID');
 const download=`${DOWNLOAD_REDIRECT}?l=${encodeURIComponent(id)}`;
 return{id,canonical:`https://remdy.app/l/${id}`,scheme:`remdy://l/${id}`,download,ios:APP_STORE_URL,play:PLAY_STORE_URL,
  android:`intent://remdy.app/l/${id}#Intent;scheme=https;package=com.remdy.app;S.browser_fallback_url=${encodeURIComponent(download)};end`};
}
function appOpenScript(links){
 // ID and URLs are generated constants, not fields from the place document.
 const json=JSON.stringify(links).replace(/</g,'\\u003c');
 return `(function(){
 const links=${json};
 document.querySelectorAll('[data-open-app]').forEach(function(button){button.addEventListener('click',function(event){
  const ua=navigator.userAgent||'';
  const ios=/iPhone|iPad|iPod/i.test(ua)||(/Macintosh/i.test(ua)&&navigator.maxTouchPoints>1);
  if(/Android/i.test(ua)){event.preventDefault();window.location.href=links.android;return;}
  if(!ios)return; // No-JS/desktop link uses the real redirect function.
  event.preventDefault();let timer;
  function cleanup(){clearTimeout(timer);document.removeEventListener('visibilitychange',changed);window.removeEventListener('pagehide',cancel);}
  function cancel(){cleanup();}
  function changed(){if(document.hidden)cancel();}
  document.addEventListener('visibilitychange',changed);window.addEventListener('pagehide',cancel);
  timer=setTimeout(function(){cleanup();if(!document.hidden)window.location.href=links.ios;},1400);
  window.location.href=links.scheme;
 });});
 })();`;
}
module.exports={APP_STORE_URL,PLAY_STORE_URL,DOWNLOAD_REDIRECT,buildPlaceAppLinks,appOpenScript};
