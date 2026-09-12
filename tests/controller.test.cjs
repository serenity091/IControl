// Exercise the production controller script with controlled browser event failures.
// The fixture deliberately drops selected browser events; it is not a DOM renderer.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

function controller() {
  class Element {
    constructor(id='') {
      this.id=id; this.handlers=new Map(); this.children=[]; this.dataset={};
      this.capture=new Set(); this.style={setProperty(k,v){this[k]=v;}};
      this.className=''; this.value=''; this.clientWidth=844; this.clientHeight=328;
      this.classList={contains:c=>this.className.split(' ').includes(c),
        add:c=>{if(!this.classList.contains(c))this.className+=' '+c;},
        remove:c=>{this.className=this.className.split(' ').filter(v=>v!==c).join(' ');},
        toggle:(c,on)=>on?this.classList.add(c):this.classList.remove(c)};
    }
    addEventListener(name,fn){if(!this.handlers.has(name))this.handlers.set(name,[]);this.handlers.get(name).push(fn);}
    emit(name,event={}){event.type=name;event.target??=this;event.preventDefault??=()=>{};for(const fn of this.handlers.get(name)||[])fn(event);}
    append(child){child.parent=this;this.children.push(child);}
    setAttribute(){}
    getBoundingClientRect(){return {left:100,top:100,width:100,height:100};}
    querySelector(){return this.children.find(c=>c.className==='stick-thumb')||null;}
    closest(){return this.dataset.control?this:this.parent?.closest();}
    setPointerCapture(id){if(this.failCapture)throw new Error('Capture failed');this.capture.add(id);}
    hasPointerCapture(id){return this.capture.has(id);}
    releasePointerCapture(id){this.capture.delete(id);this.emit('lostpointercapture',{pointerId:id});}
  }
  const nodes=new Map();
  const get=id=>{if(!nodes.has(id))nodes.set(id,new Element(id));return nodes.get(id);};
  const doc=new Element();doc.getElementById=get;doc.createElement=()=>new Element();
  doc.documentElement=new Element();doc.body=new Element();doc.hidden=false;
  const win=new Element(), intervals=[], sockets=[];let now=1, resize;
  class Socket {
    static OPEN=1;static CLOSING=2;
    constructor(){this.readyState=0;this.bufferedAmount=0;this.sent=[];sockets.push(this);}
    send(value){this.sent.push(JSON.parse(value));}
    close(){this.readyState=2;} // A close handshake can stall; don't auto-fire onclose.
    open(){this.readyState=1;this.onopen();this.message({type:'joined',player:1,mode:'live',epoch:0});}
    message(data){this.onmessage({data:JSON.stringify(data)});}
  }
  const storage={getItem:()=>null,setItem:()=>{}};
  const context=vm.createContext({document:doc,window:win,location:{hash:'#key=secret',pathname:'/play',protocol:'http:',host:'localhost:8080'},
    URLSearchParams,history:{replaceState(){}},localStorage:storage,sessionStorage:storage,
    crypto:{getRandomValues:arr=>arr.fill(1)},Uint8Array,performance:{now:()=>now},navigator:{},screen:{},
    matchMedia:()=>({matches:false}),setInterval:(fn,ms)=>intervals.push({fn,ms}),setTimeout:()=>1,clearTimeout(){},
    ResizeObserver:class{constructor(cb){resize=cb;}observe(){}},WebSocket:Socket});
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../static/controller.js'),'utf8'),context);
  get('join-form').onsubmit({preventDefault(){}});sockets[0].open();
  const el=id=>get('controller').children.find(c=>c.dataset.control===id);
  const pointer=(id=1,type='touch',x=180,y=150)=>({pointerId:id,pointerType:type,button:0,buttons:1,clientX:x,clientY:y});
  return {doc,win,el,get,sockets,context,
    press:(control,id=1,type='touch')=>el(control).emit('pointerdown',pointer(id,type)),
    pointer,
    tick:(gap=34)=>{now+=gap;for(const i of intervals)if(i.ms<100)i.fn();},
    input:()=>sockets.at(-1).sent.filter(m=>m.type==='input').at(-1).state,
    state:()=>JSON.parse(vm.runInContext('JSON.stringify(state())',context)),
    resize:()=>{get('controller').clientWidth-=30;resize();},
    touch:(kind,live,changed=live)=>doc.emit(kind,{touches:live,changedTouches:changed}),
    contact:(control,identifier)=>({identifier,target:el(control),clientX:180,clientY:150}),
  };
}

