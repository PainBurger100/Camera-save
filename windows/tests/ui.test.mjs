import {test} from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {parseHTML} from 'linkedom';
test('desktop workspace initializes with an isolated native bridge and all required elements',async()=>{
 const html=await fs.readFile(new URL('../ui/index.html',import.meta.url),'utf8');const {window,document}=parseHTML(html);globalThis.window=window;globalThis.document=document;globalThis.localStorage={getItem(){return null},setItem(){}};window.matchMedia=()=>({matches:false});window.foliow={resume:async()=>null,chooseFolder:async()=>null};
 const app=await fs.readFile(new URL('../ui/app.js',import.meta.url),'utf8');for(const [,id]of app.matchAll(/\$\('([^']+)'\)/g))assert.ok(document.getElementById(id),`missing element ${id}`);
 await import('../ui/app.js');assert.equal(document.getElementById('page-title').textContent,'Find your keepers.');document.querySelector('[data-view="pass"]').click();assert.equal(document.getElementById('page-title').textContent,'A little room to reconsider.');assert.equal(document.getElementById('export').disabled,true);assert.match(document.getElementById('download-zip').textContent,/Recycle Bin/);
});
