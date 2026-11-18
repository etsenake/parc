export type Scape = 'morning' | 'day' | 'golden' | 'night';

interface Soundscape {
  chords: number[][];
  cutoff: number;
  vol: number;
  spark: number[];
  sparkVol: number;
  len: number;
  extra: 'birds' | 'crickets' | null;
}

const SCAPES: Record<Scape, Soundscape> = {
  morning: { chords: [[196, 246.94, 293.66, 369.99, 440], [220, 261.63, 329.63, 392, 493.88], [164.81, 246.94, 293.66, 369.99, 392], [196, 246.94, 293.66, 349.23, 440]], cutoff: 1500, vol: .02, spark: [783.99, 880, 987.77, 1174.66, 1318.51, 1567.98], sparkVol: .028, len: 5200, extra: 'birds' },
  day: { chords: [[130.81, 196, 246.94, 293.66, 329.63], [174.61, 220, 261.63, 329.63, 392], [110, 164.81, 196, 246.94, 261.63], [98, 146.83, 196, 220, 246.94]], cutoff: 1100, vol: .024, spark: [523.25, 587.33, 659.25, 783.99, 880, 1046.5], sparkVol: .032, len: 4800, extra: null },
  golden: { chords: [[138.59, 207.65, 261.63, 311.13, 349.23], [116.54, 174.61, 207.65, 261.63, 277.18], [92.5, 138.59, 174.61, 233.08, 277.18], [103.83, 155.56, 174.61, 207.65, 261.63]], cutoff: 750, vol: .03, spark: [554.37, 622.25, 698.46, 830.61, 932.33], sparkVol: .024, len: 6000, extra: null },
  night: { chords: [[130.81, 196, 246.94, 293.66, 329.63], [110, 164.81, 196, 246.94, 261.63], [87.31, 130.81, 164.81, 220, 246.94], [98, 146.83, 164.81, 220, 246.94]], cutoff: 900, vol: .03, spark: [523.25, 587.33, 659.25, 783.99, 880, 1046.5], sparkVol: .03, len: 4800, extra: 'crickets' },
};

let on = false;
let ctx: AudioContext | null = null;
let master: GainNode;
let bus: GainNode | null = null;
let noise: AudioBuffer | null = null;
let scape: Scape | null = null;
let scapeTimer = 0;
let scapeToken: object | null = null;

