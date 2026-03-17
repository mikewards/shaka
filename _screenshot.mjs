import { chromium } from 'playwright';

const dir = '_shots';
const layers = ['currents', 'wind', 'waves', 'sst', 'salinity', 'chlorophyll', 'phytoplankton', 'zooplankton'];

async function run() {
  const browser = await chromium.launch({ headless: false, args: ['--use-gl=angle'] });
  const page = await browser.newPage({ viewport: { width: 1024, height: 720 } });
  await page.goto('http://127.0.0.1:8765/test_particle_final.html', { waitUntil: 'networkidle' });
  await page.waitForTimeout(8000);

  for (const layer of layers) {
    console.log(`Switching to ${layer}...`);
    await page.evaluate((k) => switchLayer(k), layer);
    await page.waitForTimeout(5000);
    await page.screenshot({ path: `${dir}/${layer}.png` });
    console.log(`Saved ${layer}.png`);
  }

  await browser.close();
  console.log('Done');
}

run();
