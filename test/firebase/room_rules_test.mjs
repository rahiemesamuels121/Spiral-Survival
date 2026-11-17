import fs from 'node:fs';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, getDocs, collection, updateDoc, serverTimestamp, Timestamp, runTransaction} from 'firebase/firestore';
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run security tests with Firebase emulators:exec.');
const projectId='demo-spiral-survival';
const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(process.env.ROOM_RULES ?? new URL('../../firestore.rules', import.meta.url),'utf8')}});
const databases=new Map();
const db=id=>{if(!databases.has(id)) databases.set(id,env.authenticatedContext(id).firestore());return databases.get(id);};
const code='ABCDEFGH';
const roomRef=id=>doc(db(id),'rooms',code);
const createData=()=>({hostId:'host',members:{host:'Host'},avatars:{host:'paw'},playerOrder:['host'],status:'waiting',revision:0,
 boardId:'reference',state:'',outcome:'',activeUid:'',lastRequestId:'',lastError:'',
 hostSeen:serverTimestamp(),createdAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+86400000)});
let passed=0;
async function check(name,body){await body();passed++;console.log('PASS',name);}
async function join(id){
 for(let attempt=0;attempt<5;attempt++){
  try{
   const ref=roomRef(id);
   return await runTransaction(db(id),async tx=>{
    const snapshot=await tx.get(ref);const data=snapshot.data();
    tx.update(ref,{members:{...data.members,[id]:id},avatars:{...data.avatars,[id]:'paw'},playerOrder:[...data.playerOrder,id]});
   });
  }catch(error){if(error.code!=='permission-denied'||attempt===4)throw error;await new Promise(resolve=>setTimeout(resolve,40*(attempt+1)));}
 }
}

