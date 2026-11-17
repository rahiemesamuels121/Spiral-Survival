'use strict';
(() => {
const $ = id => document.getElementById(id);
const NS = 'http://www.w3.org/2000/svg';
const copy = value => JSON.parse(JSON.stringify(value));
const effects = {
  start:['Start','The start of the route. Its role is locked.'], normal:['Normal','A safe space with no extra effect.'],
  sea:['Sea','Swimmers cross safely without a boat. Other characters need a boat to cross the sea or surf, or drown and restart.'],
  boat:['Boat','Add boats to inventory.'], antidote:['Antidote','Add antidotes to inventory.'], rawMeat:['Raw meat','Collect meat to survive a lion.'],
  surf:['Surf','Water hazard: swimmers cross safely without a boat. Other players need a boat or return to START.'],
  lion:['Lion','Cat Whisperers pass safely without consuming supplies. Other characters use one raw meat. Otherwise, automatically use a health pack to recover and stay here; without a pack, become injured and go to the selected hospital.'], snake:['Snake','An antidote protects the player. Without one, go to the selected antidote tile.'],
  cash:['Cash','Add the amount to the player’s cash.'], police:['Police','Confiscate weapons and offer a bribe while the player stays at the encounter. Paying avoids jail and missed turns; refusing sends them to the nearest jail for one turn. Amount sets the bribe; 0 uses 20. Carried stars require jail without a bribe option.'],
  fine:['Fine','Charge the amount; unpaid fines become debt.'], jail:['Jail','Miss this many turns. A value of 0 uses one turn.'], goToJail:['Go to jail','Send the player to the selected jail.'],
  mine:['Mine','Red kills and restarts. Green uses one health pack or sends the injured player to hospital. Broken blue has equal chances of death or a treatable injury.'], portal:['Portal','Choose a mystery card to travel to the nearest portal behind or ahead.'],
  setBack:['Move back','Move backwards this many spaces.'], moveForward:['Move forward','Move forwards this many spaces.'],
  shop:['Weapon shop','Offer the game’s weapon catalog. Prices are set by the game rules.'], event:['Event card','Draw an event card.'],
  confusion:['Confusion','The player’s next dice move goes backwards.'], star:['Star','Add stars and the standard 25-coin bonus. Police can confiscate stars and impose missed turns.'],
  secretSociety:['Secret Society','Hire the single hitman for $200 ($150 for Secret Agents) and place him on any space. Secret Agents can also access this tile from up to 3 route spaces away before rolling or after landing nearby; other characters must land here. Only the hirer sees him and may choose one target within 20 route spaces on their turn. Use the hitman before rolling: one kill releases him and ends the turn without movement. A contract hired after landing waits for a later turn.'],
  hospital:['Hospital','Each hospital starts with 2 health kits and generates 1 every 5 real minutes without a limit. Sold-out kits cannot be purchased. Healthy players shop for health packs (10 coins) and antidotes (5 coins). Packs automatically heal lion, fire and trap-door injuries before hospital travel. Injured visitors pay 10 coins, use a pack, or restart for free.'],
  fire:['Fire','Automatically use a health pack to recover and stay here; without a pack, injure the player and send them to the selected hospital.'], trapDoor:['Trap door','Miss one turn. Automatically use a health pack to recover and stay here; without a pack, become injured and go to the selected hospital.'], finish:['Finish','An exact roll wins. Its role is locked.']
};
const artwork = ['none','spiral','boat','water','skull','antidote','snake','cash','police','jail','mine','portal','back','forward','shop','dice','star','stop','jet','fire','diamond','train','surf','lion','rawMeat','hospital','secretSociety','trapDoor','confusion','startFlag'];
const symbols = {start:'startFlag',sea:'water',surf:'surf',boat:'boat',antidote:'antidote',rawMeat:'rawMeat',lion:'lion',snake:'snake',cash:'cash',police:'police',fine:'cash',jail:'jail',goToJail:'jail',mine:'mine',portal:'portal',setBack:'back',moveForward:'forward',shop:'shop',event:'dice',confusion:'confusion',star:'star',hospital:'hospital',secretSociety:'secretSociety',fire:'fire',trapDoor:'trapDoor',finish:'stop',normal:'none'};
const targetTypes = {snake:'antidote',goToJail:'jail',lion:'hospital',fire:'hospital',trapDoor:'hospital'};
const amountTypes = new Set(['boat','antidote','rawMeat','cash','fine','police','jail','setBack','moveForward','star']);
const contents = ['type','label','amount','destination','consumesAntidote','artwork','fillColor','textColor','mineColor'];
let state = null, selected = 0, baseDigest = '', savedState = '', past = [], future = [], formPending = false, busy = false;
let view = {x:0,y:0,w:1000,h:1000}, drag = null, drawQueued = false, toastTimer;
const storageKey = 'spiral-board-workshop-v1';
const token = document.querySelector('meta[name="editor-token"]').content;

function toast(message, error = false) {
  $('toast').textContent = message; $('toast').classList.toggle('error',error); $('toast').hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => {$('toast').hidden=true;}, error?7000:3500);
}
function setStatus(message) {$('status').textContent=message;}
function dirty() {return !!state && (JSON.stringify(state)!==savedState || formPending);}
function color(value) {return '#'+(Number(value)&0xffffff).toString(16).padStart(6,'0');}
function palette(tile) {
  if(tile.fillColor!=null) return [color(tile.fillColor),tile.textColor!=null?color(tile.textColor):luminance(color(tile.fillColor))>.4?'#203c43':'#ffffff'];
  let fill='#f8f1e2',ink='#213e47';
  if(['start','boat','sea'].includes(tile.type)){fill='#2d6b83';ink='#ffffff';}
  else if(['rawMeat','antidote','snake','cash','moveForward'].includes(tile.type))fill='#bad3bd';
  else if(['jail','goToJail','star'].includes(tile.type))fill='#e2c98e';
  else if(tile.type==='police'){fill='#2b4455';ink='#ffffff';}
  else if(['portal','confusion'].includes(tile.type)){fill='#6b5b89';ink='#ffffff';}
  else if(tile.type==='mine'){fill=({red:'#B73542',blue:'#236DC1',green:'#27834C'})[tile.mineColor||'red'];ink='#ffffff';}
  else if(['fire','trapDoor','fine','setBack','finish','lion'].includes(tile.type)){fill='#97464f';ink='#ffffff';}
  else if(tile.type==='normal')fill=tile.index%2?'#efe5d1':'#f8f1e2';
  if(tile.textColor!=null)ink=color(tile.textColor);
  return [fill,ink];
}
function luminance(hex){const rgb=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;}
function node(tag, attrs={}, text) {const el=document.createElementNS(NS,tag);for(const [key,value] of Object.entries(attrs))el.setAttribute(key,String(value));if(text!=null)el.textContent=text;return el;}
function iconFor(tile) {
  if(tile.artwork) return tile.artwork==='spiral'?'portal':tile.artwork;
  if(tile.type==='cash' && tile.label.includes('TRAIN'))return 'train';
  if(tile.type==='normal')return {JET:'jet',FIRE:'fire',SURF:'surf',BOAT:'boat','ORANGE ICON':'diamond',SPIRAL:'portal',S:'lion'}[tile.label.toUpperCase()]||'none';
  return symbols[tile.type]||'none';
}
function caption(tile) {if(tile.label==='START · SPIRAL')return 'START';if(tile.label==='STOP · FINISH')return 'FINISH';return tile.label|| (tile.type==='normal'?'':(effects[tile.type]?.[0]||tile.type).toUpperCase());}
function wrapLabel(text) {const lines=[];let line='';for(const word of text.split(/\s+/)){if((line+' '+word).trim().length>9&&line){lines.push(line);line=word;}else line=(line+' '+word).trim();}if(line)lines.push(line);return lines.slice(0,2);}
function renderBoard() {
  if(!state)return;
  const svg=$('board');svg.replaceChildren();svg.setAttribute('viewBox',`${view.x} ${view.y} ${view.w} ${view.h}`);
  svg.append(node('rect',{x:0,y:0,width:1000,height:1000,rx:28,fill:'#101e29',stroke:'#b69b67','stroke-width':3}));
  for(let i=0;i<4;i++)svg.append(node('rect',{x:i%2?500:20,y:i<2?20:500,width:480,height:480,rx:28,fill:['#192e39','#1c2c39','#203438','#1c3438'][i]}));
  const segments=new Map();for(const tile of state.tiles){const key=tile.segment||'route';if(!segments.has(key))segments.set(key,[]);segments.get(key).push(tile);}
  let stripe=0;for(const tiles of segments.values()){
    if(tiles.length<2)continue;const d=tiles.map((t,i)=>`${i?'L':'M'}${t.x*1000},${t.y*1000}`).join(' ');
    for(const [stroke,width] of [[['#608d93','#9f747a','#c6aa70','#699887'][stripe++%4],73],['#d8d1be',66]])svg.append(node('path',{d,fill:'none',stroke,'stroke-width':width,'stroke-linecap':'round','stroke-linejoin':'round'}));
  }
  if($('route').checked)svg.append(node('path',{d:state.tiles.map((t,i)=>`${i?'L':'M'}${t.x*1000},${t.y*1000}`).join(' '),fill:'none',stroke:'#88c5ba','stroke-width':2,'stroke-dasharray':'5 5',opacity:.75}));
  svg.append(node('rect',{x:360,y:473,width:280,height:60,rx:18,fill:'#142a34',stroke:'#a88e5f'}));
  svg.append(node('text',{x:500,y:506,'font-size':26,class:'board-title'},'SPIRAL QUEST'));
  svg.append(node('text',{x:500,y:524,'font-size':8,class:'board-title',fill:'#bbc6bc'},'FORTUNE / DANGER / SURVIVAL'));
  for(const tile of state.tiles){
    const x=tile.x*1000,y=tile.y*1000,[fill,ink]=palette(tile),g=node('g',{'data-tile':tile.index,class:`tile${tile.index===selected?' selected':''}`,tabindex:0,role:'button','aria-label':`Tile ${tile.index}: ${effects[tile.type]?.[0]||tile.type}`});
    g.append(node('title',{},`Tile ${tile.index} · ${effects[tile.type]?.[0]||tile.type}`));
    g.append(node('rect',{x:x-25,y:y-25,width:50,height:50,rx:5,fill,stroke:'#fcf5e5','stroke-width':1.2,class:'tile-frame'}));
    g.append(node('rect',{x:x-22,y:y-22,width:44,height:44,rx:2,fill:'none',stroke:ink,'stroke-width':.5,opacity:.45}));
    g.append(node('rect',{x:x-29,y:y-29,width:58,height:58,rx:8,class:'selection-ring'}));
    const label=caption(tile),symbol=iconFor(tile);
    if(symbol!=='none')g.append(node('use',{href:`/icons.svg#icon-${symbol}`,x:x-25,y:y-25+(label?0:8),width:50,height:50,color:ink,'pointer-events':'none'}));
    else if(tile.type==='normal')g.append(node('rect',{x:x-21,y:y-21,width:42,height:3,rx:1,fill:['#608d93','#9f747a','#c6aa70','#699887'][Math.floor(tile.index/4)%4]}));
    const lines=wrapLabel(label);lines.forEach((line,i)=>g.append(node('text',{x,y:y+(symbol==='none'?3:14)+(i-(lines.length-1)/2)*9,fill:ink,class:'tile-label'},line)));
    if($('numbers').checked)g.append(node('text',{x:x-23,y:y-28,class:'tile-number'},tile.index));
    svg.append(g);
  }
}
function scheduleDraw(){if(drawQueued)return;drawQueued=true;requestAnimationFrame(()=>{drawQueued=false;renderBoard();});}
function validate(board) {
  const errors=[];if(!board||typeof board!=='object'||Array.isArray(board))return ['The board must be a JSON object.'];
  if(board.version!==2)errors.push('The board file must use version 2.');
  if(typeof board.id!=='string'||!board.id.length||board.id.length>100)errors.push('The board needs an ID of 1–100 characters.');
  if(!Array.isArray(board.tiles)||board.tiles.length!==120)return [...errors,'The game needs exactly 120 tiles.'];
  if(board.startIndex!==0||board.finishIndex!==119)errors.push('START must be tile 0 and FINISH must be tile 119.');
  board.tiles.forEach((tile,i)=>{
    if(!tile||typeof tile!=='object'||Array.isArray(tile)){errors.push(`Tile ${i}: invalid tile.`);return;}
    const issue=message=>errors.push(`Tile ${i}: ${message}`);
    if(tile.index!==i)issue('route indices must stay in order.');
    const knownType=typeof tile.type==='string'&&Object.prototype.hasOwnProperty.call(effects,tile.type);
    if(!knownType)issue('unknown effect.');
    if((i===0&&tile.type!=='start')||(i===119&&tile.type!=='finish')||(i>0&&i<119&&['start','finish'].includes(tile.type)))issue('START and FINISH are locked.');
    if(typeof (tile.label??'')!=='string'||(tile.label||'').length>80)issue('label must be at most 80 characters.');
    for(const axis of ['x','y'])if(typeof tile[axis]!=='number'||!Number.isFinite(tile[axis])||tile[axis]<0||tile[axis]>1)issue(`${axis.toUpperCase()} must be between 0% and 100%.`);
    if(!Number.isInteger(tile.amount??0)||(tile.amount??0)<0||(tile.amount??0)>1000000)issue('amount must be a whole number from 0 to 1000000.');
    if(['setBack','moveForward'].includes(tile.type)&&tile.amount<1)issue('movement needs at least one space.');
    if(tile.destination!=null&&(!Number.isInteger(tile.destination)||tile.destination<0||tile.destination>=120))issue('invalid destination.');
    if(tile.mineColor!=null&&!['red','blue','green'].includes(tile.mineColor))issue('invalid mine color.');
    const required=tile.type==='mine'&&tile.mineColor&&tile.mineColor!=='red'?'hospital':knownType?targetTypes[tile.type]:null;if(required&&(!Number.isInteger(tile.destination)||board.tiles[tile.destination]?.type!==required))issue(`choose a ${required.toUpperCase()} destination.`);
    if(tile.type==='police'&&!board.tiles.some(t=>t?.type==='jail'))issue('police needs a JAIL on the board.');
    if(tile.artwork!=null&&!artwork.includes(tile.artwork))issue('unknown illustration.');
    if(tile.consumesAntidote!=null&&typeof tile.consumesAntidote!=='boolean')issue('invalid antidote setting.');
    for(const key of ['fillColor','textColor'])if(tile[key]!=null&&(!Number.isInteger(tile[key])||tile[key]<0||tile[key]>0xffffffff))issue('invalid color.');
    for(const key of ['width','height'])if(tile[key]!=null&&(typeof tile[key]!=='number'||!Number.isFinite(tile[key])||tile[key]<.02||tile[key]>.2))issue('invalid legacy dimensions.');
  });return errors;
}
function remember(before){past.push(before);if(past.length>80)past.shift();future=[];}
function persist(){try{localStorage.setItem(storageKey,JSON.stringify({board:state,baseDigest,savedState}));}catch{/* The editor still works when local storage is unavailable. */}}
function refresh(){
  renderBoard();renderForm();const errors=validate(state);$('validation-heading').textContent=errors.length?`${errors.length} ${errors.length===1?'issue':'issues'} to fix`:'Ready to save';
  $('validation-heading').parentElement.classList.toggle('invalid',!!errors.length);$('issues').replaceChildren();
  for(const text of errors.slice(0,12)){const li=document.createElement('li'),b=document.createElement('button');b.textContent=text;b.type='button';b.addEventListener('click',()=>{const m=text.match(/^Tile (\d+):/);if(m)selectTile(Number(m[1]));});li.append(b);$('issues').append(li);}
  $('validation-note').hidden=!!errors.length;$('undo').disabled=!past.length||busy;$('redo').disabled=!future.length||busy;
  $('save').disabled=busy||!!errors.length||!dirty();$('download').disabled=busy||!!errors.length;
  $('open').disabled=busy;$('reload').disabled=busy;document.querySelector('main').inert=busy;
  $('jump').value=selected;$('previous').disabled=selected===0;$('next').disabled=selected===119;
  setStatus(dirty()?'Unsaved edits · Nothing changes in the game until you save.':'Current game board · All changes saved.');persist();
}
function renderForm(){
  const t=state.tiles[selected];formPending=false;$('apply').classList.remove('pending');$('tile-heading').textContent=`Tile ${selected}`;$('type-pill').textContent=effects[t.type]?.[0]||t.type;
  $('effect').replaceChildren();for(const [value,[name]] of Object.entries(effects)){if(selected>0&&selected<119&&['start','finish'].includes(value))continue;if((selected===0||selected===119)&&value!==t.type)continue;const o=new Option(name,value);$('effect').append(o);}
  $('effect').value=t.type;$('effect').disabled=selected===0||selected===119;
  $('mine-color').value=t.mineColor||'red';
  $('label').value=t.label||'';$('amount').value=t.amount??0;$('antidote').checked=!!t.consumesAntidote;
  $('x').value=Number((t.x*100).toFixed(4));$('y').value=Number((t.y*100).toFixed(4));$('artwork').value=t.artwork??'';
  $('auto-fill').checked=t.fillColor==null;$('auto-ink').checked=t.textColor==null;
  $('fill').value=t.fillColor==null?palette(t)[0]:color(t.fillColor);$('ink').value=t.textColor==null?palette(t)[1]:color(t.textColor);
  $('fill').disabled=$('auto-fill').checked;$('ink').disabled=$('auto-ink').checked;
  updateEffectFields(false);
}
function updateEffectFields(changed){
  const kind=$('effect').value,t=state.tiles[selected];$('effect-hint').textContent=effects[kind]?.[1]||'';
  $('amount-row').hidden=!amountTypes.has(kind);$('antidote-row').hidden=kind!=='snake';
  const minimum=['boat','antidote','rawMeat','jail','setBack','moveForward','star'].includes(kind)?1:0;
  $('amount').min=minimum;if(Number($('amount').value)<minimum)$('amount').value=minimum;
  $('mine-color-row').hidden=kind!=='mine';
  const required=kind==='mine'&&$('mine-color').value!=='red'?'hospital':targetTypes[kind];$('destination-row').hidden=!required;$('destination').replaceChildren();
  for(const target of state.tiles)if(target.type===required&&target.index!==selected)$('destination').append(new Option(`${target.index} · ${target.label||effects[target.type][0]}`,String(target.index)));
  if(required){if([...$('destination').options].some(o=>Number(o.value)===t.destination))$('destination').value=String(t.destination);else if($('destination').options.length)$('destination').selectedIndex=0;else $('destination').append(new Option(`Add a ${required} tile first`,''));}
  if(changed){$('label').value=kind==='normal'?'':effects[kind][0].toUpperCase();$('amount').value=({cash:10,fine:20,police:20,setBack:3,moveForward:2,jail:1,boat:1,antidote:1,rawMeat:1,star:1})[kind]??0;$('artwork').value='';$('antidote').checked=kind==='snake';markForm();}
}
function markForm(){if(busy||!state)return;formPending=true;$('apply').classList.add('pending');$('save').disabled=busy;setStatus('Tile edits pending · Apply tile changes, or save to apply them.');}
function commitForm(quiet=false){
  if(busy)return false;
  if(!state||!formPending)return true;
  if(!$('tile-form').reportValidity())return false;
  const before=copy(state),tile=state.tiles[selected],kind=$('effect').value;
  tile.type=kind;tile.label=$('label').value.trim();tile.amount=amountTypes.has(kind)?Number($('amount').value):0;
  tile.mineColor=kind==='mine'?$('mine-color').value:undefined;
  const needsTarget=targetTypes[kind]||(kind==='mine'&&tile.mineColor!=='red');
  tile.destination=needsTarget&&$('destination').value!==''?Number($('destination').value):null;
  tile.consumesAntidote=kind==='snake'&&$('antidote').checked;tile.artwork=$('artwork').value||null;
  tile.x=Number($('x').value)/100;tile.y=Number($('y').value)/100;
  tile.fillColor=$('auto-fill').checked?null:parseInt('ff'+$('fill').value.slice(1),16);
  tile.textColor=$('auto-ink').checked?null:parseInt('ff'+$('ink').value.slice(1),16);
  if(JSON.stringify(before)!==JSON.stringify(state))remember(before);refresh();if(!quiet)toast(`Tile ${selected} updated`);return true;
}
function selectTile(index){if(!state||!Number.isInteger(index)||index<0||index>119)return;if(!commitForm(true))return;selected=index;refresh();}
function mutate(action){if(!state||busy||!commitForm(true))return;const before=copy(state);action(state);if(JSON.stringify(before)!==JSON.stringify(state))remember(before);refresh();}
async function request(path, body){const res=await fetch(path,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json','X-Editor-Token':token}:{},body:body?JSON.stringify(body):undefined});const data=await res.json();if(!res.ok)throw new Error(data.error||'Could not complete the request.');return data;}
async function load(initial=false){
  if(busy)return;
  if(!initial&&dirty()&&!confirm('Discard unsaved edits and reload the game board?'))return;
  try{const data=await request('/api/board');state=data.board;baseDigest=data.digest;savedState=JSON.stringify(state);past=[];future=[];selected=0;
    if(initial){try{const draft=JSON.parse(localStorage.getItem(storageKey));if(draft?.baseDigest===baseDigest&&draft.board&&JSON.stringify(draft.board)!==savedState&&Array.isArray(draft.board.tiles)&&draft.board.tiles.length===120){state=draft.board;toast('Restored your unsaved edits');}}catch{}}
    refresh();$('loading').hidden=true;
  }catch(error){$('loading').textContent='Could not open the game board.';setStatus(error.message);toast(error.message,true);}
}
async function save(download=false){
  if(busy||!commitForm(true))return;const errors=validate(state);if(errors.length){toast(errors[0],true);return;}
  busy=true;refresh();try{
    const data=await request(download?'/api/export':'/api/save',{board:state,expectedDigest:baseDigest});
    if(download){const blob=new Blob([JSON.stringify(data.board,null,2)+'\n'],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='spiral_board_map.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);toast('Board JSON downloaded');}
    else{state=data.board;baseDigest=data.digest;savedState=JSON.stringify(state);toast('Saved to game source. A backup was created.');setStatus(`Saved · Backup: ${data.backup}`);}
  }catch(error){toast(error.message,true);setStatus(error.message);}finally{busy=false;refresh();}
}
function fit(){view={x:0,y:0,w:1000,h:1000};renderBoard();}
function zoom(factor,at={x:view.x+view.w/2,y:view.y+view.h/2}){const next=Math.max(150,Math.min(1500,view.w*factor)),ratio=next/view.w;view={x:at.x-(at.x-view.x)*ratio,y:at.y-(at.y-view.y)*ratio,w:next,h:next};renderBoard();}
function point(event){const rect=$('board').getBoundingClientRect(),scale=Math.min(rect.width/view.w,rect.height/view.h);return {x:view.x+(event.clientX-rect.left-(rect.width-view.w*scale)/2)/scale,y:view.y+(event.clientY-rect.top-(rect.height-view.h*scale)/2)/scale};}
function snap(value){return $('snap').checked ? .066+Math.max(0,Math.min(14,Math.round((value-.066)/.062)))*.062:Math.max(.025,Math.min(.975,value));}

$('tile-form').addEventListener('submit',event=>{event.preventDefault();commitForm();});
$('tile-form').addEventListener('input',event=>{if(event.target.id==='auto-fill')$('fill').disabled=event.target.checked;if(event.target.id==='auto-ink')$('ink').disabled=event.target.checked;markForm();});
$('mine-color').addEventListener('change',()=>{updateEffectFields(false);markForm();});
$('effect').addEventListener('change',()=>updateEffectFields(true));
for(const id of ['destination','artwork'])$(id).addEventListener('change',markForm);
$('previous').addEventListener('click',()=>selectTile(selected-1));$('next').addEventListener('click',()=>selectTile(selected+1));$('go').addEventListener('click',()=>selectTile(Number($('jump').value)));$('jump').addEventListener('keydown',event=>{if(event.key==='Enter')selectTile(Number($('jump').value));});
$('swap').addEventListener('click',()=>{const target=Number($('swap-target').value);if(!$('swap-target').value||!Number.isInteger(target)||target<1||target>118||selected===0||selected===119||target===selected){toast('Choose two different tiles between 1 and 118.',true);return;}mutate(board=>{const a=copy(board.tiles[selected]),b=copy(board.tiles[target]);for(const key of contents){if(key in b)board.tiles[selected][key]=b[key];else delete board.tiles[selected][key];if(key in a)board.tiles[target][key]=a[key];else delete board.tiles[target][key];}});toast(`Swapped tiles ${selected} and ${target}`);});
$('undo').addEventListener('click',()=>{if(formPending){renderForm();refresh();return;}if(!past.length)return;future.push(copy(state));state=past.pop();refresh();});
$('redo').addEventListener('click',()=>{if(!future.length)return;past.push(copy(state));state=future.pop();refresh();});
$('save').addEventListener('click',()=>save(false));$('download').addEventListener('click',()=>save(true));$('reload').addEventListener('click',()=>load(false));
$('open').addEventListener('click',()=>$('file').click());$('file').addEventListener('change',async()=>{const file=$('file').files[0];if(!file)return;try{if(file.size>1000000)throw new Error('Board files must be smaller than 1 MB.');const imported=JSON.parse(await file.text()),errors=validate(imported);if(errors.length)throw new Error(errors[0]);if(dirty()&&!confirm('Replace unsaved edits with this JSON file?'))return;remember(copy(state));state=imported;selected=0;refresh();toast('Imported a board copy. Save to game when ready.');}catch(error){toast(error.message,true);}finally{$('file').value='';}});
$('fit').addEventListener('click',fit);$('zoomin').addEventListener('click',()=>zoom(.8));$('zoomout').addEventListener('click',()=>zoom(1.25));
for(const id of ['numbers','route'])$(id).addEventListener('change',renderBoard);$('move').addEventListener('change',()=>$('canvas').classList.toggle('moving',$('move').checked));
$('restore-layout').addEventListener('click',()=>mutate(board=>{const points=[{x:0,y:0,leg:0}],directions=[[0,1],[1,0],[0,-1],[-1,0]],lengths=[14,14,14,12,12,10,10,8,8,6,6,4,4,2,2];let x=0,y=0;lengths.forEach((length,leg)=>{const [dx,dy]=directions[leg%4];for(let n=0;n<length;n++){x+=dx;y+=dy;points.push({x,y,leg});}});board.tiles.forEach((tile,i)=>{tile.x=Number((.066+points[i].x*.062).toFixed(6));tile.y=Number((.066+points[i].y*.062).toFixed(6));tile.segment=`spiral-leg-${points[i].leg}`;tile.width=.05;tile.height=.05;});}));
$('board').addEventListener('wheel',event=>{event.preventDefault();zoom(event.deltaY>0?1.12:1/1.12,point(event));},{passive:false});
$('board').addEventListener('pointerdown',event=>{if(event.button!==0||!state)return;if(!commitForm(true))return;const target=event.target.closest('[data-tile]'),index=target?Number(target.getAttribute('data-tile')):null;drag={start:point(event),screenX:event.clientX,screenY:event.clientY,view:{...view},tile:$('move').checked?index:null,index,moved:false,before:copy(state)};$('board').setPointerCapture?.(event.pointerId);});
$('board').addEventListener('pointermove',event=>{if(!drag)return;const moved=Math.hypot(event.clientX-drag.screenX,event.clientY-drag.screenY)>3;if(!moved&&!drag.moved)return;drag.moved=true;if(drag.tile!=null){const here=point(event),original=drag.before.tiles[drag.tile];state.tiles[drag.tile].x=Number(snap(original.x+(here.x-drag.start.x)/1000).toFixed(6));state.tiles[drag.tile].y=Number(snap(original.y+(here.y-drag.start.y)/1000).toFixed(6));selected=drag.tile;}else{const rect=$('board').getBoundingClientRect(),scale=Math.min(rect.width/drag.view.w,rect.height/drag.view.h);view.x=drag.view.x-(event.clientX-drag.screenX)/scale;view.y=drag.view.y-(event.clientY-drag.screenY)/scale;}scheduleDraw();});
function finishDrag(){if(!drag)return;const done=drag;drag=null;if(done.moved&&done.tile!=null){remember(done.before);refresh();}else if(!done.moved&&done.index!=null)selectTile(done.index);}
$('board').addEventListener('pointerup',finishDrag);$('board').addEventListener('pointercancel',finishDrag);
$('board').addEventListener('keydown',event=>{const target=event.target.closest('[data-tile]');if(target&&['Enter',' '].includes(event.key)){event.preventDefault();selectTile(Number(target.getAttribute('data-tile')));}});
document.addEventListener('keydown',event=>{if(!event.metaKey&&!event.ctrlKey)return;const typing=['INPUT','SELECT','TEXTAREA'].includes(event.target.tagName);if(event.key.toLowerCase()==='s'){event.preventDefault();save(false);}else if(event.key.toLowerCase()==='z'&&!typing){event.preventDefault();$(event.shiftKey?'redo':'undo').click();}});
window.addEventListener('beforeunload',event=>{if(dirty()){event.preventDefault();event.returnValue='';}});
$('artwork').append(new Option('Use game default',''));for(const item of artwork)$('artwork').append(new Option(item.replace(/([a-z])([A-Z])/g,'$1 $2'),item));
load(true);
})();
