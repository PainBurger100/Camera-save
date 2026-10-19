'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const EXTENSIONS = new Set('cr2 cr3 nef nrw arw srf sr2 dng raf orf rw2 pef srw raw rwl 3fr iiq erf kdc mos mrw x3f jpg jpeg jpe jfif png webp avif gif bmp tif tiff heic heif ico'.split(' '));
const MAX_PREVIEW_SIZE = 512 * 1024 * 1024;
function within(root, candidate) {
  const rel = path.relative(root, candidate);
  return rel !== '' && rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel);
}
function stamp(stat) { return { size: String(stat.size), modified: String(stat.mtimeNs), inode: String(stat.ino), device: String(stat.dev) }; }
function same(a,b) { return a && b && ['size','modified','inode','device'].every(k=>a[k]===b[k]); }
function decision(value) { if(value !== null && value !== 'keep' && value !== 'pass') throw new Error('Invalid photo decision.');return value; }
class PhotoSession {
  constructor({stateDirectory, trash}) {
    this.stateDirectory=stateDirectory;this.trash=trash;this.root=null;this.id=null;this.records=new Map();this.deleting=false;this.confirmations=new Map();this.queue=Promise.resolve();
  }
  async rememberedFolder() { try {const x=JSON.parse(await fs.readFile(path.join(this.stateDirectory,'last-folder.json'),'utf8'));return typeof x.root==='string'?x.root:null;}catch{return null;} }
  statePath(root=this.root) {return path.join(this.stateDirectory,createHash('sha256').update(root).digest('hex')+'.json');}
  async atomicWrite(destination, data) {
    await fs.mkdir(this.stateDirectory,{recursive:true});const temporary=destination+'.'+randomUUID()+'.tmp';
    try{await fs.writeFile(temporary,JSON.stringify(data));await fs.rename(temporary,destination);}finally{await fs.rm(temporary,{force:true}).catch(()=>{});}
  }
  async save() {
    const payload={version:1,root:this.root,decisions:[...this.records.values()].filter(r=>r.decision).map(r=>({relativePath:r.relativePath,fingerprint:r.fingerprint,decision:r.decision}))};
    await this.atomicWrite(this.statePath(),payload);
  }
  serialized(action) {const result=this.queue.then(action,action);this.queue=result.catch(()=>{});return result;}
  assertSession(id) { if(!this.id || id!==this.id)throw new Error('This folder session changed. Open it again.'); }
  async safeFile(record) {
    const full=path.join(this.root,record.relativePath);
    if(!within(this.root,full))throw new Error('This photo is outside the selected folder.');
    let cursor=this.root;
    const rootStat=await fs.lstat(cursor);if(rootStat.isSymbolicLink()||!rootStat.isDirectory())throw new Error('The selected folder is no longer available.');
    for(const part of path.relative(this.root,full).split(path.sep)) {
      cursor=path.join(cursor,part);const st=await fs.lstat(cursor);
      if(st.isSymbolicLink())throw new Error('Symbolic links and junctions cannot be used for file operations.');
    }
    const real=await fs.realpath(full);
    if(!within(this.root,real))throw new Error('This photo is outside the selected folder.');
    const current=await fs.stat(full,{bigint:true});
    if(!current.isFile()||!same(record.fingerprint,stamp(current)))throw new Error('The original changed since review. Reopen the folder and review it again.');
    return full;
  }
  async openFolder(folder) {
    return this.serialized(async()=>{
      if(this.deleting)throw new Error('Wait for the current deletion to finish.');
      const root=await fs.realpath(folder);const rootStat=await fs.stat(root);if(!rootStat.isDirectory())throw new Error('Choose a photo folder.');
      let prior=[];try{const data=JSON.parse(await fs.readFile(this.statePath(root),'utf8'));if(data.root===root&&Array.isArray(data.decisions))prior=data.decisions;}catch{}
      const saved=new Map(prior.map(r=>[r.relativePath,r]));const records=new Map();
      const visit=async directory=>{
        const entries=await fs.readdir(directory,{withFileTypes:true});
        for(const entry of entries){
          if(entry.isSymbolicLink()||entry.name.startsWith('.')||['$RECYCLE.BIN','System Volume Information'].includes(entry.name))continue;
          const full=path.join(directory,entry.name);if(!within(root,full))continue;
          if(entry.isDirectory()){await visit(full);continue;}
          if(!entry.isFile()||!EXTENSIONS.has(path.extname(entry.name).slice(1).toLowerCase()))continue;
          const stat=await fs.lstat(full,{bigint:true});if(!stat.isFile()||stat.isSymbolicLink())continue;
          const relativePath=path.relative(root,full);const fingerprint=stamp(stat);const old=saved.get(relativePath);const id=randomUUID();
          records.set(id,{id,name:entry.name,relativePath,fingerprint,size:Number(stat.size),lastModified:Number(stat.mtimeNs/1000000n),decision:same(old?.fingerprint,fingerprint)&&['keep','pass'].includes(old?.decision)?old.decision:null});
        }
      };
      await visit(root);
      if(!records.size)throw new Error('No supported photos found. Choose a folder containing JPEG, CR2, RAW, HEIC, PNG or TIFF files.');
      this.root=root;this.records=records;this.id=randomUUID();this.confirmations.clear();
      await this.atomicWrite(path.join(this.stateDirectory,'last-folder.json'),{root});await this.save();return this.snapshot();
    });
  }
  snapshot() {return {sessionId:this.id,name:path.basename(this.root),folderPath:this.root,files:[...this.records.values()].map(r=>({desktopId:r.id,name:r.name,relativePath:r.relativePath.split(path.sep).join('/'),size:r.size,lastModified:r.lastModified,decision:r.decision}))};}
  async setDecision(sessionId,id,value) {
    return this.serialized(async()=>{
      this.assertSession(sessionId);if(this.deleting)throw new Error('Wait for deletion to finish.');
      const r=this.records.get(id);if(!r)throw new Error('Unknown photo.');const previous=r.decision;r.decision=decision(value);
      try{await this.save();}catch(error){r.decision=previous;throw new Error('Could not save this decision: '+error.message);}return true;
    });
  }
  async readPhoto(sessionId,id) {
    this.assertSession(sessionId);const r=this.records.get(id);if(!r)throw new Error('Unknown photo.');
    if(r.size>MAX_PREVIEW_SIZE)throw new Error('This photo is too large for an in-memory preview. You can skip it.');
    const full=await this.safeFile(r);const handle=await fs.open(full,'r');
    try{if(!same(r.fingerprint,stamp(await handle.stat({bigint:true}))))throw new Error('The original changed since review.');const data=await handle.readFile();if(!same(r.fingerprint,stamp(await handle.stat({bigint:true}))))throw new Error('The original changed while opening.');return data;}finally{await handle.close();}
  }
  prepareDeletion(sessionId) {
    this.assertSession(sessionId);if(this.deleting)throw new Error('Wait for deletion to finish.');
    this.confirmations.clear();const files=[...this.records.values()].filter(r=>r.decision==='pass').map(r=>({...r}));
    if(!files.length)throw new Error('No passed photos to delete.');const token=randomUUID();
    this.confirmations.set(token,{sessionId,expires:Date.now()+5*60*1000,files});return {token,folderName:path.basename(this.root),files:files.map(r=>({name:r.name,relativePath:r.relativePath,size:r.size})),count:files.length};
  }
  async recycle(token,confirm) {
    return this.serialized(async()=>{
      const snapshot=this.confirmations.get(token);this.confirmations.delete(token);
      if(!snapshot||snapshot.expires<Date.now())throw new Error('This deletion review expired. Open the list again.');this.assertSession(snapshot.sessionId);
      if(snapshot.files.some(r=>this.records.get(r.id)?.decision!=='pass'))throw new Error('Your decisions changed. Review the deletion list again.');
      this.deleting=true;
      try{
        if(!await confirm(snapshot.files.length,path.basename(this.root)))return {cancelled:true,deleted:[],errors:[],session:this.snapshot()};
        const deleted=[],errors=[];
        for(const r of snapshot.files){
          try{
            if(this.records.get(r.id)?.decision!=='pass')throw new Error('This photo is no longer passed.');
            const full=await this.safeFile(r);await this.trash(full);this.records.delete(r.id);deleted.push(r.id);
          }catch(e){errors.push({name:r.name,message:e.message});}
        }
        let saveError=null;try{await this.save();}catch(e){saveError=e.message;}
        return {cancelled:false,deleted,errors,saveError,session:this.snapshot()};
      }finally{this.deleting=false;}
    });
  }
}
module.exports={PhotoSession,within,stamp,same,EXTENSIONS};
