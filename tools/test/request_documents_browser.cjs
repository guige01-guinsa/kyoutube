const fs=require('fs'),path=require('path'),http=require('http');
const {chromium}=require('playwright');
const root=process.cwd();
const config=JSON.parse(fs.readFileSync('firebase.web.json','utf8'));
const policy=config.hosting.headers[0].headers.find(h=>h.key==='Content-Security-Policy').value.replace('; upgrade-insecure-requests','');
const server=http.createServer((req,res)=>{
  res.setHeader('Content-Security-Policy',policy);res.setHeader('X-Content-Type-Options','nosniff');
  if(req.url==='/favicon.ico'){res.writeHead(204).end();return;}
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><html><body><h1>Local PDF verification</h1><script type="module" src="/request-documents.js"></script></body></html>');return;}
  const name=req.url==='/fixture.pdf'?path.join(root,'.artifacts/request-documents/request-ko.pdf'):path.join(root,'web',decodeURIComponent(req.url.split('?')[0]));
  if(!name.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  if(!fs.existsSync(name)){res.writeHead(404).end();return;}
  const ext=path.extname(name);res.setHeader('Content-Type',({'.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm','.pdf':'application/pdf'})[ext]||'application/octet-stream');res.end(fs.readFileSync(name));
});
(async()=>{
 await new Promise(r=>server.listen(8788,'127.0.0.1',r));
 const browser=await chromium.launch({headless:true,channel:"chrome"});
 try{
  const page=await browser.newPage();const violations=[],errors=[],network=[];
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('pageerror',e=>errors.push(e.message));
  page.on('request',r=>network.push(r.url()));
  await page.goto('http://127.0.0.1:8788/');
  await page.evaluate(()=>{window.pdfViolations=[];document.addEventListener('securitypolicyviolation',e=>window.pdfViolations.push({directive:e.violatedDirective,uri:e.blockedURI}));});
  const result=await page.evaluate(async()=>{
    const bytes=new Uint8Array(await(await fetch('/fixture.pdf')).arrayBuffer());
    const pages=await window.recipeScoutPdfRaster(bytes);
    for(const png of pages){const img=document.createElement('img');img.src=URL.createObjectURL(new Blob([png],{type:'image/png'}));img.style.width='360px';document.body.appendChild(img);}
    return {pages:pages.length,sizes:pages.map(p=>p.byteLength)};
  });
  await page.screenshot({path:'.artifacts/request-documents/browser-preview.png',fullPage:true});
  // Do not invoke a physical printer. Replace only the iframe print entry point.
  const printed=await page.evaluate(async()=>{
    let called=0;
    const create=document.createElement.bind(document);
    document.createElement=function(name,...args){const el=create(name,...args);if(name==='iframe')el.addEventListener('load',()=>{el.contentWindow.print=()=>{called++;};});return el;};
    const bytes=new Uint8Array(await(await fetch('/fixture.pdf')).arrayBuffer());
    await window.recipeScoutPdfPrint(bytes,'test');
    return called;
  });
  violations.push(...await page.evaluate(()=>window.pdfViolations));
  const report={...result,printCalls:printed,violations,errors,externalRequests:network.filter(u=>/^https?:/.test(u)&&!u.startsWith('http://127.0.0.1:8788/'))};
  fs.writeFileSync('.artifacts/request-documents/browser-report.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
  if(result.pages!==3||printed!==1||violations.length||report.externalRequests.length)process.exitCode=1;
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e.message);server.close();process.exitCode=1;});
