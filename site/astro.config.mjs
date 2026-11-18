import { defineConfig, fontProviders } from 'astro/config';

export default defineConfig({
  site: 'https://parcbrowser.com',
  outDir: '../build/site',
  scopedStyleStrategy: 'where',
  compressHTML: false,
  build: { assets: 'assets' },
  fonts: [
    {
      provider: fontProviders.local(),
      name: 'Instrument Sans',
      cssVariable: '--font-instrument-sans',
      fallbacks: ['system-ui', '-apple-system', 'sans-serif'],
      options: { variants: [{ src: ['./src/assets/fonts/InstrumentSans.woff2'], weight: '400 700', style: 'normal' }] },
    },
    {
      provider: fontProviders.local(),
      name: 'Instrument Serif',
      cssVariable: '--font-instrument-serif',
      fallbacks: ['Georgia', 'serif'],
      options: {
        variants: [
          { src: ['./src/assets/fonts/InstrumentSerif.woff2'], weight: 400, style: 'normal' },
          { src: ['./src/assets/fonts/InstrumentSerif-Italic.woff2'], weight: 400, style: 'italic' },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'Caveat',
      cssVariable: '--font-caveat',
      fallbacks: ['cursive'],
      options: { variants: [{ src: ['./src/assets/fonts/Caveat-600.woff2'], weight: 600, style: 'normal' }] },
    },
    {
      provider: fontProviders.local(),
      name: 'JetBrains Mono',
      cssVariable: '--font-jetbrains-mono',
      fallbacks: ['ui-monospace', 'monospace'],
      options: { variants: [{ src: ['./src/assets/fonts/JetBrainsMono.woff2'], weight: '500 600', style: 'normal' }] },
    },
  ],
});
