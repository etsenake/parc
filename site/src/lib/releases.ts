import { getCollection, type CollectionEntry } from 'astro:content';

export type Release = CollectionEntry<'releases'>['data'];
type Change = Release['changes'][number];

const GROUPS = [['breaking', 'Heads up'], ['feat', 'New'], ['fix', 'Fixed'], ['perf', 'Faster']] as const;

function newestFirst(a: Release, b: Release): number {
  const left = a.version.split('.').map(Number), right = b.version.split('.').map(Number);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const delta = (right[i] ?? 0) - (left[i] ?? 0);
    if (delta) return delta;
  }
  return 0;
}

export async function latestRelease(): Promise<Release | undefined> {
  const releases = (await getCollection('releases')).map((entry) => entry.data);
  return releases.sort(newestFirst)[0];
}

function members(changes: Change[], key: string): Change[] {
  return changes.filter((change) => key === 'breaking' ? change.breaking : !change.breaking && change.type === key);
}

export function glance(changes: Change[]): string {
  return GROUPS.map(([key, title]) => ({ key, title, count: members(changes, key).length }))
    .filter(({ count }) => count)
    .map(({ key, title, count }) => key === 'breaking' ? title : `${count} ${title.toLowerCase()}`)
    .join(' · ');
}

export function longDate(value: string): string {
  const [year, month, day] = value.split('-').map(Number);
  const name = new Date(Date.UTC(year, month - 1, day)).toLocaleString('en-US', { month: 'long', timeZone: 'UTC' });
  return `${name} ${day}, ${year}`;
}

export function display(summary: string): string {
  const word = summary.split(' ', 1)[0];
  return word.toLowerCase() === word && word.toUpperCase() !== word ? summary.charAt(0).toUpperCase() + summary.slice(1) : summary;
}

export function scopeLabel(scope: string | null): string {
  if (!scope) return '';
  const words = scope.replaceAll('-', ' ');
  return words.charAt(0).toUpperCase() + words.slice(1).toLowerCase();
}

export function highlights(release: Release): Change[] {
  const notable = release.changes.filter((change) => !change.breaking && ['feat', 'fix', 'perf'].includes(change.type));
  const features = notable.filter((change) => change.type === 'feat').slice(0, 3);
  return features.length ? features : notable.slice(0, 3);
}
