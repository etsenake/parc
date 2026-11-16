(() => {
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const darkMQ = matchMedia('(prefers-color-scheme: dark)');
const root = $('#root'), hero = $('#top'), sun = $('#sun'), reveal = $('#reveal');
const remember = (key, value) => { try { if (value === undefined) return localStorage.getItem(key); localStorage.setItem(key, value); } catch (e) {} return null; };

const TIMES = ['morning', 'day', 'golden', 'night'];
const brand = 'linear-gradient(100deg,#FF4A57 10%,#B0408F 50%,#2D5BFF 90%)';
const warm = 'linear-gradient(100deg,#FFE7A0 10%,#FFC98A 50%,#FF9DB0 90%)';
const L = { chipBg: 'rgba(255,255,255,.55)', chipBorder: 'rgba(28,36,64,.16)' };
const D = { chipBg: 'rgba(255,255,255,.1)', chipBorder: 'rgba(255,255,255,.22)' };
const lampOn = 'radial-gradient(circle, rgba(255,226,150,.85) 0%, rgba(255,226,150,0) 70%)';
const SKIES = {
  morning: { ...L, sky: 'linear-gradient(180deg,#F4B79A 0%,#F9D3B4 42%,#FCEBD6 78%,#FFF4E6 100%)', sun: '#FFF1DA', sunShadow: '0 0 0 18px rgba(255,214,170,.55),0 0 0 48px rgba(255,196,150,.32),0 0 180px 40px rgba(255,196,150,.32)', sunY: 330, ink: '#1C2440', inkSoft: 'rgba(28,36,64,.82)', inkInv: '#FFF4E6', string: 'rgba(28,36,64,.5)', cloud: .9, hills: ['#A9C79B', '#78A982', '#4C8661'], tree: '#5E9470', trunk: '#5B4632', lampHead: '#F3EAD6', lampGlow: 'transparent', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'morning', night: false },
  day: { ...L, sky: 'linear-gradient(180deg,#6FA9EE 0%,#9CC8F5 45%,#CFE5FB 80%,#EEF6FF 100%)', sun: '#FFF6D8', sunShadow: '0 0 0 18px rgba(255,246,216,.55),0 0 0 48px rgba(255,240,190,.28),0 0 180px 40px rgba(255,240,190,.28)', sunY: 96, ink: '#14203F', inkSoft: 'rgba(20,32,63,.84)', inkInv: '#EEF6FF', string: 'rgba(20,32,63,.45)', cloud: .95, hills: ['#9CCB8C', '#62A56E', '#3B7F55'], tree: '#4F9461', trunk: '#5B4632', lampHead: '#F3EAD6', lampGlow: 'transparent', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'day', night: false },
  golden: { chipBg: 'rgba(255,255,255,.4)', chipBorder: 'rgba(42,24,56,.2)', sky: 'linear-gradient(180deg,#E9805B 0%,#F4A26C 38%,#F9C98C 72%,#FCE3B6 100%)', sun: '#FFE3A1', sunShadow: '0 0 0 18px rgba(255,214,140,.6),0 0 0 48px rgba(255,170,110,.32),0 0 180px 40px rgba(255,170,110,.32)', sunY: 370, ink: '#2A1838', inkSoft: 'rgba(42,24,56,.84)', inkInv: '#FCE3B6', string: 'rgba(42,24,56,.5)', cloud: .78, hills: ['#B7A66C', '#8E8B55', '#5E6B44'], tree: '#77784A', trunk: '#4E3A2A', lampHead: '#FFE3A1', lampGlow: 'rgba(255,214,140,.35)', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'golden', night: false },
  night: { ...D, sky: 'linear-gradient(180deg,#0B1030 0%,#18205A 50%,#2C2F6E 85%,#3B3A78 100%)', sun: '#F2EEDC', sunShadow: 'none', sunY: 110, ink: '#F4EFE4', inkSoft: 'rgba(244,239,228,.86)', inkInv: '#0B1030', string: 'rgba(244,239,228,.42)', cloud: .14, hills: ['#2A3466', '#1F2853', '#151C3E'], tree: '#232D5C', trunk: '#141A38', lampHead: '#FFE7A0', lampGlow: lampOn, orb: 'moon', stars: true, flies: false, shoot: false, reveal: warm, scape: 'night', night: true },
  morningDark: { ...D, sky: 'linear-gradient(180deg,#121836 0%,#262B5C 42%,#5B4778 72%,#C9787A 92%,#F2A27E 100%)', sun: '#FFD9A8', sunShadow: '0 0 0 16px rgba(255,190,140,.25),0 0 120px 50px rgba(255,160,120,.35)', sunY: 600, ink: '#F6EFE6', inkSoft: 'rgba(246,239,230,.86)', inkInv: '#121836', string: 'rgba(246,239,230,.42)', cloud: .22, hills: ['#3A3F6E', '#2C3159', '#1E2344'], tree: '#2F3563', trunk: '#171B36', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFD9A8 10%,#FF9DB0 50%,#9DB4FF 90%)', scape: 'morning', night: true },
  dayDark: { ...D, sky: 'linear-gradient(180deg,#0D1422 0%,#1A2638 45%,#34445A 80%,#5E6E80 100%)', sun: '#0A0D15', sunShadow: '0 0 0 3px rgba(255,244,214,.95),0 0 36px 14px rgba(255,232,180,.6),0 0 140px 60px rgba(255,214,150,.22)', sunY: 110, ink: '#EEF1F6', inkSoft: 'rgba(238,241,246,.86)', inkInv: '#0D1422', string: 'rgba(238,241,246,.4)', cloud: .12, hills: ['#2E3B45', '#24303A', '#18222B'], tree: '#2A3640', trunk: '#121A21', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFF4D6 10%,#FFD27A 50%,#FFFFFF 90%)', scape: 'day', night: true },
  goldenDark: { ...D, sky: 'linear-gradient(180deg,#160F33 0%,#3A1E52 38%,#8A3A5E 68%,#E0685A 88%,#F59A62 100%)', sun: '#FFC27A', sunShadow: '0 0 0 16px rgba(255,160,110,.3),0 0 160px 60px rgba(255,120,90,.35)', sunY: 630, ink: '#FBEFE6', inkSoft: 'rgba(251,239,230,.86)', inkInv: '#160F33', string: 'rgba(251,239,230,.42)', cloud: .3, hills: ['#4A2D52', '#36213F', '#24162C'], tree: '#3E2747', trunk: '#1A1020', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFC27A 10%,#FF7A8A 50%,#B79CFF 90%)', scape: 'golden', night: true },
  nightDark: { ...D, sky: 'linear-gradient(180deg,#05071A 0%,#0D1236 55%,#1A1E4A 88%,#262A5C 100%)', sun: '#F7F3E3', sunShadow: 'none', sunY: 100, ink: '#F4EFE4', inkSoft: 'rgba(244,239,228,.86)', inkInv: '#05071A', string: 'rgba(244,239,228,.4)', cloud: .1, hills: ['#1B2250', '#141A40', '#0D122E'], tree: '#18204A', trunk: '#0A0E24', lampHead: '#FFE7A0', lampGlow: lampOn, orb: 'moon moon-bright', stars: true, flies: true, shoot: true, reveal: warm, scape: 'night', night: true }
};
const state = { skyStep: null, dark: darkMQ.matches, sound: false, space: 0, open: null, shuffle: 0, scape: null };

let seed = 7;
const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
const starBox = $('#stars');
for (let i = 0; i < 48; i++) {
  const s = document.createElement('span'); s.className = 'star';
  const z = (1 + rnd() * 2.4).toFixed(1) + 'px';
  Object.assign(s.style, { left: (rnd() * 100).toFixed(2) + '%', top: (rnd() * 60).toFixed(2) + '%', width: z, height: z, animationDelay: (rnd() * -6).toFixed(2) + 's', animationDuration: (2.4 + rnd() * 4).toFixed(2) + 's' });
  starBox.appendChild(s);
}
const flyBox = $('#flies');
['fa', 'fb', 'fc'].forEach((d) => {
  for (let i = 0; i < 6; i++) {
    const w = document.createElement('span'); w.className = d;
    Object.assign(w.style, { left: (rnd() * 100).toFixed(2) + '%', top: Math.round(470 + rnd() * 360) + 'px', animationDuration: (10 + rnd() * 10).toFixed(1) + 's', animationDelay: (rnd() * -20).toFixed(1) + 's' });
    const f = document.createElement('span'); f.className = 'fly';
    const z = (3 + rnd() * 3).toFixed(1) + 'px';
    Object.assign(f.style, { width: z, height: z, animationDuration: (2 + rnd() * 3).toFixed(1) + 's', animationDelay: (rnd() * -5).toFixed(1) + 's' });
    w.appendChild(f); flyBox.appendChild(w);
  }
});

const TRAIL = ['#FF4A57', '#2D5BFF', '#7DB36B', '#FFB347', '#B0408F', '#2D5BFF', '#FF4A57'];
const trailBox = $('#trail');
const trailEls = TRAIL.map((c, i) => { const s = document.createElement('span'); s.className = 'trail-dot ' + (i % 2 ? 'petal' : 'leaf'); Object.assign(s.style, { width: (12 - i) + 'px', height: (12 - i) + 'px', background: c }); trailBox.appendChild(s); return s; });

const autoTime = () => { const h = new Date().getHours(); return h >= 5 && h < 10 ? 'morning' : h >= 10 && h < 16 ? 'day' : h >= 16 && h < 20 ? 'golden' : 'night'; };
const timeKey = () => state.skyStep !== null ? TIMES[state.skyStep] : autoTime();
const skyKey = () => timeKey() + (state.dark ? 'Dark' : '');
let sky = SKIES[skyKey()];
function applySky() {
  sky = SKIES[skyKey()];
  const v = {
    '--sky': sky.sky, '--sun': sky.sun, '--sun-shadow': sky.sunShadow, '--sun-top': sky.sunY + 'px',
    '--ink': sky.ink, '--ink-soft': sky.inkSoft, '--ink-inv': sky.inkInv, '--string': sky.string, '--cloud': sky.cloud, '--chip-bg': sky.chipBg, '--chip-border': sky.chipBorder,
    '--hill-back': sky.hills[0], '--hill-mid': sky.hills[1], '--hill-front': sky.hills[2], '--tree': sky.tree, '--trunk': sky.trunk, '--lamp-head': sky.lampHead, '--lamp-glow': sky.lampGlow, '--reveal': sky.reveal
  };
  for (const k in v) hero.style.setProperty(k, v[k]);
  hero.classList.toggle('has-stars', sky.stars); hero.classList.toggle('has-flies', sky.flies); hero.classList.toggle('has-shoot', sky.shoot);
  sun.className = 'sun' + (sky.orb ? ' ' + sky.orb : '');
  trailEls.forEach((el) => el.classList.toggle('trail-night', sky.night));
  const meta = $('meta[name="theme-color"]'); if (meta) meta.setAttribute('content', sky.night ? '#0B1030' : '#F4B79A');
  if (state.sound && sky.scape !== state.scape) { stopScape(); startScape(sky.scape); }
  paintCard();
}
sun.addEventListener('click', () => {
  const cur = TIMES.indexOf(timeKey()), now = TIMES.indexOf(autoTime()), next = (cur + 1) % 4;
  sfx(() => chime([523.25, 659.25, 783.99, 1046.5], 0.08, 0.07));
  state.skyStep = next === now && state.skyStep !== null ? null : next;
  applySky();
});
const onScheme = (e) => { state.dark = e.matches; applySky(); };
if (darkMQ.addEventListener) darkMQ.addEventListener('change', onScheme); else if (darkMQ.addListener) darkMQ.addListener(onScheme);
setInterval(() => { if (state.skyStep === null) applySky(); }, 30000);

const px = { sun: $('#pxSun'), clouds: $('#pxClouds'), kite: $('#pxKite'), trees: $('#pxTrees'), hills: $('#pxHills') };
const DEPTH = { sun: [-36, -24], clouds: [-60, -18], kite: [46, 28], trees: [-14, 0], hills: [-10, 0] };
hero.addEventListener('mousemove', (e) => {
  const r = hero.getBoundingClientRect(), nx = (e.clientX - r.left) / r.width - .5, ny = (e.clientY - r.top) / r.height - .5;
  if (!reduced) for (const k in px) px[k].style.transform = `translate(${(nx * DEPTH[k][0]).toFixed(1)}px, ${(ny * DEPTH[k][1]).toFixed(1)}px)`;
  const rr = reveal.getBoundingClientRect(), pos = `${(e.clientX - rr.left - 170).toFixed(0)}px ${(e.clientY - rr.top - 170).toFixed(0)}px`;
  reveal.style.webkitMaskPosition = pos; reveal.style.maskPosition = pos; reveal.style.opacity = '1';
});
hero.addEventListener('mouseleave', () => { for (const k in px) px[k].style.transform = ''; reveal.style.opacity = '0'; });

const tp = TRAIL.map(() => ({ x: -200, y: -200 }));
let mouse = null, lastMove = 0, trailShown = false, trailRunning = false;
function trailFrame() {
  if (!mouse || performance.now() - lastMove > 1400) {
    if (trailShown) { trailEls.forEach((el) => { el.style.opacity = '0'; }); trailShown = false; }
    trailRunning = false; return;
  }
  let tx = mouse.x, ty = mouse.y;
  tp.forEach((p, i) => {
    const k = i === 0 ? .4 : .32; p.x += (tx - p.x) * k; p.y += (ty - p.y) * k; tx = p.x; ty = p.y;
    trailEls[i].style.transform = `translate3d(${p.x.toFixed(1)}px, ${p.y.toFixed(1)}px, 0) rotate(${Math.round(i * 40 + p.x * .6)}deg)`;
  });
  requestAnimationFrame(trailFrame);
}
root.addEventListener('mousemove', (e) => {
  if (reduced) return;
  const r = root.getBoundingClientRect(); mouse = { x: e.clientX - r.left, y: e.clientY - r.top }; lastMove = performance.now();
  if (!trailShown) { trailEls.forEach((el, i) => { el.style.opacity = String(1 - i * .1); }); trailShown = true; }
  if (!trailRunning) { trailRunning = true; requestAnimationFrame(trailFrame); }
});
root.addEventListener('mouseleave', () => { mouse = null; });

let ctx = null, master = null, bus = null, noise = null, scapeTimer = 0, scapeToken = null;
const SCAPES = {
  morning: { chords: [[196, 246.94, 293.66, 369.99, 440], [220, 261.63, 329.63, 392, 493.88], [164.81, 246.94, 293.66, 369.99, 392], [196, 246.94, 293.66, 349.23, 440]], cutoff: 1500, vol: .02, spark: [783.99, 880, 987.77, 1174.66, 1318.51, 1567.98], sparkVol: .028, len: 5200, extra: 'birds' },
  day: { chords: [[130.81, 196, 246.94, 293.66, 329.63], [174.61, 220, 261.63, 329.63, 392], [110, 164.81, 196, 246.94, 261.63], [98, 146.83, 196, 220, 246.94]], cutoff: 1100, vol: .024, spark: [523.25, 587.33, 659.25, 783.99, 880, 1046.5], sparkVol: .032, len: 4800, extra: null },
  golden: { chords: [[138.59, 207.65, 261.63, 311.13, 349.23], [116.54, 174.61, 207.65, 261.63, 277.18], [92.5, 138.59, 174.61, 233.08, 277.18], [103.83, 155.56, 174.61, 207.65, 261.63]], cutoff: 750, vol: .03, spark: [554.37, 622.25, 698.46, 830.61, 932.33], sparkVol: .024, len: 6000, extra: null },
  night: { chords: [[130.81, 196, 246.94, 293.66, 329.63], [110, 164.81, 196, 246.94, 261.63], [87.31, 130.81, 164.81, 220, 246.94], [98, 146.83, 164.81, 220, 246.94]], cutoff: 900, vol: .03, spark: [523.25, 587.33, 659.25, 783.99, 880, 1046.5], sparkVol: .03, len: 4800, extra: 'crickets' }
};
function audio() {
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return null;
    ctx = new AC(); master = ctx.createGain(); master.gain.value = .9;
    const delay = ctx.createDelay(), fb = ctx.createGain(), wet = ctx.createGain();
    delay.delayTime.value = .32; fb.gain.value = .3; wet.gain.value = .3;
    master.connect(ctx.destination); master.connect(delay); delay.connect(fb); fb.connect(delay); delay.connect(wet); wet.connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}
function pluck(freq, when, vol, dest) {
  const t = when || ctx.currentTime, g = ctx.createGain();
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + .012); g.gain.exponentialRampToValueAtTime(.0001, t + 1.8);
  const o1 = ctx.createOscillator(), o2 = ctx.createOscillator(), g2 = ctx.createGain();
  o1.type = 'sine'; o1.frequency.value = freq; o2.type = 'triangle'; o2.frequency.value = freq * 2; o2.detune.value = 5; g2.gain.value = .22;
  o1.connect(g); o2.connect(g2); g2.connect(g); g.connect(dest || master);
  o1.start(t); o2.start(t); o1.stop(t + 1.9); o2.stop(t + 1.9);
}
function padVoice(freq, t, dur, out, cutoff, vol) {
  const f = ctx.createBiquadFilter(), g = ctx.createGain();
  f.type = 'lowpass'; f.frequency.value = cutoff; f.Q.value = .6;
  g.gain.setValueAtTime(.0001, t); g.gain.linearRampToValueAtTime(vol, t + 1.8); g.gain.setValueAtTime(vol, t + dur - 2.2); g.gain.linearRampToValueAtTime(.0001, t + dur);
  [-7, 7].forEach((d) => { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = freq; o.detune.value = d; o.connect(f); o.start(t); o.stop(t + dur + .1); });
  f.connect(g); g.connect(out);
}
function chirps(t, out) {
  const n = 2 + Math.floor(Math.random() * 3);
  for (let k = 0; k < n; k++) {
    const s = t + k * .13, base = 2400 + Math.random() * 900, o = ctx.createOscillator(), g = ctx.createGain();
    o.type = 'sine'; o.frequency.setValueAtTime(base, s); o.frequency.exponentialRampToValueAtTime(base * 1.45, s + .05); o.frequency.exponentialRampToValueAtTime(base * .9, s + .1);
    g.gain.setValueAtTime(.0001, s); g.gain.exponentialRampToValueAtTime(.022, s + .015); g.gain.exponentialRampToValueAtTime(.0001, s + .11);
    o.connect(g); g.connect(out); o.start(s); o.stop(s + .13);
  }
}
function cricket(t, out) {
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = 'sine'; o.frequency.value = 4200 + Math.random() * 300; g.gain.setValueAtTime(.0001, t);
  for (let k = 0; k < 6; k++) { const s = t + k * .045; g.gain.setValueAtTime(.0001, s); g.gain.linearRampToValueAtTime(.009, s + .01); g.gain.linearRampToValueAtTime(.0001, s + .035); }
  o.connect(g); g.connect(out); o.start(t); o.stop(t + .3);
}
function whoosh(up) {
  if (!noise) { noise = ctx.createBuffer(1, Math.floor(ctx.sampleRate * .5), ctx.sampleRate); const d = noise.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
  const src = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain(), t = ctx.currentTime;
  src.buffer = noise; f.type = 'bandpass'; f.Q.value = .8;
  f.frequency.setValueAtTime(up ? 400 : 1800, t); f.frequency.exponentialRampToValueAtTime(up ? 2200 : 300, t + .4);
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.08, t + .08); g.gain.exponentialRampToValueAtTime(.0001, t + .45);
  src.connect(f); f.connect(g); g.connect(master); src.start(t); src.stop(t + .5);
}
function chime(freqs, gap, vol) { const t = ctx.currentTime; freqs.forEach((f, i) => pluck(f, t + i * gap, vol)); }
function sfx(fn) { if (state.sound && ctx) { try { fn(); } catch (e) {} } }
function startScape(key) {
  if (!audio()) return;
  const S = SCAPES[key], out = ctx.createGain(), token = {};
  out.gain.setValueAtTime(.0001, ctx.currentTime); out.gain.linearRampToValueAtTime(1, ctx.currentTime + 1.6); out.connect(master);
  bus = out; state.scape = key; scapeToken = token;
  let i = 0;
  const play = () => {
    if (scapeToken !== token) return;
    const t = ctx.currentTime + .05, dur = S.len / 1000 + 1.6;
    S.chords[i % 4].forEach((f) => padVoice(f, t, dur, out, S.cutoff, S.vol));
    [.4, 1.3, 2.6, 3.4].forEach((d, j) => pluck(S.spark[(i * 2 + j * 3) % S.spark.length], t + d, S.sparkVol, out));
    if (S.extra === 'birds') { chirps(t + .8 + Math.random() * 1.5, out); chirps(t + 2.8 + Math.random() * 1.5, out); }
    if (S.extra === 'crickets') for (let k = 0; k < 4; k++) cricket(t + k * 1.2 + Math.random() * .3, out);
    i += 1; scapeTimer = setTimeout(play, S.len);
  };
  play();
}
function stopScape() {
  scapeToken = null; state.scape = null; clearTimeout(scapeTimer);
  if (bus && ctx) { const b = bus; try { b.gain.cancelScheduledValues(ctx.currentTime); b.gain.setTargetAtTime(0, ctx.currentTime, .3); } catch (e) {} setTimeout(() => { try { b.disconnect(); } catch (e) {} }, 2200); bus = null; }
}
const soundBtn = $('#soundBtn');
soundBtn.addEventListener('click', () => {
  state.sound = !state.sound;
  soundBtn.setAttribute('aria-pressed', String(state.sound));
  if (state.sound) startScape(sky.scape); else stopScape();
});

const SPACES = [
  { name: 'Work', color: '#3D63F0', tint: '#E3E8FC', url: 'docs.yourcompany.com/q4', title: 'Q4 planning', data: 'w', note: 659.25, pins: ['R', 'I', 'C', 'D'], today: ['Q4 planning doc', 'Design review notes', 'Team calendar', 'Release checklist'] },
  { name: 'Home', color: '#C4502E', tint: '#FBE4D9', url: 'recipes.example/sunday-roast', title: 'Sunday roast', data: 'h', note: 587.33, pins: ['G', 'B', 'R', 'S'], today: ['Sunday roast recipe', 'Furnace filter sizes', 'Flights to Lisbon', 'Library holds'] },
  { name: 'Side quest', color: '#237A51', tint: '#DCEFE3', url: 'forum.example/pottery', title: 'Pottery wheel notes', data: 'h', note: 783.99, pins: ['P', 'S', 'B', 'M'], today: ['Pottery wheel reviews', 'Synth patch ideas', 'Weekend bike route', 'Sourdough schedule'] },
  { name: 'Late reading', color: '#7550E6', tint: '#E9E3FB', url: 'longreads.example/maps', title: 'A short history of maps', data: 'h', note: 880, pins: ['E', 'P', 'A', 'L'], today: ['A short history of maps', 'An essay on public gardens', 'Poetry archive', 'Saved for the weekend'] }
];
const DATA = { w: { who: 'you@yourcompany.com', av: '#18203A' }, h: { who: 'you@yourmail.com', av: '#E0803A' } };
const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };
const swatches = $('#swatches'), dots = $('#sDots');
let fadeFlip = false;
SPACES.forEach((sp, i) => {
  const b = el('button', 'swatch'); b.type = 'button';
  const dot = el('i'); dot.style.background = sp.color; dot.setAttribute('aria-hidden', 'true');
  b.append(dot, el('span', '', sp.name));
  b.addEventListener('click', () => pickSpace(i)); swatches.appendChild(b);
  const d = el('button', 'dot-btn'); d.type = 'button'; d.tabIndex = -1; d.setAttribute('aria-label', 'Switch to ' + sp.name);
  d.addEventListener('click', () => pickSpace(i)); dots.appendChild(d);
});
function renderSpace() {
  const sp = SPACES[state.space], fade = fadeFlip ? 'fade-b' : 'fade-a';
  $('#spaces').style.backgroundColor = sp.tint; $('#sbar').style.backgroundColor = sp.color;
  $('#sUrl').textContent = sp.url; $('#sName').textContent = sp.name;
  const pins = $('#sPins'); pins.className = 'mock-pins ' + fade; pins.replaceChildren(...sp.pins.map((g) => el('div', '', g)));
  const today = $('#sToday'); today.className = 'mock-today ' + fade;
  today.replaceChildren(...sp.today.map((t) => { const row = el('div'); row.append(el('i'), el('span', '', t)); return row; }));
  $('#sPage').className = 'mock-page ' + fade; $('#sPill').style.backgroundColor = sp.color; $('#sPill').textContent = sp.name; $('#sTitle').textContent = sp.title;
  $('#sImg').style.backgroundColor = sp.tint; $('#sCircle').style.backgroundColor = sp.color;
  $('#sAv').style.backgroundColor = DATA[sp.data].av; $('#sWho').textContent = DATA[sp.data].who;
  const others = SPACES.filter((o) => o !== sp);
  $('#sMenuRows').replaceChildren(...others.map((o) => {
    const row = el('div', 'smenu-row' + (o.data === sp.data ? ' on' : ''));
    const swatch = el('i'); swatch.style.background = o.color;
    row.append(el('span', 'smenu-check', '✓'), swatch, document.createTextNode(o.name));
    return row;
  }));
  $('#sKeep').classList.toggle('on', !others.some((o) => o.data === sp.data));
  $('#sMenu').className = 'smenu ' + (fadeFlip ? 'menu-b' : 'menu-a');
  $$('.swatch', swatches).forEach((b, i) => { b.classList.toggle('is-on', i === state.space); b.setAttribute('aria-pressed', String(i === state.space)); });
  $$('.dot-btn', dots).forEach((d, i) => d.classList.toggle('is-on', i === state.space));
}
function pickSpace(i) {
  const sp = SPACES[i]; sfx(() => chime([sp.note, sp.note * 1.5], .08, .1));
  if (i === state.space) return; state.space = i; fadeFlip = !fadeFlip; renderSpace();
}

const SPECIMENS = [
  { no: '01', clip: 'split', name: 'Split View', latin: 'Paginae duae', behavior: 'Up to four pages, side by side or stacked. Drag the edges, or make them all equal. Copy Links grabs the lot.', habitat: 'Comparing, copying, cross-checking.', spot: 'Option-click a link. Or drag a tab onto your page.', note: 'pairs for life.' },
  { no: '02', clip: 'peek', name: 'Peek', latin: 'Prospectus brevis', behavior: 'Links float over your page so you keep your place. Fling one away with two fingers, or keep it as a tab. Hover a tab in the sidebar and its card can Peek it too. Nothing reloads.', habitat: 'Links to other sites. Anything you Shift-click. Any tab’s preview card.', spot: 'A page floating up front while yours takes a polite step back.', note: 'springs back if you chicken out.' },
  { no: '03', clip: 'commandbar', name: 'Command Bar', latin: 'Imperium clavis', behavior: 'Search, jump to a tab, or run a command. Click any address and it opens right there.', habitat: 'Dead centre.', spot: '⌘T.', note: 'loves a shortcut.' },
  { no: '04', clip: 'easel', name: 'Easels', latin: 'Tabula viva', behavior: 'Live web pages, screenshots, text and arrows on one canvas. The pages keep working.', habitat: 'Moodboards, research walls, trip plans.', spot: 'File → New Easel.', note: 'naps after four hours, like the rest of us.' },
  { no: '05', name: 'Notes', latin: 'Scriptura localis', behavior: 'A title, a body, Markdown shortcuts and a real Format menu. Saved on your Mac.', habitat: 'Next to whatever you’re reading.', spot: 'New Note.', note: 'keeps secrets.' },
  { no: '06', clip: 'capture', name: 'Capture', latin: 'Imago capta', behavior: 'Drag across any part of a page to capture it. Frame it in Portrait mode, then copy it, save it to your Library or drop it on an Easel.', habitat: 'Anything worth keeping.', spot: '⌘⇧2, then drag.', note: 'frames itself nicely.' },
  { no: '07', clip: 'mini', name: 'Mini Player', latin: 'Musica pendens', behavior: 'Leave a playing tab and the controls follow you. One click to picture in picture, or send the sound to your speakers.', habitat: 'Music, talks, cooking videos.', spot: 'Leave a tab that’s playing.', note: 'follows you around, nicely.' },
  { no: '08', clip: 'crank', name: 'Window Frame', latin: 'Margo versatilis', behavior: 'Turn the crank to set the band of colour around your page, from 3 · Hairline to 13 · Gallery. Every window follows as you turn.', habitat: 'View → Adjust Window Frame…', spot: 'A car-window crank, right on your window.', note: 'goes up to thirteen.' },
  { no: '09', clip: 'archive', name: 'Archive', latin: 'Tabulae dormientes', behavior: 'Tabs you haven’t touched in 12 hours tuck themselves into the Archive. Put Back drops one right where it was.', habitat: 'Library → Archived Tabs.', spot: '“We cleaned up!”', note: 'nothing’s ever really gone.' },
  { no: '11', name: 'Custom Shortcuts', latin: 'Claves propriae', behavior: 'Change any shortcut. When a site wants the same keys, you pick who wins. Your number pad gets its own.', habitat: 'Settings → Shortcuts.', spot: 'Your fingertips.', note: 'muscle memory included.' },
  { no: '12', name: 'Moving In', latin: 'Migratio facilis', behavior: 'Your Arc Spaces, pinned tabs and Favorites move in the way you left them. Bookmarks, passwords and history come from Chrome, Safari, Firefox and the rest.', habitat: 'Your first five minutes.', spot: 'First launch.', note: 'travels light.' }
];
const plate = $('#plate'), plateL = $('#plateL'), plateR = $('#plateR'), stage = $('#plateStage');
const overlay = $('#guideOverlay'), shell = $('#gShell'), backdrop = $('#gBackdrop'), plateBody = $('.plate-body', plate);
const guideCards = $$('.card', $('#guideGrid'));
const OPEN_EASE = 'cubic-bezier(.2,.9,.25,1)', SHUT_EASE = 'cubic-bezier(.4,0,.2,1)', CARD_RADIUS = '20px';
let plateFlip = false, busy = false, fade = null;
function flipPages() {
  plateFlip = !plateFlip;
  [plateL, plateR].forEach((p) => { p.classList.remove('plate-a', 'plate-b'); p.classList.add(plateFlip ? 'plate-b' : 'plate-a'); });
}
function fillPlate(i) {
  const sp = SPECIMENS[i];
  state.open = i;
  $('#plateNo').textContent = sp.no;
  $('#plateName').textContent = sp.name; $('#plateLatin').textContent = sp.latin; $('#plateBehavior').textContent = sp.behavior;
  $('#plateHabitat').textContent = sp.habitat; $('#plateSpot').textContent = sp.spot; $('#plateNote').textContent = 'field note: ' + sp.note;
  $('#plateTag').textContent = sp.clip ? 'spotted in the wild' : 'sketched from life';
  unmountPlateClip();
  plate.classList.toggle('wide', !!sp.clip);
  stage.classList.toggle('has-clip', !!sp.clip);
  if (sp.clip) mountPlateClip(sp.clip, sp.name + ' in Parc');
  else stage.replaceChildren($('#scene-' + i).content.cloneNode(true));
  plateBody.scrollTop = 0;
  flipPages();
}
function mountPlateClip(name, label) {
  const frame = el('div', 'stage-window');
  const v = document.createElement('video');
  v.muted = true; v.defaultMuted = true; v.loop = true; v.playsInline = true; v.preload = 'auto';
  v.setAttribute('muted', ''); v.setAttribute('playsinline', '');
  v.poster = 'media/plates/' + name + '.jpg'; v.src = 'media/plates/' + name + '.mp4';
  v.setAttribute('aria-label', label);
  v.addEventListener('click', () => { if (v.paused) v.play().catch(() => {}); else v.pause(); });
  frame.appendChild(v);
  stage.replaceChildren(frame);
  if (!reduced) v.play().catch(() => {});
}
function unmountPlateClip() {
  const v = $('video', stage);
  if (!v) return;
  v.pause(); v.removeAttribute('src'); v.load();
}
const rect = (r) => ({ left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });
const onScreen = (r) => r.bottom > 0 && r.top < innerHeight && r.width > 0;
function morph(from, to, r0, r1, duration, easing, o0 = 1, o1 = 1) {
  shell.style.display = 'block';
  const anim = shell.animate([{ ...rect(from), borderRadius: r0, opacity: o0 }, { ...rect(to), borderRadius: r1, opacity: o1 }], { duration, easing, fill: 'forwards' });
  return anim.finished.then(() => anim, () => anim);
}
function fadeBackdrop(show) {
  if (fade) fade.cancel();
  fade = backdrop.animate([{ opacity: show ? 0 : 1 }, { opacity: show ? 1 : 0 }], { duration: show ? 320 : 280, easing: show ? 'ease-out' : 'ease-in', fill: 'forwards' });
}
async function openPlate(i) {
  if (busy || state.open !== null) return;
  const card = guideCards[i];
  fillPlate(i);
  overlay.hidden = false;
  document.documentElement.classList.add('g-locked');
  sfx(() => { whoosh(true); chime([783.99, 1174.66], .1, .07); });
  if (reduced) { $('#plateClose').focus({ preventScroll: true }); return; }
  busy = true;
  plate.classList.add('is-ghost');
  const from = card.getBoundingClientRect(), to = plate.getBoundingClientRect(), radius = getComputedStyle(plate).borderRadius;
  card.style.visibility = 'hidden';
  fadeBackdrop(true);
  const anim = await morph(from, to, CARD_RADIUS, radius, 480, OPEN_EASE);
  plate.classList.remove('is-ghost');
  flipPages();
  shell.style.display = 'none'; anim.cancel();
  busy = false;
  $('#plateClose').focus({ preventScroll: true });
}
async function closePlate() {
  if (busy || state.open === null) return;
  const card = guideCards[state.open];
  state.open = null;
  sfx(() => whoosh(false));
  const finish = () => {
    overlay.hidden = true; plate.classList.remove('is-ghost'); shell.style.display = 'none';
    unmountPlateClip();
    if (fade) { fade.cancel(); fade = null; }
    guideCards.forEach((c) => { c.style.visibility = ''; });
    document.documentElement.classList.remove('g-locked');
    $('[data-open]', card).focus({ preventScroll: true });
    busy = false;
  };
  if (reduced) { finish(); return; }
  busy = true;
  const from = plate.getBoundingClientRect(), to = card.getBoundingClientRect(), radius = getComputedStyle(plate).borderRadius;
  plate.classList.add('is-ghost');
  fadeBackdrop(false);
  const anim = onScreen(to) ? await morph(from, to, radius, CARD_RADIUS, 400, SHUT_EASE) : await morph(from, from, radius, radius, 240, 'ease-in', 1, 0);
  anim.cancel();
  finish();
}
function step(dir) {
  if (busy || state.open === null) return;
  const n = (state.open + dir + SPECIMENS.length) % SPECIMENS.length;
  guideCards[state.open].style.visibility = '';
  fillPlate(n);
  if (!reduced) guideCards[n].style.visibility = 'hidden';
  sfx(() => whoosh(dir > 0));
}
$$('[data-open]').forEach((b) => b.addEventListener('click', () => openPlate(+b.dataset.open)));
$$('[data-step]').forEach((b) => b.addEventListener('click', () => step(+b.dataset.step)));
$('#plateClose').addEventListener('click', closePlate);
overlay.addEventListener('click', (e) => { if (e.target === overlay || e.target === backdrop) closePlate(); });
document.addEventListener('keydown', (e) => {
  if (state.open === null) return;
  if (e.key === 'Escape') closePlate();
  else if (e.key === 'ArrowRight') step(1);
  else if (e.key === 'ArrowLeft') step(-1);
  else if (e.key === 'Tab') {
    const focusable = $$('button', plate).filter((b) => b.offsetParent !== null);
    const first = focusable[0], last = focusable[focusable.length - 1];
    if (!plate.contains(document.activeElement)) { e.preventDefault(); first.focus(); return; }
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }
});
let swipe = null;
plate.addEventListener('pointerdown', (e) => { swipe = e.pointerType === 'mouse' ? null : [e.clientX, e.clientY]; });
plate.addEventListener('pointercancel', () => { swipe = null; });
plate.addEventListener('pointerup', (e) => {
  if (!swipe) return;
  const dx = e.clientX - swipe[0], dy = e.clientY - swipe[1];
  swipe = null;
  if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) step(dx < 0 ? 1 : -1);
});

const TITLES = ['Professional Bench Sitter', 'Chief Kite Officer', 'Keeper of the Archive', 'Certified Tab Gardener', 'Regional Duck Liaison', 'Sunday Navigator', 'Friend of the Fireflies'];
const PALETTES = [
  { base: '#F7C9B0', colors: ['#FF8A6B', '#FFD27A', '#9CC8F5', '#FF4A57', '#F4B79A'] },
  { base: '#BFE0FA', colors: ['#2D5BFF', '#7DB36B', '#FFE7A0', '#6FA9EE', '#FFFFFF'] },
  { base: '#F4A26C', colors: ['#FF4A57', '#FFD27A', '#8E5C9E', '#E9805B', '#FCE3B6'] },
  { base: '#18205A', colors: ['#FFE7A0', '#7550E6', '#3D63F0', '#FF9DB0', '#2C2F6E'] }
];
const nameIn = $('#cardName'), mcard = $('#mcard'), sheen = $('#sheen');
function paintCard() {
  const pal = PALETTES[(TIMES.indexOf(sky.scape) + state.shuffle) % PALETTES.length];
  $('#cardArt').style.backgroundColor = pal.base;
  $$('#cardArt .blob').forEach((b, i) => { b.style.background = pal.colors[i]; });
  $('#cardTitle').textContent = TITLES[(state.shuffle * 3 + 1) % TITLES.length];
  const n = nameIn.value.trim() || 'Your Name';
  $('#cardShow').textContent = n;
  mcard.setAttribute('aria-label', 'Parc membership card for ' + n);
}
$('#cardDate').textContent = new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
nameIn.addEventListener('input', paintCard);
$('#shuffle').addEventListener('click', () => { sfx(() => chime([880, 1174.66, 1318.51, 1760], .05, .05)); state.shuffle += 1; paintCard(); });
const tiltZone = $('#tiltZone');
tiltZone.addEventListener('mousemove', (e) => {
  if (reduced) return;
  const r = tiltZone.getBoundingClientRect(), x = (e.clientX - r.left) / r.width - .5, y = (e.clientY - r.top) / r.height - .5;
  mcard.style.transform = `rotateX(${(-y * 16).toFixed(2)}deg) rotateY(${(x * 20).toFixed(2)}deg) scale(1.03)`;
  sheen.style.backgroundPosition = `${(50 + x * 70).toFixed(1)}% ${(50 + y * 70).toFixed(1)}%`;
});
tiltZone.addEventListener('mouseleave', () => { mcard.style.transform = ''; sheen.style.backgroundPosition = '50% 50%'; });

const ICONS = [['Original', 'Original'], ['Sorbet', 'Sorbet'], ['Twilight', 'Twilight'], ['RainGlass', 'Rain Glass'], ['Opal', 'Opal'], ['AfterHours', 'After Hours'], ['Recess', 'Recess'], ['TracingPaper', 'Tracing Paper'], ['Grapefruit', 'Grapefruit'], ['Terminal', 'Terminal']];
const iconBox = $('#icons'), dockApp = $('#dockApp'), favicon = $('link[rel="icon"]');
const iconButtons = ICONS.map(([file, label], i) => {
  const b = el('button', 'icon-pick'); b.type = 'button'; b.setAttribute('role', 'radio');
  const img = el('img'); img.src = 'assets/icons/' + file + '.png'; img.alt = ''; img.width = 84; img.height = 84; img.loading = 'lazy'; img.decoding = 'async';
  b.append(img, el('span', '', label));
  b.addEventListener('click', () => pickIcon(i, true));
  iconBox.appendChild(b);
  return b;
});
iconBox.addEventListener('keydown', (e) => {
  const i = iconButtons.indexOf(document.activeElement); if (i < 0) return;
  const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key]; if (!d) return;
  e.preventDefault(); const n = (i + d + ICONS.length) % ICONS.length; pickIcon(n, true); iconButtons[n].focus();
});
function pickIcon(i, chosen) {
  const [file] = ICONS[i], src = 'assets/icons/' + file + '.png';
  iconButtons.forEach((b, j) => { b.setAttribute('aria-checked', String(j === i)); b.tabIndex = j === i ? 0 : -1; });
  $('img', dockApp).src = src;
  if (favicon) favicon.href = src;
  if (!chosen) return;
  remember('parc-icon', file);
  sfx(() => chime([659.25, 987.77], .07, .08));
  if (!reduced) { dockApp.classList.remove('is-bouncing'); void dockApp.offsetWidth; dockApp.classList.add('is-bouncing'); }
}
pickIcon(Math.max(0, ICONS.findIndex(([file]) => file === remember('parc-icon'))), false);

$$('.copy-btn').forEach((b) => b.addEventListener('click', () => {
  const text = b.dataset.copy;
  const done = () => { b.textContent = 'Copied'; clearTimeout(b._t); b._t = setTimeout(() => { b.textContent = 'Copy'; }, 1600); };
  const select = () => { const code = b.parentNode.querySelector('code'); if (!code) return; const r = document.createRange(); r.selectNodeContents(code); const s = getSelection(); s.removeAllRanges(); s.addRange(r); };
  try {
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, () => { select(); done(); });
    else { select(); done(); }
  } catch (e) { select(); done(); }
  sfx(() => chime([1046.5, 1318.51], .06, .08));
}));

const filmFrame = $('#filmFrame'), filmVideo = $('#filmVideo');
if (filmFrame && filmVideo) {
  if (reduced) {
    filmVideo.removeAttribute('autoplay'); filmVideo.pause();
    filmVideo.addEventListener('click', () => { if (filmVideo.paused) filmVideo.play().catch(() => {}); else filmVideo.pause(); });
  } else {
    let ticking = false;
    const reveal = () => {
      ticking = false;
      const r = filmFrame.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, (innerHeight - r.top) / (innerHeight * .65)));
      filmFrame.style.setProperty('--p', p.toFixed(3));
    };
    addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(reveal); } }, { passive: true });
    addEventListener('resize', reveal);
    reveal();
    if ('IntersectionObserver' in window) {
      new IntersectionObserver((entries) => entries.forEach((e) => { if (e.isIntersecting) filmVideo.play().catch(() => {}); else filmVideo.pause(); }), { threshold: .2 }).observe(filmFrame);
    }
  }
}

renderSpace();
applySky();
})();
