export const RAW_EXTENSIONS = new Set('cr2 cr3 nef nrw arw srf sr2 dng raf orf rw2 pef srw raw rwl 3fr iiq erf kdc mos mrw x3f'.split(' '));
const IMAGE_EXTENSIONS = new Set('jpg jpeg jpe png webp avif gif bmp tif tiff heic heif ico jfif'.split(' '));
export const extension = name => name.split('.').pop().toLowerCase();
export const supported = file => RAW_EXTENSIONS.has(extension(file.name)) || IMAGE_EXTENSIONS.has(extension(file.name));
export const fileKey = file => `${file.webkitRelativePath || file.relativePath || file.name}|${file.size}|${file.lastModified}`;
export class ReviewModel {
  constructor(){ this.items=[]; this.history=[]; this.view='review'; this.activeId=null; }
  load(files, saved={}){
    this.items=[]; this.history=[]; this.view='review'; const seen=new Set();
    for(const file of files){ const id=fileKey(file); if(!supported(file)||seen.has(id))continue; seen.add(id); this.items.push({id,file,decision:['keep','pass'].includes(saved[id])?saved[id]:null}); }
    this.sort('name'); this.activeId=this.visible()[0]?.id || null;
  }
  sort(by){ this.items.sort(by==='date' ? (a,b)=>a.file.lastModified-b.file.lastModified || a.file.name.localeCompare(b.file.name,undefined,{numeric:true}) : (a,b)=>(a.file.webkitRelativePath||a.file.relativePath||a.file.name).localeCompare(b.file.webkitRelativePath||b.file.relativePath||b.file.name,undefined,{numeric:true})); }
  visible(){return this.items.filter(item=>this.view==='review'?!item.decision:item.decision===this.view);}
  current(){const items=this.visible();return items.find(i=>i.id===this.activeId)||items[0];}
  choose(decision){const current=this.current();if(!current)return;const visible=this.visible();const index=visible.indexOf(current);if(current.decision!==decision)this.history.push({id:current.id,before:current.decision});current.decision=decision;const remaining=this.visible();this.activeId=remaining.some(i=>i.id===current.id)?remaining[(index+1)%remaining.length]?.id:remaining[Math.min(index,remaining.length-1)]?.id||null;return current;}
  undo(){const last=this.history.pop();if(!last)return;const item=this.items.find(i=>i.id===last.id);item.decision=last.before;this.view=last.before||'review';this.activeId=item.id;return item;}
  skip(){const items=this.visible();const current=this.current();this.activeId=items[(items.indexOf(current)+1)%items.length]?.id||null;}
  counts(){return {total:this.items.length,keep:this.items.filter(i=>i.decision==='keep').length,pass:this.items.filter(i=>i.decision==='pass').length,pending:this.items.filter(i=>!i.decision).length};}
  decisions(){return Object.fromEntries(this.items.filter(i=>i.decision).map(i=>[i.id,i.decision]));}
}
