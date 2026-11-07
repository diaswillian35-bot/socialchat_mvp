'use strict';
// Styles and brand assets reproduced from the live public event page (2026-11-06).
// Pure rendering: never reads Firestore, never serializes a source document.
const css = require('node:fs').readFileSync(require('node:path').join(__dirname, 'public_place.css'), 'utf8');
const brand = require('./public_place_brand.json');
const {buildPlaceAppLinks,appOpenScript,APP_STORE_URL}=require('./public_place_app_links');
const ORIGIN = 'https://remdy.app';
const LANGS = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];
const COPY = {
 'pt-BR': ['Local no Remdy','Abrir no app','Sobre','Informações','Localização','Horários','Categoria','Resumo','Compartilhar','Locais que você talvez queira conhecer','Local não encontrado','Este local não está disponível publicamente.','Só delivery','Abrir no Google Maps','Conheça este local no app Remdy.','Baixe o app Remdy e descubra locais perto de você.','Locais perto de você.','Explorar','Início','Todos os direitos reservados.','Eventos','Grupos','Pessoas','Organizadores','Buscar eventos, cidades...','em','Fechado','Segunda','Terça','Quarta','Quinta','Sexta','Sábado','Domingo'],
 'pt-PT': ['Local no Remdy','Abrir na app','Sobre','Informações','Localização','Horários','Categoria','Resumo','Partilhar','Locais que talvez queira conhecer','Local não encontrado','Este local não está disponível publicamente.','Apenas entrega','Abrir no Google Maps','Conheça este local na app Remdy.','Descarregue a app Remdy e descubra locais perto de si.','Locais perto de si.','Explorar','Início','Todos os direitos reservados.','Eventos','Grupos','Pessoas','Organizadores','Pesquisar eventos, cidades...','em','Fechado','Segunda','Terça','Quarta','Quinta','Sexta','Sábado','Domingo'],
 en: ['Place on Remdy','Open in app','About','Information','Location','Opening hours','Category','Summary','Share','Places you might like to discover','Place not found','This place is not publicly available.','Delivery only','Open in Google Maps','Discover this place in the Remdy app.','Get the Remdy app and discover places near you.','Places near you.','Explore','Home','All rights reserved.','Events','Groups','People','Organizers','Search events, cities...','in','Closed','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'],
 es: ['Lugar en Remdy','Abrir en la app','Acerca de','Información','Ubicación','Horarios','Categoría','Resumen','Compartir','Lugares que quizás quieras conocer','Lugar no encontrado','Este lugar no está disponible públicamente.','Solo entrega','Abrir en Google Maps','Descubre este lugar en la app Remdy.','Descarga la app Remdy y descubre lugares cerca de ti.','Lugares cerca de ti.','Explorar','Inicio','Todos los derechos reservados.','Eventos','Grupos','Personas','Organizadores','Buscar eventos, ciudades...','en','Cerrado','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'],
 fr: ['Lieu sur Remdy',"Ouvrir dans l’app",'À propos','Informations','Emplacement','Horaires','Catégorie','Résumé','Partager','Des lieux que vous pourriez aimer découvrir','Lieu introuvable',"Ce lieu n’est pas accessible au public.",'Livraison uniquement','Ouvrir dans Google Maps',"Découvrez ce lieu dans l’app Remdy.","Téléchargez l’app Remdy et découvrez des lieux près de vous.",'Des lieux près de vous.','Explorer','Accueil','Tous droits réservés.','Événements','Groupes','Personnes','Organisateurs','Rechercher événements, villes...','à','Fermé','Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'],
};
const CATEGORIES = {
 'pt-BR': ['Restaurante','Bar','Café','Hotel','Pousada','Casa noturna'],
 'pt-PT': ['Restaurante','Bar','Café','Hotel','Alojamento local','Discoteca'],
 en: ['Restaurant','Bar','Café','Hotel','Guest house','Nightclub'],
 es: ['Restaurante','Bar','Café','Hotel','Posada','Discoteca'],
 fr: ['Restaurant','Bar','Café','Hôtel',"Maison d’hôtes",'Boîte de nuit'],
};
const EXTRA_COPY = {
 'pt-BR': {gallery:'Galeria',photo:'foto',events:'Eventos que você talvez queira conhecer',explore:'Explore no Remdy',browse:'Explorar eventos',empty:'Novos locais e eventos públicos aparecerão aqui quando estiverem disponíveis.'},
 'pt-PT': {gallery:'Galeria',photo:'foto',events:'Eventos que talvez queira conhecer',explore:'Explore no Remdy',browse:'Explorar eventos',empty:'Novos locais e eventos públicos aparecerão aqui quando estiverem disponíveis.'},
 en: {gallery:'Gallery',photo:'photo',events:'Events you might like to discover',explore:'Explore on Remdy',browse:'Explore events',empty:'New public places and events will appear here when available.'},
 es: {gallery:'Galería',photo:'foto',events:'Eventos que quizás quieras conocer',explore:'Explora en Remdy',browse:'Explorar eventos',empty:'Los nuevos lugares y eventos públicos aparecerán aquí cuando estén disponibles.'},
 fr: {gallery:'Galerie',photo:'photo',events:'Des événements que vous pourriez aimer découvrir',explore:'Explorez sur Remdy',browse:'Explorer les événements',empty:'Les nouveaux lieux et événements publics apparaîtront ici dès leur disponibilité.'},
};
const ACTION_COPY = {
 'pt-BR': {directions:'Como chegar',orderInApp:'Ver cardápio e pedir'},
 'pt-PT': {directions:'Como chegar',orderInApp:'Ver ementa e pedir'},
 en: {directions:'Get directions',orderInApp:'View menu and order'},
 es: {directions:'Cómo llegar',orderInApp:'Ver menú y pedir'},
 fr: {directions:'Itinéraire',orderInApp:'Voir le menu et commander'},
};
const CATEGORY_KEYS = ['restaurant','bar','cafe','hotel','pousada','nightclub'];
const SCHEMA_TYPES = ['Restaurant','BarOrPub','CafeOrCoffeeShop','Hotel','BedAndBreakfast','NightClub'];
const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const text = v => typeof v === 'string' ? v.trim() : '';
const escapeHtml = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function safeHttps(v) { try { const u = new URL(text(v)); return u.protocol === 'https:' && !u.username && !u.password ? u.href : ''; } catch { return ''; } }
function validId(id) { return typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id); }
function isPublished(d) { return !!d && d.schemaVersion === 1 && d.active === true && d.deleted === false && d.moderationStatus === 'published'; }
function normalizeLanguage(raw) {
 const t = text(raw).toLowerCase().replace('_','-');
 if (t === 'pt-pt') return 'pt-PT';
 if (t === 'pt' || t === 'pt-br') return 'pt-BR';
 return ['en','es','fr'].find(l => t === l || t.startsWith(l+'-')) || null;
}
function chooseLanguage(header = '', explicit) {
 const direct = normalizeLanguage(explicit); if (direct) return direct;
 const parts = String(header).split(',').map((part,i) => {
  const [tag,...params] = part.trim().split(';');
  const qParam = params.find(p => p.trim().startsWith('q='));
  const q = qParam ? Number(qParam.trim().slice(2)) : 1;
  return {lang: normalizeLanguage(tag), q, i};
 }).filter(x => x.lang && x.q > 0 && x.q <= 1).sort((a,b)=>b.q-a.q || a.i-b.i);
 return parts[0]?.lang || 'pt-BR';
}
function categoryName(d, lang) { const i = CATEGORY_KEYS.indexOf(d.category); return i < 0 ? '' : CATEGORIES[lang][i]; }
function imageOf(d) { return safeHttps(d.coverUrl) || safeHttps(d.logoUrl) || (Array.isArray(d.photoUrls) ? d.photoUrls.map(safeHttps).find(Boolean) : '') || ''; }
function photosOf(d) {
 const urls=[];const add=raw=>{const url=safeHttps(raw);if(url&&!urls.includes(url)&&urls.length<7)urls.push(url);};
 add(d.coverUrl);if(Array.isArray(d.photoUrls))d.photoUrls.forEach(add);return urls;
}
function publicLocation(d) { return d.deliveryOnly !== true && d.addressPublic !== false && d.hideAddress !== true; }
// Identical URL pattern to public_event_model.mapsUrl: coordinates first.
function mapsUrlForPlace(d) {
 if(!publicLocation(d))return '';
 if(typeof d.latitude==='number'&&typeof d.longitude==='number'&&Math.abs(d.latitude)<=90&&Math.abs(d.longitude)<=180)return `https://www.google.com/maps/search/?api=1&query=${d.latitude},${d.longitude}`;
 if(!text(d.addressLine))return '';
 const line=[text(d.addressLine),text(d.district),text(d.cityName),text(d.stateName)].filter(Boolean).join(', ');
 return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(line)}`;
}
function hoursOf(d) {
 if (d.hours?.v !== 1 || !d.hours.days || typeof d.hours.days !== 'object') return [];
 return DAYS.map((day,i) => ({day, slots: Array.isArray(d.hours.days[String(i+1)]) ? d.hours.days[String(i+1)].filter(s => /^([01]\d|2[0-3]):[0-5]\d$/.test(s?.o) && /^([01]\d|2[0-3]):[0-5]\d$/.test(s?.c)) : []}));
}
function relatedPlaces(id, d, rows) {
 const seen = new Set([id]);
 return rows.filter(r => { if (!validId(r.id) || seen.has(r.id) || !isPublished(r.data) || !text(d.cityName) || r.data.cityName !== d.cityName || (d.countryCode && r.data.countryCode !== d.countryCode)) return false; seen.add(r.id);return true; }).slice(0,6);
}
function jsonLd(id,d) {
 const obj = {'@context':'https://schema.org','@type': SCHEMA_TYPES[CATEGORY_KEYS.indexOf(d.category)] || 'LocalBusiness',name:text(d.name),url:`${ORIGIN}/l/${id}`,address:{'@type':'PostalAddress',addressLocality:text(d.cityName)}};
 const image = imageOf(d); const photos=photosOf(d);if (image || photos.length) obj.image = [...new Set([...photos,...(safeHttps(d.logoUrl)?[safeHttps(d.logoUrl)]:[])])];
 if (text(d.countryCode)) obj.address.addressCountry = text(d.countryCode);
 if (text(d.stateName)) obj.address.addressRegion = text(d.stateName);
 if (publicLocation(d)) {
  if (text(d.addressLine)) obj.address.streetAddress = text(d.addressLine);
  if (text(d.postalCode)) obj.address.postalCode = text(d.postalCode);
  if (typeof d.latitude === 'number' && typeof d.longitude === 'number' && Math.abs(d.latitude)<=90 && Math.abs(d.longitude)<=180) obj.geo = {'@type':'GeoCoordinates',latitude:d.latitude,longitude:d.longitude};
 }
 const hours = hoursOf(d).flatMap(h => h.slots.map(s => ({'@type':'OpeningHoursSpecification',dayOfWeek:`https://schema.org/${h.day}`,opens:s.o,closes:s.c})));
 if (hours.length) obj.openingHoursSpecification = hours;
 return obj;
}
function jsonForScript(obj) { return JSON.stringify(obj).replace(/[<>&\u2028\u2029]/g, c => '\\u'+c.charCodeAt(0).toString(16).padStart(4,'0')); }
function renderPlacePage({id,data,language='pt-BR',related=[],recommendations=null}) {
 const lang = LANGS.includes(language) ? language : 'pt-BR';const t=COPY[lang];const x=EXTRA_COPY[lang];const actions=ACTION_COPY[lang];const e=escapeHtml;
 const found = validId(id) && isPublished(data); const d=found?data:{};
 const url = validId(id) ? `${ORIGIN}/l/${id}` : `${ORIGIN}/`;
 const category = categoryName(d,lang);const city = text(d.cityName);
 const title = found ? `${text(d.name)}${category?' · '+category:''}${city?' '+t[25]+' '+city:''} | Remdy` : `${t[10]} | Remdy`;
 const desc = found ? `${text(d.name)}${city?' '+t[25]+' '+city:''}. ${text(d.description) || t[14]}`.slice(0,220) : t[11];
 const image=imageOf(d);const appLinks=validId(id)?buildPlaceAppLinks(id):null;
 const logo=`<img class="remdy-logo-full" src="${e(brand.logo)}" alt="Remdy" decoding="async">`;
 const whiteLogo=`<img class="remdy-logo-full remdy-logo-on-dark" src="${e(brand.whiteLogo || brand.logo)}" alt="Remdy" decoding="async">`;
 const icon=`<img class="remdy-icon" src="${e(brand.icon)}" alt="" width="18" height="18">`;
 const open=`<a class="btn btn-primary" href="${e(appLinks?.download||ORIGIN)}" data-open-app>${icon} ${e(t[1])}</a>`;
 const header=`<header class="site-header"><div class="site-header-inner"><a class="brand" href="${ORIGIN}/" aria-label="Remdy">${logo}</a><nav class="nav-links">${[20,21,22,23].map((i,j)=>`<a href="${ORIGIN}/${j===0?'eventos':''}">${e(t[i])}</a>`).join('')}</nav><div class="header-actions"><form class="search-form" method="get" action="${ORIGIN}/eventos"><input type="search" name="cidade" placeholder="${e(t[24])}" aria-label="${e(t[24])}"></form>${open}<button type="button" class="menu-toggle" id="menuToggle" aria-label="Menu">☰</button></div></div><div class="mobile-nav" id="mobileNav">${[20,21,22,23].map((i,j)=>`<a href="${ORIGIN}/${j===0?'eventos':''}">${e(t[i])}</a>`).join('')}${open}</div></header>`;
 const footer=`<section class="download-band">${whiteLogo}<h2>${e(t[14])}</h2><p>${e(t[15])}</p><div class="actions"><a class="btn btn-primary" style="background:#fff;color:var(--navy)" href="https://play.google.com/store/apps/details?id=com.remdy.app">Google Play</a><a class="btn btn-ghost" style="border-color:rgba(255,255,255,.4);color:#fff" href="${APP_STORE_URL}">App Store</a></div></section><footer class="site-footer"><div class="footer-inner"><div>${whiteLogo}<p>${e(t[16])}</p></div><div><h3>${e(t[17])}</h3><a href="${ORIGIN}/eventos">${e(t[20])}</a><a href="${ORIGIN}/">${e(t[18])}</a></div><div><h3>App</h3><a href="https://play.google.com/store/apps/details?id=com.remdy.app">Google Play</a><a href="${APP_STORE_URL}">App Store</a></div></div><div class="copy">© ${new Date().getUTCFullYear()} Remdy. ${e(t[19])}</div></footer>`;
 const hours=hoursOf(d);const hoursText=hours.length?hours.map((h,i)=>`${t[27+i]}: ${h.slots.length?h.slots.map(s=>`${s.o}–${s.c}`).join(', '):t[26]}`).join('\n'):text(d.hoursNote);
 const location = [publicLocation(d)?text(d.addressLine):'',text(d.district),city,text(d.stateName)].filter(Boolean).join(' · ');
 const maps=mapsUrlForPlace(d);
 const primaryAction=d.deliveryOnly?`<a class="btn btn-primary btn-wide" href="${e(appLinks?.download||ORIGIN)}" data-open-app>${icon} ${e(actions.orderInApp)}</a>`:maps?`<a href="${e(maps)}" target="_blank" rel="noopener noreferrer">${e(actions.directions)}</a>`:'';
 const share=`<a class="btn btn-hero" href="https://wa.me/?text=${encodeURIComponent(text(d.name)+' '+url)}">${e(t[8])}</a>`;
 const placeRows=recommendations?.places || relatedPlaces(id,d,related);
 const cards=placeRows.filter(r=>r.id!==id&&validId(r.id)&&isPublished(r.data)).slice(0,6).map(r=>`<article class="ev-card"><a href="${ORIGIN}/l/${r.id}?lang=${lang}"><div class="thumb">${imageOf(r.data)?`<img src="${e(imageOf(r.data))}" alt="${e(r.data.name)}" loading="lazy">`:''}</div></a><div class="ev-card-body"><span class="badge">${e(categoryName(r.data,lang))}</span><h3><a href="${ORIGIN}/l/${r.id}?lang=${lang}">${e(r.data.name)}</a></h3><div class="muted">${e(r.data.cityName)}</div></div></article>`).join('');
 const gallery=photosOf(d).map((url,i)=>`<a href="${e(url)}" target="_blank" rel="noopener noreferrer" aria-label="${e(d.name)} — ${e(x.photo)} ${i+1}" style="border-radius:10px;overflow:hidden;aspect-ratio:1;background:#e8edf5;display:flex;align-items:center;justify-content:center"><img src="${e(url)}" alt="${e(d.name)} — ${e(x.photo)} ${i+1}" loading="lazy" style="width:100%;height:100%;object-fit:contain"></a>`).join('');
 const eventCards=(recommendations?.events || []).slice(0,6).filter(r=>validId(r.id)).map(r=>`<article class="ev-card"><a href="${ORIGIN}/e/${r.id}"><div class="thumb">${safeHttps(r.image)?`<img src="${e(safeHttps(r.image))}" alt="${e(r.title)}" loading="lazy">`:''}</div></a><div class="ev-card-body">${r.category?`<span class="badge">${e(r.category)}</span>`:''}<h3><a href="${ORIGIN}/e/${r.id}">${e(r.title)}</a></h3><div class="muted">${e(r.date)}</div><div class="muted">${e(r.city)}</div></div></article>`).join('');
 const recTitle=cards?t[9]:eventCards?x.events:x.explore;
 const recSection=`<section class="carousel-section" id="related-places" data-kind="${cards?'places':eventCards?'events':'explore'}"><h2>${e(recTitle)}</h2>${cards||eventCards?`<div class="carousel"><div class="carousel-track">${cards||eventCards}</div></div>`:`<div class="panel"><p>${e(x.empty)}</p><a class="btn btn-primary" href="${ORIGIN}/eventos">${e(x.browse)}</a></div>`}</section>`;
 const body=found?`<nav class="breadcrumb"><a href="${ORIGIN}/">${e(t[18])}</a> › <strong>${e(d.name)}</strong></nav><section class="hero"><div class="hero-bg">${image?`<img src="${e(image)}" alt="" style="width:100%;height:100%;object-fit:cover">`:''}</div><div class="hero-inner${safeHttps(d.logoUrl)?' has-side':''}"><div><div class="hero-kicker"><span class="hero-seal">${icon} ${e(t[0])}</span><span class="hero-badge">${e(category)}</span>${d.deliveryOnly?`<span class="hero-badge" id="delivery-badge">${e(t[12])}</span>`:''}</div><h1>${e(d.name)}</h1><p class="hero-city">${e([city,d.stateName].filter(Boolean).join(' · '))}</p><p class="hero-summary">${e(text(d.description).slice(0,160))}</p><div class="hero-meta-grid">${d.deliveryOnly?'':`<span>${e(location)}</span>`}</div><div class="hero-actions">${open}${share}</div></div>${safeHttps(d.logoUrl)?`<div class="hero-side"><img class="logo-chip" src="${e(safeHttps(d.logoUrl))}" alt="${e(d.name)}"></div>`:''}</div></section><nav class="tabs-bar"><div class="tabs-wrap"><div class="tabs-inner"><a href="#sobre">${e(t[2])}</a><a href="#informacoes">${e(t[3])}</a><a href="#localizacao">${e(t[4])}</a>${gallery?`<a href="#galeria">${e(x.gallery)}</a>`:''}</div></div></nav><div class="layout"><main class="main-col"><section class="panel section-anchor" id="sobre"><h2>${e(t[2])}</h2><p style="white-space:pre-line">${e(d.description)}</p></section><section class="panel section-anchor" id="informacoes"><h2>${e(t[3])}</h2><ul class="quick-list"><li><strong>${e(t[6])}</strong>${e(category)}</li>${hoursText?`<li><strong>${e(t[5])}</strong><span style="white-space:pre-line">${e(hoursText)}</span></li>`:''}</ul></section><section class="panel section-anchor" id="localizacao"><h2>${e(t[4])}</h2><p>${e(location)}</p>${primaryAction?`<div id="place-primary-action">${primaryAction}</div>`:''}</section>${gallery?`<section class="panel section-anchor" id="galeria"><h2>${e(x.gallery)}</h2><div class="gallery-grid">${gallery}</div></section>`:''}</main><aside class="sidebar"><div class="panel"><h2>${e(t[1])}</h2><div class="participate-brand">${icon}<p>${e(t[14])}</p></div>${open}</div><div class="panel"><h2>${e(t[7])}</h2><ul class="quick-list"><li><strong>${e(t[6])}</strong>${e(category)}</li><li><strong>${e(t[4])}</strong>${e(city)}</li></ul></div></aside></div>${recSection}`:`<main class="layout"><section class="panel"><h1>${e(t[10])}</h1><p>${e(t[11])}</p></section></main>`;
 const alternates=found?LANGS.map(l=>`<link rel="alternate" hreflang="${l}" href="${url}?lang=${l}">`).join('')+`<link rel="alternate" hreflang="x-default" href="${url}">`:'';
 const canonical = found && lang !== 'pt-BR' ? `${url}?lang=${lang}` : url;
 return {status:found?200:404,html:`<!DOCTYPE html><html lang="${lang}"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${e(title)}</title><meta name="description" content="${e(desc)}"><link rel="canonical" href="${e(canonical)}">${alternates}<meta name="robots" content="${found?'index,follow':'noindex,follow'}"><meta property="og:type" content="website"><meta property="og:site_name" content="Remdy"><meta property="og:title" content="${e(title)}"><meta property="og:description" content="${e(desc)}"><meta property="og:url" content="${url}"><meta property="og:locale" content="${lang.replace('-','_')}">${image?`<meta property="og:image" content="${e(image)}"><meta property="og:image:alt" content="${e(d.name)}"><meta name="twitter:image" content="${e(image)}">`:''}<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${e(title)}"><meta name="twitter:description" content="${e(desc)}">${found?`<script type="application/ld+json">${jsonForScript(jsonLd(id,d))}</script>`:''}<style>${css}</style></head><body>${header}${body}${footer}<script>
 document.getElementById('menuToggle').addEventListener('click',function(){document.getElementById('mobileNav').classList.toggle('open')});
 ${appLinks?appOpenScript(appLinks):''}
 </script></body></html>`};
}
function buildPlacesSitemap(rows) {
 const seen=new Set();const urls=[];
 for(const r of rows){if(!validId(r.id)||!isPublished(r.data)||seen.has(r.id))continue;seen.add(r.id);
  const raw=r.data.updatedAt||r.data.publishedAt||r.data.createdAt;let date;
  try {date=raw?.toDate?raw.toDate():typeof raw==='string'?new Date(raw):null;}catch{date=null;}
  const lastmod=date && Number.isFinite(date.getTime())?`<lastmod>${date.toISOString()}</lastmod>`:'';
  for(const lang of LANGS) urls.push(`<url><loc>${ORIGIN}/l/${r.id}${lang==='pt-BR'?'':`?lang=${lang}`}</loc>${lastmod}</url>`);
 }
 return `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls.join('')}</urlset>`;
}
// XML protocol limits: up to 50,000 URL entries per sitemap = 10,000 places.
function buildPlacesSitemapResponse(rows, page) {
 const unique = [...new Map(rows.filter(r=>validId(r.id)&&isPublished(r.data)).map(r=>[r.id,r])).values()];
 const count = Math.ceil(unique.length / 10000);
 if (count <= 1 && !page) return buildPlacesSitemap(unique);
 if (page) {
  if (!/^\d+$/.test(String(page)) || Number(page)<1 || Number(page)>Math.max(1,count)) return null;
  return buildPlacesSitemap(unique.slice((Number(page)-1)*10000, Number(page)*10000));
 }
 return `<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${Array.from({length:count},(_,i)=>`<sitemap><loc>${ORIGIN}/sitemap-locais.xml?page=${i+1}</loc></sitemap>`).join('')}</sitemapindex>`;
}
module.exports={ORIGIN,LANGS,escapeHtml,safeHttps,photosOf,mapsUrlForPlace,validId,isPublished,chooseLanguage,relatedPlaces,jsonLd,jsonForScript,renderPlacePage,buildPlacesSitemap,buildPlacesSitemapResponse};