test('release outside the control resets stick and visual even if element misses pointerup',()=>{
  const h=controller();h.press('LS');assert.ok(h.input().lx>0);
  h.win.emit('pointerup',h.pointer());
  assert.equal(h.input().lx,0);assert.equal(h.el('LS').querySelector().style.transform,'');
});
test('native touchend recovers a missed pointerup without releasing another finger',()=>{
  const h=controller();h.press('LS',1);const stick=h.contact('LS',10);h.touch('touchstart',[stick]);
  h.press('A',2);const button=h.contact('A',20);h.touch('touchstart',[stick,button],[button]);
  h.touch('touchend',[button],[stick]);
  assert.equal(h.input().lx,0);assert.deepEqual(h.input().buttons,['A']);
  h.touch('touchend',[],[button]);assert.deepEqual(h.input().buttons,[]);
});
test('native touchcancel releases the last contact if pointercancel is lost',()=>{
  const h=controller();h.press('RS');const contact=h.contact('RS',10);h.touch('touchstart',[contact]);
  h.touch('touchcancel',[],[contact]);assert.equal(h.input().rx,0);
});
test('touchmove reconciliation does not bypass the 30 Hz input throttle',()=>{
  const h=controller();h.press('LS');const contact=h.contact('LS',10);h.touch('touchstart',[contact]);
  const before=h.sockets[0].sent.length;
  for(let i=0;i<240;i++){
    h.win.emit('pointermove',{...h.pointer(),clientX:160+i%10});
    h.touch('touchmove',[contact]);
  }
  assert.equal(h.sockets[0].sent.length,before);h.tick();assert.equal(h.sockets[0].sent.length,before+1);
});
test('missing lostpointercapture is recovered by checking capture ownership',()=>{
  const h=controller();h.press('LS');h.el('LS').capture.clear();h.tick();assert.equal(h.input().lx,0);
});
test('capture failure uses global release handlers instead of throwing',()=>{
  const h=controller();h.el('LS').failCapture=true;assert.doesNotThrow(()=>h.press('LS'));
  h.win.emit('pointerup',h.pointer());assert.equal(h.input().lx,0);
});
test('mouse movement with no held button clears a missed release',()=>{
  const h=controller();h.press('LS',1,'mouse');h.win.emit('pointermove',{...h.pointer(1,'mouse'),buttons:0});
  assert.equal(h.input().lx,0);
});
test('stationary hold remains active for a minute while normal heartbeats run',()=>{
  const h=controller();h.press('LS');for(let i=0;i<1800;i++)h.tick();assert.ok(h.input().lx>0);
});
test('browser suspension clears old touches before the next heartbeat',()=>{
  const h=controller();h.press('LS');h.tick(1500);assert.equal(h.input().lx,0);
});
test('backpressure immediately recenters the visual even if socket close stalls',()=>{
  const h=controller();h.press('LS');h.sockets[0].bufferedAmount=20000;h.tick(250);
  assert.equal(h.state().lx,0);assert.equal(h.el('LS').querySelector().style.transform,'');
  assert.equal(h.el('LS').capture.size,0);
});
test('same-orientation viewport changes release stale joystick geometry',()=>{
  const h=controller();h.press('LS');h.resize();assert.equal(h.input().lx,0);
});
test('server reset generation clears touches and is acknowledged with neutral input',()=>{
  const h=controller();h.press('LS');h.sockets[0].message({type:'reset',epoch:1});
  assert.equal(h.input().lx,0);assert.equal(h.sockets[0].sent.at(-1).epoch,1);
});
test('stale socket callbacks cannot clear a replacement connection',()=>{
  const h=controller(),old=h.sockets[0];old.readyState=3;old.onclose({code:1006});
  h.get('join-form').onsubmit({preventDefault(){}});h.sockets[1].open();h.press('LS');
  old.onclose({code:1006});assert.ok(h.state().lx>0);
});
test('blur resets both sticks and all pressed buttons',()=>{
  const h=controller();h.press('LS',1);h.press('RS',2);h.press('A',3);h.win.emit('blur');
  assert.equal(h.input().lx,0);assert.equal(h.input().rx,0);assert.deepEqual(h.input().buttons,[]);
});
test('double-tap zoom is canceled',()=>{
  const h=controller();let prevented=false;
  h.doc.emit('dblclick',{preventDefault(){prevented=true;}});assert.equal(prevented,true);
});
test('Safari pinch gestures are canceled without clearing held controls',()=>{
  const h=controller();h.press('LS',1);h.press('A',2);
  for(const type of ['gesturestart','gesturechange','gestureend']){
    let prevented=false;h.doc.emit(type,{preventDefault(){prevented=true;}});assert.equal(prevented,true);
  }
  assert.ok(h.state().lx>0);assert.deepEqual(h.state().buttons,['A']);
});
test('touchend suppresses control double taps but leaves toolbar clicks alone',()=>{
  const h=controller();let prevented=false;
  h.doc.emit('touchend',{target:h.el('LS'),touches:[],changedTouches:[],preventDefault(){prevented=true;}});
  assert.equal(prevented,true);prevented=false;
  h.doc.emit('touchend',{target:h.get('edit'),touches:[],changedTouches:[],preventDefault(){prevented=true;}});
  assert.equal(prevented,false);
});
