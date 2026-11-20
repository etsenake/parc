export type SketchId = 'split' | 'peek' | 'commandbar' | 'easel' | 'notes' | 'capture' | 'mini' | 'crank' | 'archive' | 'shortcuts' | 'moving';

export interface Clip {
  video: string;
  poster: string;
}

export interface Specimen {
  id: SketchId;
  no: string;
  name: string;
  label: string;
  latin: string;
  line: string;
  behavior: string;
  habitat: string;
  spot: string;
  note: string;
  clip?: Clip;
}

const plates = import.meta.glob<string>('../assets/media/plates/{*.mp4,*.jpg}', { query: '?url', import: 'default', eager: true });

function filmed(name: string): Clip {
  const video = plates[`../assets/media/plates/${name}.mp4`];
  const poster = plates[`../assets/media/plates/${name}.jpg`];
  if (!video || !poster) throw new Error(`Missing plate clip: ${name}`);
  return { video, poster };
}

export const specimens: Specimen[] = [
  {
    id: 'split',
    no: '01',
    name: 'Split View',
    label: 'Split View',
    latin: 'Paginae duae',
    line: 'Up to four pages, in rows and columns.',
    behavior: 'Up to four pages, side by side, stacked, or both. Drag the edges, or make them all equal. Copy Links grabs the lot.',
    habitat: 'Comparing, copying, cross-checking.',
    spot: 'Option-click a link. Or drag a tab onto your page.',
    note: 'pairs for life.',
    clip: filmed('split'),
  },
  {
    id: 'peek',
    no: '02',
    name: 'Peek',
    label: 'Peek',
    latin: 'Prospectus brevis',
    line: 'Peek at a link. Fling it or keep it.',
    behavior: 'Links float over your page so you keep your place. Fling one away with two fingers, or keep it as a tab. Hover a tab in the sidebar and its card can Peek it too. Nothing reloads.',
    habitat: 'Links to other sites. Anything you Shift-click. Any tab’s preview card.',
    spot: 'A page floating up front while yours takes a polite step back.',
    note: 'springs back if you chicken out.',
    clip: filmed('peek'),
  },
  {
    id: 'commandbar',
    no: '03',
    name: 'Command Bar',
    label: 'the Command Bar',
    latin: 'Imperium clavis',
    line: '⌘T, then type anything.',
    behavior: 'Search, jump to a tab, or run a command. Click any address and it opens right there.',
    habitat: 'Dead centre.',
    spot: '⌘T.',
    note: 'loves a shortcut.',
    clip: filmed('commandbar'),
  },
  {
    id: 'easel',
    no: '04',
    name: 'Easels',
    label: 'Easels',
    latin: 'Tabula viva',
    line: 'A canvas where web pages still work.',
    behavior: 'Live web pages, screenshots, text and arrows on one canvas. The pages keep working.',
    habitat: 'Moodboards, research walls, trip plans.',
    spot: 'File → New Easel.',
    note: 'naps after four hours, like the rest of us.',
    clip: filmed('easel'),
  },
  {
    id: 'notes',
    no: '05',
    name: 'Notes',
    label: 'Notes',
    latin: 'Scriptura localis',
    line: 'Markdown notes that open like tabs.',
    behavior: 'Slash commands, a floating format bar, toggles, tables and math. All saved as plain Markdown files, in a folder you pick.',
    habitat: 'Next to whatever you’re reading.',
    spot: 'File → New Note, or any .md file.',
    note: 'keeps secrets.',
    clip: filmed('notes'),
  },
  {
    id: 'capture',
    no: '06',
    name: 'Capture',
    label: 'Capture',
    latin: 'Imago capta',
    line: 'Frame any part of a page.',
    behavior: 'Drag across any part of a page to capture it. Frame it in Portrait mode, then copy it, save it to your Library or drop it on an Easel.',
    habitat: 'Anything worth keeping.',
    spot: '⌘⇧2, then drag.',
    note: 'frames itself nicely.',
    clip: filmed('capture'),
  },
  {
    id: 'mini',
    no: '07',
    name: 'Mini Player',
    label: 'the Mini Player',
    latin: 'Musica pendens',
    line: 'Your video follows you to the sidebar.',
    behavior: 'Leave a playing tab and the controls follow you. One click to picture in picture, or send the sound to your speakers.',
    habitat: 'Music, talks, cooking videos.',
    spot: 'Leave a tab that’s playing.',
    note: 'follows you around, nicely.',
    clip: filmed('mini'),
  },
  {
    id: 'crank',
    no: '08',
    name: 'Window Frame',
    label: 'the Window Frame',
    latin: 'Margo versatilis',
    line: 'Crank the frame thick or thin.',
    behavior: 'Turn the crank to set the band of colour around your page, from 3 · Hairline to 13 · Gallery. Every window follows as you turn.',
    habitat: 'View → Adjust Window Frame…',
    spot: 'A car-window crank, right on your window.',
    note: 'goes up to thirteen.',
    clip: filmed('crank'),
  },
  {
    id: 'archive',
    no: '09',
    name: 'Archive',
    label: 'the Archive',
    latin: 'Tabulae dormientes',
    line: 'Nothing’s gone. Put it back.',
    behavior: 'Tabs you haven’t touched in 12 hours tuck themselves into the Archive. Put Back drops one right where it was.',
    habitat: 'Library → Archived Tabs.',
    spot: '“We cleaned up!”',
    note: 'nothing’s ever really gone.',
    clip: filmed('archive'),
  },
  {
    id: 'shortcuts',
    no: '11',
    name: 'Custom Shortcuts',
    label: 'Custom Shortcuts',
    latin: 'Claves propriae',
    line: 'Rebind anything.',
    behavior: 'Change any shortcut. When a site wants the same keys, you pick who wins. Your number pad gets its own.',
    habitat: 'Settings → Shortcuts.',
    spot: 'Your fingertips.',
    note: 'muscle memory included.',
  },
  {
    id: 'moving',
    no: '12',
    name: 'Moving In',
    label: 'Moving In',
    latin: 'Migratio facilis',
    line: 'Your Arc Spaces come too.',
    behavior: 'Your Arc Spaces, pinned tabs and Favorites move in the way you left them. Bookmarks, passwords and history come from Chrome, Safari, Firefox and the rest.',
    habitat: 'Your first five minutes.',
    spot: 'First launch.',
    note: 'travels light.',
  },
];
