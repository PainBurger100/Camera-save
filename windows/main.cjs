'use strict';
const {app,BrowserWindow,ipcMain,dialog,shell,session,protocol,net}=require('electron');
const path=require('node:path');const fs=require('node:fs/promises');const {pathToFileURL}=require('node:url');
const {PhotoSession}=require('./photo-session.cjs');
const smoke=process.argv.includes('--smoke-test');
protocol.registerSchemesAsPrivileged([{scheme:'foliow',privileges:{standard:true,secure:true,supportFetchAPI:true,corsEnabled:true,stream:true}}]);
let window,photos;
app.setAppUserModelId('com.foliow.windows');
function authorized(event){if(event.sender!==window?.webContents || !event.senderFrame || event.senderFrame.url!=='foliow://app/index.html')throw new Error('This request is not from the photo workspace.');}
function handler(channel,callback){ipcMain.handle(channel,async(event,...args)=>{authorized(event);return callback(...args);});}
async function chooseFolder(initial){const result=await dialog.showOpenDialog(window,{title:'Choose a photo folder',defaultPath:initial,properties:['openDirectory']});return result.canceled?null:photos.openFolder(result.filePaths[0]);}
async function init(){
  if(smoke){const os=require('node:os');const directory=await fs.mkdtemp(path.join(os.tmpdir(),'foliow-smoke-'));app.setPath('userData',directory);}
  const uiRoot=path.join(__dirname,'ui');
  protocol.handle('foliow',request=>{
    const url=new URL(request.url);if(url.host!=='app')return new Response('Not found',{status:404});
    let relative;try{relative=decodeURIComponent(url.pathname).replace(/^\/+/, '')||'index.html';}catch{return new Response('Invalid path',{status:400});}
    const file=path.resolve(uiRoot,relative);if(file!==uiRoot&&!file.startsWith(uiRoot+path.sep))return new Response('Not found',{status:404});
    return net.fetch(pathToFileURL(file).href);
  });
  session.defaultSession.webRequest.onHeadersReceived((details,callback)=>callback({responseHeaders:{...details.responseHeaders,'Content-Security-Policy':["default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self' blob:; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-src 'none'; form-action 'none'"]}}));
  session.defaultSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
  session.defaultSession.setPermissionCheckHandler(()=>false);
  photos=new PhotoSession({stateDirectory:path.join(app.getPath('userData'),'sessions'),trash:file=>shell.trashItem(file)});
  window=new BrowserWindow({width:1360,height:950,minWidth:850,minHeight:650,show:!smoke,backgroundColor:'#f8f9f5',title:'Foliow — Photo review',icon:path.join(__dirname,'build','icon.ico'),webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true}});
  window.setMenuBarVisibility(false);
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  window.webContents.on('will-navigate',(event,url)=>{if(url!=='foliow://app/index.html')event.preventDefault();});
  window.webContents.on('will-attach-webview',event=>event.preventDefault());
  window.webContents.on('render-process-gone',(_event,details)=>{if(!smoke)dialog.showErrorBox('Photo workspace stopped','A preview could not finish. Reopen Foliow to restore your saved decisions. '+details.reason);});
  handler('photos:choose',()=>chooseFolder());
  handler('photos:drop',async folder=>{if(typeof folder!=='string'||!folder)throw new Error('Drop a photo folder from File Explorer.');return photos.openFolder(folder);});
  handler('photos:resume',async()=>{const root=await photos.rememberedFolder();return root?photos.openFolder(root):null;});
  handler('photos:read',({sessionId,id})=>photos.readPhoto(sessionId,id));
  handler('photos:decide',({sessionId,id,value})=>photos.setDecision(sessionId,id,value));
  handler('photos:prepare',id=>photos.prepareDeletion(id));
  handler('photos:recycle',token=>photos.recycle(token,async(count,name)=>{
    const result=await dialog.showMessageBox(window,{type:'warning',title:'Delete passed originals?',message:`Move ${count} passed photo${count===1?'':'s'} to the Recycle Bin?`,detail:`Folder: ${name}\n\nOnly the photos in the reviewed list will be removed from their original folders. Keepers and unreviewed photos stay in place. Restore recycled files using Windows Recycle Bin. Unavailable files are skipped; the app has no permanent-delete fallback.`,buttons:['Cancel',`Move ${count} to Recycle Bin`],defaultId:0,cancelId:0,noLink:true});return result.response===1;
  }));
  await window.loadURL('foliow://app/index.html');
  if(smoke)await runSmoke();
}
async function runSmoke(){
  let root;
  try{
    const os=require('node:os');root=await fs.mkdtemp(path.join(os.tmpdir(),'foliow-photos-'));
    await fs.copyFile(path.join(__dirname,'ui','assets','demo-1.jpg'),path.join(root,'sample.jpg'));
    const loaded=await photos.openFolder(root);
    const appState=await window.webContents.executeJavaScript('({title:document.title,ready:!!document.getElementById("folder-title"),bridge:typeof window.foliow.chooseFolder,node:typeof window.require})');
    if(!appState.ready||appState.bridge!=='function'||appState.node!=='undefined')throw new Error('The desktop workspace or isolated bridge did not initialize.');
    const bytes=await photos.readPhoto(loaded.sessionId,loaded.files[0].desktopId);if(bytes.length<1000)throw new Error('Photo bytes missing.');
    // Verify the same renderer path used to restore a real session, including image decoding.
    const renderResult=await window.webContents.executeJavaScript(`window.__foliowSmokeImport(${JSON.stringify(loaded)})`);
    if(renderResult!==true)throw new Error('The sample photo failed to render.');
    await photos.setDecision(loaded.sessionId,loaded.files[0].desktopId,'pass');const deletion=photos.prepareDeletion(loaded.sessionId);
    const recycled=await photos.recycle(deletion.token,async()=>true);if(recycled.deleted.length!==1)throw new Error('Windows recycling failed: '+JSON.stringify(recycled.errors));
    const cleared=await window.webContents.executeJavaScript(`window.__foliowSmokeImport(${JSON.stringify(recycled.session)})`);if(cleared!==true)throw new Error('The gallery did not clear after recycling its last photo.');
    console.log('SMOKE PASSED: isolated renderer, native folder/read bridge, JPEG preview, and native recycling of one disposable fixture.');
    app.exit(0);
  }catch(error){console.error('SMOKE FAILED:',error.stack||error.message);app.exit(1);}
}
app.whenReady().then(init).catch(error=>{console.error(error);if(!smoke)dialog.showErrorBox('Foliow could not start',error.message);app.exit(1);});
app.on('window-all-closed',()=>app.quit());
