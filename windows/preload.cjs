'use strict';
const {contextBridge,ipcRenderer,webUtils}=require('electron');
contextBridge.exposeInMainWorld('foliow',{
  chooseFolder:()=>ipcRenderer.invoke('photos:choose'),
  openDroppedFolder:file=>ipcRenderer.invoke('photos:drop',webUtils.getPathForFile(file)),
  resume:()=>ipcRenderer.invoke('photos:resume'),
  readPhoto:(sessionId,id)=>ipcRenderer.invoke('photos:read',{sessionId,id}),
  decide:(sessionId,id,value)=>ipcRenderer.invoke('photos:decide',{sessionId,id,value}),
  prepareDeletion:sessionId=>ipcRenderer.invoke('photos:prepare',sessionId),
  recycle:token=>ipcRenderer.invoke('photos:recycle',token)
});