try {
 await check('unauthenticated rooms are denied',()=>assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'rooms',code))));
 await check('host creates a room',()=>assertSucceeds(setDoc(roomRef('host'),createData())));
 await check('room directory cannot be listed',()=>assertFails(getDocs(collection(db('guest'),'rooms'))));
 await check('forged host identity denied',()=>assertFails(setDoc(doc(db('guest'),'rooms','ABCDEFGJ'),createData())));
 await check('joining cannot rewrite another name',()=>assertFails(updateDoc(roomRef('guest'),{members:{host:'Changed',guest:'Guest'},playerOrder:['host','guest']})));
 await check('four concurrent joins fill exactly five seats',async()=>{
  await Promise.all(['one','two','three','four'].map(id=>join(id)));
  assert.equal(Object.keys((await getDoc(roomRef('host'))).data().members).length,5);
 });
 await check('sixth player is rejected',()=>assertFails(join('six')));
 await check('member cannot change game state',()=>assertFails(updateDoc(roomRef('one'),{state:'cheat'})));
 await check('member cannot transfer hosting',()=>assertFails(updateDoc(roomRef('one'),{hostId:'one'})));
 await check('non-host can leave the waiting room',async()=>{
  const data=(await getDoc(roomRef('four'))).data();delete data.members.four;delete data.avatars.four;
  await assertSucceeds(updateDoc(roomRef('four'),{members:data.members,avatars:data.avatars,playerOrder:data.playerOrder.filter(x=>x!=='four')}));
 });
 await check('fifth seat can be filled again',()=>assertSucceeds(join('four')));
 await check('member can choose a class while waiting',()=>assertSucceeds(updateDoc(roomRef('two'),{'avatars.two':'secretAgent'})));
 await check('member cannot change another class',()=>assertFails(updateDoc(roomRef('two'),{'avatars.one':'swimmer'})));
 await check('host cannot change another class in lobby',()=>assertFails(updateDoc(roomRef('host'),{'avatars.one':'swimmer'})));
 await check('legacy cosmetic options cannot be selected',()=>assertFails(updateDoc(roomRef('two'),{'avatars.two':'rocket'})));
 await check('avatar cannot be removed from a seated player',()=>assertFails(updateDoc(roomRef('two'),{avatars:{host:'paw',one:'paw',three:'paw',four:'paw'}})));
 await check('host starts the game with frozen seats',()=>assertSucceeds(updateDoc(roomRef('host'),{status:'playing',state:'{"players":[]}',activeUid:'one',revision:1,hostSeen:serverTimestamp()})));
 await check('classes lock for members when room starts',()=>assertFails(updateDoc(roomRef('two'),{'avatars.two':'swimmer'})));
 await check('classes lock for the host when room starts',()=>assertFails(updateDoc(roomRef('host'),{'avatars.host':'swimmer'})));
 await check('no late join after start',()=>assertFails(join('late')));
 await check('members cannot leave and change seat order mid-match',()=>assertFails(updateDoc(roomRef('one'),{members:{host:'Host'},playerOrder:['host']})));
 const request=()=>({requestId:'test-request',action:'roll',args:{},expectedRevision:1,createdAt:serverTimestamp()});
 await check('out-of-turn requests are denied',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),request())));
 await check('forged request UID is denied',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','one'),request())));
 await check('guest cannot provide dice or replacement state',()=>assertFails(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),args:{dice:6,state:'win'}})));
 await check('stale command revisions are denied',()=>assertFails(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),expectedRevision:0})));
 await check('valid turn-owner command is accepted',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),request())));
 await check('turn-owner hospital purchase is accepted',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'medicalBuy',args:{item:'healthPack'}})));
 await check('turn-owner antidote purchase is accepted',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'medicalBuy',args:{item:'antidote'}})));
 await check('turn-owner health pack treatment is accepted',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'healthPack'})));
 await check('out-of-turn medical purchases are denied',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),{...request(),action:'medicalBuy',args:{item:'antidote'}})));
 await check('medical purchases cannot supply their own price',()=>assertFails(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'medicalBuy',args:{item:'healthPack',price:0}})));
 await check('out-of-turn character changes are rejected',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),{...request(),action:'playerIcon',args:{icon:'rocket'}})));
 await check('icon changes cannot target another player',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),{...request(),action:'playerIcon',args:{icon:'star',target:'one'}})));
 await check('unknown icon names are rejected',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),{...request(),action:'playerIcon',args:{icon:'unknown'}})));
 await check('icon changes cannot forge another UID',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','one'),{...request(),action:'playerIcon',args:{icon:'star'}})));
 await check('guest cannot inspect other requests',()=>assertFails(getDocs(collection(db('two'),'rooms',code,'requests'))));
 await check('host can receive the request stream',()=>assertSucceeds(getDocs(collection(db('host'),'rooms',code,'requests'))));
 const authority=id=>doc(db(id),'rooms',code,'authority','state');
 const privateRef=(id,owner=id)=>doc(db(id),'rooms',code,'private',owner);
 await check('host stores authoritative contracts',()=>assertSucceeds(setDoc(authority('host'),{state:'private contract'})));
 await check('guest cannot read authority',()=>assertFails(getDoc(authority('one'))));
 await check('guest cannot write authority',()=>assertFails(setDoc(authority('one'),{state:'forged'})));
 await check('host can read authority',()=>assertSucceeds(getDoc(authority('host'))));
 await check('host writes a private contract view',()=>assertSucceeds(setDoc(privateRef('host','one'),{revision:1,hitmanOwnerId:'p2',hitmanTile:30})));
 await check('hirer can read own contract',()=>assertSucceeds(getDoc(privateRef('one'))));
 await check('opponent cannot read another contract',()=>assertFails(getDoc(privateRef('two','one'))));
 await check('outsider cannot read private view',()=>assertFails(getDoc(privateRef('outsider','one'))));
 await check('private views cannot be listed',()=>assertFails(getDocs(collection(db('one'),'rooms',code,'private'))));
 await check('hirer cannot forge a contract',()=>assertFails(setDoc(privateRef('one'),{hitmanTile:45})));
 await check('turn-owner can request a hire',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'hitmanHire',args:{tile:30}})));
 await check('turn-owner can request an attack',()=>assertSucceeds(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'hitmanAttack',args:{target:2}})));
 await check('opponent cannot hire outside their turn',()=>assertFails(setDoc(doc(db('two'),'rooms',code,'requests','two'),{...request(),action:'hitmanHire',args:{tile:30}})));
 await check('opponent cannot read hitman hire requests',()=>assertFails(getDoc(doc(db('two'),'rooms',code,'requests','one'))));
 await check('hire request cannot supply its own price',()=>assertFails(setDoc(doc(db('one'),'rooms',code,'requests','one'),{...request(),action:'hitmanHire',args:{tile:30,price:0}})));
 await check('host closes a room',()=>assertSucceeds(updateDoc(roomRef('host'),{status:'closed',hostSeen:serverTimestamp()})));
 await check('closed-room commands are denied',()=>assertFails(setDoc(doc(db('one'),'rooms',code,'requests','one'),request())));
 await check('closed-room reopening is denied',()=>assertFails(updateDoc(roomRef('host'),{status:'waiting',hostSeen:serverTimestamp()})));
 console.log(`${passed} security checks passed`);
}finally{await env.cleanup();}
