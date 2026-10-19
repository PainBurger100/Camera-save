'use strict';
const fs=require('node:fs');const path=require('node:path');
const root=path.resolve(__dirname,'..');const target=path.join(root,'ui','vendor');const modules=path.join(root,'node_modules');
fs.mkdirSync(path.join(target,'raw'),{recursive:true});fs.mkdirSync(path.join(target,'extract'),{recursive:true});
function copy(module,source,destination){fs.copyFileSync(path.join(modules,module,source),path.join(target,destination));}
for(const file of ['index.js','worker.js','libraw.wasm'])copy('libraw-wasm-nothread','dist/'+file,'raw/'+file);
function copyJS(from,to){fs.mkdirSync(to,{recursive:true});for(const entry of fs.readdirSync(from,{withFileTypes:true})){if(entry.isDirectory())copyJS(path.join(from,entry.name),path.join(to,entry.name));else if(entry.name.endsWith('.js'))fs.copyFileSync(path.join(from,entry.name),path.join(to,entry.name));}}
copyJS(path.join(modules,'extract-raw-preview','dist'),path.join(target,'extract'));
copy('exifr','dist/full.esm.mjs','exifr.mjs');copy('utif','UTIF.js','utif.js');copy('pako','dist/pako.min.js','pako.min.js');copy('heic2any','dist/heic2any.min.js','heic2any.min.js');
console.log('Prepared offline photo decoders.');
