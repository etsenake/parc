export function $<E extends Element = HTMLElement>(selector: string, root: ParentNode = document): E {
  return root.querySelector<E>(selector)!;
}

export function $$<E extends Element = HTMLElement>(selector: string, root: ParentNode = document): E[] {
  return [...root.querySelectorAll<E>(selector)];
}

export function el<K extends keyof HTMLElementTagNameMap>(tag: K, className?: string, text?: string): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.classList.add(...className.split(' ').filter(Boolean));
  if (text !== undefined) node.textContent = text;
  return node;
}

export const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

export function remember(key: string, value?: string): string | null {
  try {
    if (value === undefined) return localStorage.getItem(key);
    localStorage.setItem(key, value);
  } catch {}
  return null;
}
