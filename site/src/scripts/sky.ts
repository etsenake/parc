import type { Scape } from './sound';

export const TIMES: Scape[] = ['morning', 'day', 'golden', 'night'];

export interface Sky {
  chipBg: string;
  chipBorder: string;
  sky: string;
  sun: string;
  sunShadow: string;
  sunY: number;
  ink: string;
  inkSoft: string;
  inkInv: string;
  string: string;
  cloud: number;
  hills: [string, string, string];
  tree: string;
  trunk: string;
  lampHead: string;
  lampGlow: string;
  orb: string;
  stars: boolean;
  flies: boolean;
  shoot: boolean;
  reveal: string;
  scape: Scape;
  night: boolean;
}

const brand = 'linear-gradient(100deg,#FF4A57 10%,#B0408F 50%,#2D5BFF 90%)';
const warm = 'linear-gradient(100deg,#FFE7A0 10%,#FFC98A 50%,#FF9DB0 90%)';
const L = { chipBg: 'rgba(255,255,255,.55)', chipBorder: 'rgba(28,36,64,.16)' };
const D = { chipBg: 'rgba(255,255,255,.1)', chipBorder: 'rgba(255,255,255,.22)' };
const lampOn = 'radial-gradient(circle, rgba(255,226,150,.85) 0%, rgba(255,226,150,0) 70%)';
const SKIES: Record<string, Sky> = {
  morning: { ...L, sky: 'linear-gradient(180deg,#F4B79A 0%,#F9D3B4 42%,#FCEBD6 78%,#FFF4E6 100%)', sun: '#FFF1DA', sunShadow: '0 0 0 18px rgba(255,214,170,.55),0 0 0 48px rgba(255,196,150,.32),0 0 180px 40px rgba(255,196,150,.32)', sunY: 330, ink: '#1C2440', inkSoft: 'rgba(28,36,64,.82)', inkInv: '#FFF4E6', string: 'rgba(28,36,64,.5)', cloud: .9, hills: ['#A9C79B', '#78A982', '#4C8661'], tree: '#5E9470', trunk: '#5B4632', lampHead: '#F3EAD6', lampGlow: 'transparent', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'morning', night: false },
  day: { ...L, sky: 'linear-gradient(180deg,#6FA9EE 0%,#9CC8F5 45%,#CFE5FB 80%,#EEF6FF 100%)', sun: '#FFF6D8', sunShadow: '0 0 0 18px rgba(255,246,216,.55),0 0 0 48px rgba(255,240,190,.28),0 0 180px 40px rgba(255,240,190,.28)', sunY: 96, ink: '#14203F', inkSoft: 'rgba(20,32,63,.84)', inkInv: '#EEF6FF', string: 'rgba(20,32,63,.45)', cloud: .95, hills: ['#9CCB8C', '#62A56E', '#3B7F55'], tree: '#4F9461', trunk: '#5B4632', lampHead: '#F3EAD6', lampGlow: 'transparent', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'day', night: false },
  golden: { chipBg: 'rgba(255,255,255,.4)', chipBorder: 'rgba(42,24,56,.2)', sky: 'linear-gradient(180deg,#E9805B 0%,#F4A26C 38%,#F9C98C 72%,#FCE3B6 100%)', sun: '#FFE3A1', sunShadow: '0 0 0 18px rgba(255,214,140,.6),0 0 0 48px rgba(255,170,110,.32),0 0 180px 40px rgba(255,170,110,.32)', sunY: 370, ink: '#2A1838', inkSoft: 'rgba(42,24,56,.84)', inkInv: '#FCE3B6', string: 'rgba(42,24,56,.5)', cloud: .78, hills: ['#B7A66C', '#8E8B55', '#5E6B44'], tree: '#77784A', trunk: '#4E3A2A', lampHead: '#FFE3A1', lampGlow: 'rgba(255,214,140,.35)', orb: '', stars: false, flies: false, shoot: false, reveal: brand, scape: 'golden', night: false },
  night: { ...D, sky: 'linear-gradient(180deg,#0B1030 0%,#18205A 50%,#2C2F6E 85%,#3B3A78 100%)', sun: '#F2EEDC', sunShadow: 'none', sunY: 110, ink: '#F4EFE4', inkSoft: 'rgba(244,239,228,.86)', inkInv: '#0B1030', string: 'rgba(244,239,228,.42)', cloud: .14, hills: ['#2A3466', '#1F2853', '#151C3E'], tree: '#232D5C', trunk: '#141A38', lampHead: '#FFE7A0', lampGlow: lampOn, orb: 'moon', stars: true, flies: false, shoot: false, reveal: warm, scape: 'night', night: true },
  morningDark: { ...D, sky: 'linear-gradient(180deg,#121836 0%,#262B5C 42%,#5B4778 72%,#C9787A 92%,#F2A27E 100%)', sun: '#FFD9A8', sunShadow: '0 0 0 16px rgba(255,190,140,.25),0 0 120px 50px rgba(255,160,120,.35)', sunY: 600, ink: '#F6EFE6', inkSoft: 'rgba(246,239,230,.86)', inkInv: '#121836', string: 'rgba(246,239,230,.42)', cloud: .22, hills: ['#3A3F6E', '#2C3159', '#1E2344'], tree: '#2F3563', trunk: '#171B36', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFD9A8 10%,#FF9DB0 50%,#9DB4FF 90%)', scape: 'morning', night: true },
  dayDark: { ...D, sky: 'linear-gradient(180deg,#0D1422 0%,#1A2638 45%,#34445A 80%,#5E6E80 100%)', sun: '#0A0D15', sunShadow: '0 0 0 3px rgba(255,244,214,.95),0 0 36px 14px rgba(255,232,180,.6),0 0 140px 60px rgba(255,214,150,.22)', sunY: 110, ink: '#EEF1F6', inkSoft: 'rgba(238,241,246,.86)', inkInv: '#0D1422', string: 'rgba(238,241,246,.4)', cloud: .12, hills: ['#2E3B45', '#24303A', '#18222B'], tree: '#2A3640', trunk: '#121A21', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFF4D6 10%,#FFD27A 50%,#FFFFFF 90%)', scape: 'day', night: true },
  goldenDark: { ...D, sky: 'linear-gradient(180deg,#160F33 0%,#3A1E52 38%,#8A3A5E 68%,#E0685A 88%,#F59A62 100%)', sun: '#FFC27A', sunShadow: '0 0 0 16px rgba(255,160,110,.3),0 0 160px 60px rgba(255,120,90,.35)', sunY: 630, ink: '#FBEFE6', inkSoft: 'rgba(251,239,230,.86)', inkInv: '#160F33', string: 'rgba(251,239,230,.42)', cloud: .3, hills: ['#4A2D52', '#36213F', '#24162C'], tree: '#3E2747', trunk: '#1A1020', lampHead: '#FFE7A0', lampGlow: lampOn, orb: '', stars: true, flies: false, shoot: false, reveal: 'linear-gradient(100deg,#FFC27A 10%,#FF7A8A 50%,#B79CFF 90%)', scape: 'golden', night: true },
  nightDark: { ...D, sky: 'linear-gradient(180deg,#05071A 0%,#0D1236 55%,#1A1E4A 88%,#262A5C 100%)', sun: '#F7F3E3', sunShadow: 'none', sunY: 100, ink: '#F4EFE4', inkSoft: 'rgba(244,239,228,.86)', inkInv: '#05071A', string: 'rgba(244,239,228,.4)', cloud: .1, hills: ['#1B2250', '#141A40', '#0D122E'], tree: '#18204A', trunk: '#0A0E24', lampHead: '#FFE7A0', lampGlow: lampOn, orb: 'moon moon-bright', stars: true, flies: true, shoot: true, reveal: warm, scape: 'night', night: true }
};

const darkMQ = matchMedia('(prefers-color-scheme: dark)');
const listeners: ((sky: Sky) => void)[] = [];
let step: number | null = null;
let dark = darkMQ.matches;
let started = false;

function autoTime(): Scape {
  const h = new Date().getHours();
  return h >= 5 && h < 10 ? 'morning' : h >= 10 && h < 16 ? 'day' : h >= 16 && h < 20 ? 'golden' : 'night';
}

function timeKey(): Scape {
  return step !== null ? TIMES[step] : autoTime();
}

function currentSky(): Sky {
  return SKIES[timeKey() + (dark ? 'Dark' : '')];
}

function notify() {
  const sky = currentSky();
  listeners.forEach((listener) => listener(sky));
}

export function onSky(listener: (sky: Sky) => void) {
  listeners.push(listener);
  listener(currentSky());
  if (started) return;
  started = true;
  const onScheme = (e: MediaQueryListEvent) => { dark = e.matches; notify(); };
  if (darkMQ.addEventListener) darkMQ.addEventListener('change', onScheme); else darkMQ.addListener(onScheme);
  setInterval(() => { if (step === null) notify(); }, 30000);
}

export function nextSky() {
  const cur = TIMES.indexOf(timeKey()), now = TIMES.indexOf(autoTime()), next = (cur + 1) % 4;
  step = next === now && step !== null ? null : next;
  notify();
}
