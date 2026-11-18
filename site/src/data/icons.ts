import type { ImageMetadata } from 'astro';
import AfterHours from '../assets/icons/AfterHours.png';
import Grapefruit from '../assets/icons/Grapefruit.png';
import Opal from '../assets/icons/Opal.png';
import Original from '../assets/icons/Original.png';
import RainGlass from '../assets/icons/RainGlass.png';
import Recess from '../assets/icons/Recess.png';
import Sorbet from '../assets/icons/Sorbet.png';
import Terminal from '../assets/icons/Terminal.png';
import TracingPaper from '../assets/icons/TracingPaper.png';
import Twilight from '../assets/icons/Twilight.png';

export interface Icon {
  file: string;
  label: string;
  image: ImageMetadata;
}

export const ICONS: Icon[] = [
  { file: 'Original', label: 'Original', image: Original },
  { file: 'Sorbet', label: 'Sorbet', image: Sorbet },
  { file: 'Twilight', label: 'Twilight', image: Twilight },
  { file: 'RainGlass', label: 'Rain Glass', image: RainGlass },
  { file: 'Opal', label: 'Opal', image: Opal },
  { file: 'AfterHours', label: 'After Hours', image: AfterHours },
  { file: 'Recess', label: 'Recess', image: Recess },
  { file: 'TracingPaper', label: 'Tracing Paper', image: TracingPaper },
  { file: 'Grapefruit', label: 'Grapefruit', image: Grapefruit },
  { file: 'Terminal', label: 'Terminal', image: Terminal },
];
