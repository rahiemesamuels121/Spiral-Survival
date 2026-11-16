// Optional UI logic tests: NODE_PATH=/path/to/jsdom/node_modules node tools/board_editor/test_editor.cjs
// Start the helper with --no-browser first. Requests that would save to the game are mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');
(async () => {
  const base = process.env.BOARD_EDITOR_URL || 'http://127.0.0.1:8765';
  const original = await fetch(base+'/api/board').then(r=>r.json());
  const html = await fetch(base+'/').then(r=>r.text());
  const errors=[];const consoleCapture=new VirtualConsole();consoleCapture.on('jsdomError',e=>errors.push(e));
  const dom=new JSDOM(html,{url:base,runScripts:'outside-only',pretendToBeVisual:true,virtualConsole:consoleCapture});
  const win=dom.window,$=id=>win.document.getElementById(id);
  let posted=null,exported=null;
  win.confirm=()=>true;
  win.Blob=Blob;win.URL.createObjectURL=()=> 'blob:editor-test';win.URL.revokeObjectURL=()=>{};
  win.HTMLAnchorElement.prototype.click=function(){};
  win.fetch=async (route,options={})=>{
    if(route==='/api/save'){
      posted=JSON.parse(options.body);
      assert.ok(options.headers['X-Editor-Token']);
      return {ok:true,json:async()=>({board:{...posted.board,onlineBoardId:'spiral-quest-board-qa'},digest:'test-saved-digest',backup:'tools/board_editor/backups/test.json'})};
    }
    if(route==='/api/export'){exported=JSON.parse(options.body);return {ok:true,json:async()=>({board:exported.board})};}
    return fetch(base+route,options);
  };
  const wait=async fn=>{for(let i=0;i<200;i++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw new Error('Timed out waiting for editor');};
  const change=(id,value)=>{$(id).value=value;$(id).dispatchEvent(new win.Event('input',{bubbles:true}));};
  const select=index=>{change('jump',String(index));$('go').click();};
  const apply=()=> $('tile-form').dispatchEvent(new win.Event('submit',{cancelable:true,bubbles:true}));
  const effect=kind=>{$('effect').value=kind;$('effect').dispatchEvent(new win.Event('change',{bubbles:true}));};
  let checks=0;const check=(name,fn)=>{fn();checks++;console.log('PASS',name);};
  try {
    win.eval(fs.readFileSync(path.join(__dirname,'editor.js'),'utf8'));
    await wait(()=>$('loading').hidden);
    check('current board renders all 120 selectable spaces',()=>assert.equal(win.document.querySelectorAll('[data-tile]').length,120));
    select(87);
    check('selection loads the snake rule and its real destination',()=>{assert.equal($('effect').value,'snake');assert.equal($('destination').value,'10');});
    effect('star');apply();
    check('editing changes the preview and preserves selection',()=>{assert.equal($('effect').value,'star');assert.match(win.document.querySelector('[data-tile="87"]').getAttribute('aria-label'),/Star/);});
    $('undo').click();check('undo restores the previous effect',()=>assert.equal($('effect').value,'snake'));
    $('redo').click();check('redo reapplies the effect',()=>assert.equal($('effect').value,'star'));
    select(85);change('swap-target','110');$('swap').click();
    check('swapping exchanges contents without moving the spaces',()=>assert.equal($('effect').value,'normal'));
    select(110);assert.equal($('effect').value,'mine');
    select(0);check('START cannot be changed to another effect',()=>{assert.equal($('effect').value,'start');assert.equal($('effect').disabled,true);});
    select(62);effect('normal');apply();
    check('broken hospital links are highlighted and cannot be saved',()=>{assert.match($('validation-heading').textContent,/issues? to fix/);assert.equal($('save').disabled,true);assert.equal($('download').disabled,true);});
    $('undo').click();check('restoring a required hospital makes the board valid',()=>assert.equal($('validation-heading').textContent,'Ready to save'));
    select(1);change('x','50');change('y','50');apply();$('restore-layout').click();
    check('restore layout returns tiles to the symmetric spiral grid',()=>{assert.equal($('x').value,'6.6');assert.equal($('y').value,'12.8');});
    change('label','<script>window.hacked=1</script>');apply();
    check('labels are treated as text, never executable HTML',()=>{assert.equal(win.hacked,undefined);assert.equal(win.document.querySelectorAll('#board script').length,0);});
    $('save').click();await wait(()=>posted && $('save').disabled && !$('download').disabled);
    check('save sends a valid board with the original conflict digest',()=>{assert.equal(posted.expectedDigest,original.digest);assert.equal(posted.board.tiles[85].type,'normal');assert.equal(posted.board.tiles[110].type,'mine');assert.equal(posted.board.tiles[85].x,original.board.tiles[85].x);assert.equal(posted.board.tiles[110].y,original.board.tiles[110].y);});
    $('download').click();await wait(()=>exported);
    check('JSON copies are exported without additional source writes',()=>assert.equal(exported.board.version,2));
    const untouched=await fetch(base+'/api/board').then(r=>r.json());
    check('UI tests leave the real game source untouched',()=>assert.equal(untouched.digest,original.digest));
    assert.deepEqual(errors,[]);
    console.log(`${checks} editor UI checks passed`);
  } finally {win.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
