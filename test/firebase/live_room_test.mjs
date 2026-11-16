import fs from 'node:fs';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {initializeAuth,inMemoryPersistence,signInAnonymously,deleteUser} from 'firebase/auth';
import {getFirestore,doc,setDoc,getDoc,updateDoc,deleteDoc,collection,getDocs,serverTimestamp,Timestamp,runTransaction,terminate,setLogLevel} from 'firebase/firestore';
setLogLevel('silent');
const config=JSON.parse(fs.readFileSync(process.env.FIREBASE_CLIENT_CONFIG,'utf8'));
const options={apiKey:config.FIREBASE_API_KEY,appId:config.FIREBASE_APP_ID,messagingSenderId:config.FIREBASE_MESSAGING_SENDER_ID,projectId:'spiral-survival-c4ff0'};
const players=[];const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const code='TEST'+Array.from({length:4},()=>alphabet[Math.floor(Math.random()*alphabet.length)]).join('');
const room=p=>doc(p.db,'rooms',code);
let created=false;let passed=0;
const check=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
async function join(p){for(let retry=0;retry<5;retry++){try{return await runTransaction(p.db,async tx=>{const ref=room(p);const snapshot=await tx.get(ref);const data=snapshot.data();tx.update(ref,{members:{...data.members,[p.uid]:p.name},playerOrder:[...data.playerOrder,p.uid]});});}catch(e){if(e.code!=='permission-denied'||retry===4)throw e;await new Promise(resolve=>setTimeout(resolve,80*(retry+1)));}}}
try{
 for(let i=0;i<6;i++){
  const app=initializeApp(options,'live-room-qa-'+i+'-'+Date.now());
  const auth=initializeAuth(app,{persistence:inMemoryPersistence});
  const p={app,auth,db:getFirestore(app),name:'QA Player '+(i+1)};players.push(p);
  p.uid=(await signInAnonymously(auth)).user.uid;
 }
 const host=players[0];
 await check('anonymous authentication succeeds for six isolated clients',async()=>assert.equal(new Set(players.map(p=>p.uid)).size,6));
 await check('host creates a private waiting room',async()=>{
  await setDoc(room(host),{hostId:host.uid,members:{[host.uid]:host.name},playerOrder:[host.uid],status:'waiting',revision:0,
   boardId:'spiral-quest-board-v4',state:'',outcome:'',activeUid:'',lastRequestId:'',lastError:'',hostSeen:serverTimestamp(),createdAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+3600000)});
  created=true;
 });
 await check('four concurrent joins produce exactly five seats',async()=>{
  await Promise.all(players.slice(1,5).map(join));
  assert.equal(Object.keys((await getDoc(room(host))).data().members).length,5);
 });
 await check('live server rejects a sixth player',async()=>{
  await assert.rejects(join(players[5]),e=>e.code==='permission-denied');
  assert.equal(Object.keys((await getDoc(room(host))).data().members).length,5);
 });
 await check('guest cannot replace shared game state',()=>assert.rejects(updateDoc(room(players[1]),{state:'unauthorized'}),e=>e.code==='permission-denied'));
 await check('host starts the five-seat match',async()=>{
  const current=(await getDoc(room(host))).data();
  const state={schemaVersion:3,boardId:current.boardId,players:current.playerOrder.map((id,i)=>({id:'p'+(i+1),name:current.members[id],colorValue:0xFF599ED1,position:0,cash:10})),currentPlayerIndex:0,round:1,phase:'ready',message:'Live QA ready',eventDrawPile:[],eventDiscardPile:[]};
  await updateDoc(room(host),{status:'playing',state:JSON.stringify(state),revision:1,activeUid:host.uid,hostSeen:serverTimestamp()});
 });
 const request={requestId:'qa-committed-request',action:'roll',args:{},expectedRevision:1,createdAt:serverTimestamp()};
 await check('out-of-turn guest commands are rejected',()=>assert.rejects(setDoc(doc(players[1].db,'rooms',code,'requests',players[1].uid),request),e=>e.code==='permission-denied'));
 await check('current player can submit a command',()=>setDoc(doc(host.db,'rooms',code,'requests',host.uid),request));
 await check('host atomically commits the revision and acknowledges the command',async()=>{
  const command=doc(host.db,'rooms',code,'requests',host.uid);
  await runTransaction(host.db,async tx=>{
   const pending=await tx.get(command);const current=await tx.get(room(host));
   assert.equal(pending.data().expectedRevision,current.data().revision);
   const next=JSON.parse(current.data().state);next.players[0].position=1;next.currentPlayerIndex=1;next.lastDice=1;
   tx.update(room(host),{state:JSON.stringify(next),revision:2,activeUid:current.data().playerOrder[1],lastRequestId:pending.data().requestId,lastError:'',hostSeen:serverTimestamp()});tx.delete(command);
  });
 });
 await check('all five clients observe the same committed turn',async()=>{
  const snapshots=await Promise.all(players.slice(0,5).map(p=>getDoc(room(p))));
  assert.equal(new Set(snapshots.map(s=>s.data().state)).size,1);
  for(const snapshot of snapshots){assert.equal(snapshot.data().revision,2);assert.equal(JSON.parse(snapshot.data().state).players[0].position,1);}
 });
 await check('stale request revisions are rejected',()=>assert.rejects(setDoc(doc(players[1].db,'rooms',code,'requests',players[1].uid),request),e=>e.code==='permission-denied'));
 console.log(JSON.stringify({liveSecurityChecksPassed:passed,maximumRoomPlayers:5,sixthPlayerRejected:true}));
}finally{
 if(created && players[0]?.auth.currentUser){
  const pending=await getDocs(collection(players[0].db,'rooms',code,'requests'));
  await Promise.all(pending.docs.map(d=>deleteDoc(d.ref)));
  await deleteDoc(room(players[0]));
 }
 let removed=0;
 for(const p of players){if(p.auth.currentUser){await deleteUser(p.auth.currentUser);removed++;}await terminate(p.db);await deleteApp(p.app);}
 console.log(JSON.stringify({temporaryRoomRemoved:created,temporaryAuthUsersRemoved:removed}));
}