function audio(): AudioContext | null {
  if (!ctx) {
    const AC = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = .9;
    const delay = ctx.createDelay(), fb = ctx.createGain(), wet = ctx.createGain();
    delay.delayTime.value = .32; fb.gain.value = .3; wet.gain.value = .3;
    master.connect(ctx.destination); master.connect(delay); delay.connect(fb); fb.connect(delay); delay.connect(wet); wet.connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

function pluck(ac: AudioContext, freq: number, when: number, vol: number, dest: AudioNode = master) {
  const t = when || ac.currentTime, g = ac.createGain();
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + .012); g.gain.exponentialRampToValueAtTime(.0001, t + 1.8);
  const o1 = ac.createOscillator(), o2 = ac.createOscillator(), g2 = ac.createGain();
  o1.type = 'sine'; o1.frequency.value = freq; o2.type = 'triangle'; o2.frequency.value = freq * 2; o2.detune.value = 5; g2.gain.value = .22;
  o1.connect(g); o2.connect(g2); g2.connect(g); g.connect(dest);
  o1.start(t); o2.start(t); o1.stop(t + 1.9); o2.stop(t + 1.9);
}

function padVoice(ac: AudioContext, freq: number, t: number, dur: number, out: AudioNode, cutoff: number, vol: number) {
  const f = ac.createBiquadFilter(), g = ac.createGain();
  f.type = 'lowpass'; f.frequency.value = cutoff; f.Q.value = .6;
  g.gain.setValueAtTime(.0001, t); g.gain.linearRampToValueAtTime(vol, t + 1.8); g.gain.setValueAtTime(vol, t + dur - 2.2); g.gain.linearRampToValueAtTime(.0001, t + dur);
  [-7, 7].forEach((d) => { const o = ac.createOscillator(); o.type = 'sawtooth'; o.frequency.value = freq; o.detune.value = d; o.connect(f); o.start(t); o.stop(t + dur + .1); });
  f.connect(g); g.connect(out);
}

function chirps(ac: AudioContext, t: number, out: AudioNode) {
  const n = 2 + Math.floor(Math.random() * 3);
  for (let k = 0; k < n; k++) {
    const s = t + k * .13, base = 2400 + Math.random() * 900, o = ac.createOscillator(), g = ac.createGain();
    o.type = 'sine'; o.frequency.setValueAtTime(base, s); o.frequency.exponentialRampToValueAtTime(base * 1.45, s + .05); o.frequency.exponentialRampToValueAtTime(base * .9, s + .1);
    g.gain.setValueAtTime(.0001, s); g.gain.exponentialRampToValueAtTime(.022, s + .015); g.gain.exponentialRampToValueAtTime(.0001, s + .11);
    o.connect(g); g.connect(out); o.start(s); o.stop(s + .13);
  }
}

function cricket(ac: AudioContext, t: number, out: AudioNode) {
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = 'sine'; o.frequency.value = 4200 + Math.random() * 300; g.gain.setValueAtTime(.0001, t);
  for (let k = 0; k < 6; k++) { const s = t + k * .045; g.gain.setValueAtTime(.0001, s); g.gain.linearRampToValueAtTime(.009, s + .01); g.gain.linearRampToValueAtTime(.0001, s + .035); }
  o.connect(g); g.connect(out); o.start(t); o.stop(t + .3);
}

function startScape(key: Scape) {
  const ac = audio();
  if (!ac) return;
  const S = SCAPES[key], out = ac.createGain(), token = {};
  out.gain.setValueAtTime(.0001, ac.currentTime); out.gain.linearRampToValueAtTime(1, ac.currentTime + 1.6); out.connect(master);
  bus = out; scape = key; scapeToken = token;
  let i = 0;
  const play = () => {
    if (scapeToken !== token) return;
    const t = ac.currentTime + .05, dur = S.len / 1000 + 1.6;
    S.chords[i % 4].forEach((f) => padVoice(ac, f, t, dur, out, S.cutoff, S.vol));
    [.4, 1.3, 2.6, 3.4].forEach((d, j) => pluck(ac, S.spark[(i * 2 + j * 3) % S.spark.length], t + d, S.sparkVol, out));
    if (S.extra === 'birds') { chirps(ac, t + .8 + Math.random() * 1.5, out); chirps(ac, t + 2.8 + Math.random() * 1.5, out); }
    if (S.extra === 'crickets') for (let k = 0; k < 4; k++) cricket(ac, t + k * 1.2 + Math.random() * .3, out);
    i += 1; scapeTimer = window.setTimeout(play, S.len);
  };
  play();
}

function stopScape() {
  scapeToken = null; scape = null; clearTimeout(scapeTimer);
  if (bus && ctx) {
    const b = bus, ac = ctx;
    try { b.gain.cancelScheduledValues(ac.currentTime); b.gain.setTargetAtTime(0, ac.currentTime, .3); } catch {}
    setTimeout(() => { try { b.disconnect(); } catch {} }, 2200);
    bus = null;
  }
}

export function chime(freqs: number[], gap: number, vol: number) {
  if (!ctx) return;
  const ac = ctx, t = ac.currentTime;
  freqs.forEach((f, i) => pluck(ac, f, t + i * gap, vol));
}

export function whoosh(up: boolean) {
  if (!ctx) return;
  const ac = ctx;
  if (!noise) { noise = ac.createBuffer(1, Math.floor(ac.sampleRate * .5), ac.sampleRate); const d = noise.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
  const src = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain(), t = ac.currentTime;
  src.buffer = noise; f.type = 'bandpass'; f.Q.value = .8;
  f.frequency.setValueAtTime(up ? 400 : 1800, t); f.frequency.exponentialRampToValueAtTime(up ? 2200 : 300, t + .4);
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.08, t + .08); g.gain.exponentialRampToValueAtTime(.0001, t + .45);
  src.connect(f); f.connect(g); g.connect(master); src.start(t); src.stop(t + .5);
}

export function sfx(play: () => void) {
  if (on && ctx) { try { play(); } catch {} }
}

export function soundOn(): boolean {
  return on;
}

export function setSound(next: boolean, key: Scape) {
  on = next;
  if (on) startScape(key); else stopScape();
}

export function followScape(key: Scape) {
  if (on && key !== scape) { stopScape(); startScape(key); }
}
