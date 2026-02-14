#!/usr/bin/env node
/**
 * Generate Dromos app icon PNGs (1024x1024) and in-app logo from SVG paths.
 */
import sharp from 'sharp';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(__dirname, '..');
const ICON_DIR = path.join(PROJECT, 'Dromos/Dromos/Assets.xcassets/AppIcon.appiconset');
const LOGO_DIR = path.join(PROJECT, 'Dromos/Dromos/Assets.xcassets/DromosLogo.imageset');

const SIZE = 1024;

const logoPaths = (fill) => `
<path d="M260.25 45.44L198.08 107.61L166.99 76.52C157.64 67.17 142.47 67.17 133.12 76.52L91.25 118.39C81.9 127.74 81.9 142.91 91.25 152.26L112.44 173.45L184.54 101.35C193.89 92 209.06 92 218.41 101.35L249.5 132.44L311.67 70.27C321.02 60.92 321.02 45.75 311.67 36.4L290.48 15.21C281.13 5.86 265.96 5.86 256.61 15.21L225.52 46.3L260.25 45.44Z" fill="${fill}"/>
<path d="M294.12 79.31L231.95 141.48L200.86 110.39C191.51 101.04 176.34 101.04 166.99 110.39L125.12 152.26C115.77 161.61 115.77 176.78 125.12 186.13L146.31 207.32L218.41 135.22C227.76 125.87 242.93 125.87 252.28 135.22L283.37 166.31L345.54 104.14C354.89 94.79 354.89 79.62 345.54 70.27L324.35 49.08C315 39.73 299.83 39.73 290.48 49.08L259.39 80.17L294.12 79.31Z" fill="${fill}"/>
<path d="M327.99 113.18L265.82 175.35L234.73 144.26C225.38 134.91 210.21 134.91 200.86 144.26L158.99 186.13C149.64 195.48 149.64 210.65 158.99 220L180.18 241.19L252.28 169.09C261.63 159.74 276.8 159.74 286.15 169.09L317.24 200.18L379.41 138.01C388.76 128.66 388.76 113.49 379.41 104.14L358.22 82.95C348.87 73.6 333.7 73.6 324.35 82.95L293.26 114.04L327.99 113.18Z" fill="${fill}"/>
`;

// The logo viewBox is 500x300. We want to center it in 1024x1024 with padding.
// Scale the logo to fit ~65% of the icon width for good visual balance.
const LOGO_SCALE = (SIZE * 0.65) / 500; // scale factor
const LOGO_W = Math.round(500 * LOGO_SCALE);
const LOGO_H = Math.round(300 * LOGO_SCALE);
const OFFSET_X = Math.round((SIZE - LOGO_W) / 2);
const OFFSET_Y = Math.round((SIZE - LOGO_H) / 2);

function makeSvg(fill, bgColor) {
  return Buffer.from(`<svg width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" xmlns="http://www.w3.org/2000/svg">
  ${bgColor ? `<rect width="${SIZE}" height="${SIZE}" fill="${bgColor}"/>` : ''}
  <g transform="translate(${OFFSET_X}, ${OFFSET_Y}) scale(${LOGO_SCALE})">
    ${logoPaths(fill)}
  </g>
</svg>`);
}

async function generateIcon(fill, bgColor, outputPath, flatten = true) {
  let pipeline = sharp(makeSvg(fill, bgColor), { density: 300 })
    .resize(SIZE, SIZE);
  if (flatten) {
    pipeline = pipeline.flatten({ background: bgColor || '#000000' }).png();
  } else {
    pipeline = pipeline.png();
  }
  await pipeline.toFile(outputPath);
  console.log(`  Created: ${path.basename(outputPath)}`);
}

async function generateTemplateLogo(outputPath) {
  // Render at 500x300 native size for a crisp in-app image
  const svg = Buffer.from(`<svg width="500" height="300" viewBox="0 0 500 300" xmlns="http://www.w3.org/2000/svg">
    ${logoPaths('black')}
  </svg>`);
  await sharp(svg, { density: 300 })
    .resize(500, 300)
    .png()
    .toFile(outputPath);
  console.log(`  Created: ${path.basename(outputPath)}`);
}

async function main() {
  const fs = await import('fs');
  fs.mkdirSync(ICON_DIR, { recursive: true });
  fs.mkdirSync(LOGO_DIR, { recursive: true });

  console.log('Generating app icons (1024x1024)...');
  // Light: white logo on brand green
  await generateIcon('white', '#009B77', path.join(ICON_DIR, 'AppIcon-light.png'));
  // Dark: white logo on black
  await generateIcon('white', '#000000', path.join(ICON_DIR, 'AppIcon-dark.png'));
  // Tinted: black logo on transparent (no flatten)
  await generateIcon('black', null, path.join(ICON_DIR, 'AppIcon-tinted.png'), false);

  console.log('\nGenerating in-app logo...');
  await generateTemplateLogo(path.join(LOGO_DIR, 'DromosLogo.png'));

  console.log('\nDone!');
}

main().catch(console.error);
