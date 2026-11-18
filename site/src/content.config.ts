import { defineCollection } from 'astro:content';
import { file } from 'astro/loaders';
import { z } from 'astro/zod';

const releases = defineCollection({
  loader: file('../release-notes.json', {
    parser: (text) => JSON.parse(text).releases.map((release: { version: string }) => ({ id: release.version, ...release })),
  }),
  schema: z.object({
    version: z.string(),
    build: z.number().optional(),
    date: z.string(),
    changes: z.array(z.object({
      type: z.string(),
      scope: z.string().nullable(),
      summary: z.string(),
      breaking: z.boolean(),
    })),
  }),
});

export const collections = { releases };
