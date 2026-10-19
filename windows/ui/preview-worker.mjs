import {extractThumbnail} from './vendor/extract/browser.js';
self.onmessage=async ({data:{id,buffer}})=>{
  try { const r=await extractThumbnail(new Uint8Array(buffer),{prefer:'largest',maxBytes:40*1024*1024});
    if(!r.found)self.postMessage({id,found:false});
    else { const bytes=Uint8Array.from(r.data);self.postMessage({id,found:true,bytes,mimeType:r.mimeType,width:r.width,height:r.height},[bytes.buffer]); }
  }catch{ self.postMessage({id,found:false}); }
};
