export type AccountKey = 'w' | 'h';

export interface Account {
  who: string;
  av: string;
}

export interface Space {
  name: string;
  color: string;
  tint: string;
  url: string;
  title: string;
  account: AccountKey;
  note: number;
  pins: string[];
  today: string[];
}

export const SPACES: Space[] = [
  { name: 'Work', color: '#3D63F0', tint: '#E3E8FC', url: 'docs.yourcompany.com/q4', title: 'Q4 planning', account: 'w', note: 659.25, pins: ['R', 'I', 'C', 'D'], today: ['Q4 planning doc', 'Design review notes', 'Team calendar', 'Release checklist'] },
  { name: 'Home', color: '#C4502E', tint: '#FBE4D9', url: 'recipes.example/sunday-roast', title: 'Sunday roast', account: 'h', note: 587.33, pins: ['G', 'B', 'R', 'S'], today: ['Sunday roast recipe', 'Furnace filter sizes', 'Flights to Lisbon', 'Library holds'] },
  { name: 'Side quest', color: '#237A51', tint: '#DCEFE3', url: 'forum.example/pottery', title: 'Pottery wheel notes', account: 'h', note: 783.99, pins: ['P', 'S', 'B', 'M'], today: ['Pottery wheel reviews', 'Synth patch ideas', 'Weekend bike route', 'Sourdough schedule'] },
  { name: 'Late reading', color: '#7550E6', tint: '#E9E3FB', url: 'longreads.example/maps', title: 'A short history of maps', account: 'h', note: 880, pins: ['E', 'P', 'A', 'L'], today: ['A short history of maps', 'An essay on public gardens', 'Poetry archive', 'Saved for the weekend'] },
];

export const ACCOUNTS: Record<AccountKey, Account> = {
  w: { who: 'you@yourcompany.com', av: '#18203A' },
  h: { who: 'you@yourmail.com', av: '#E0803A' },
};
