import { chromium } from 'playwright';

const dir = '_shots';

async function run() {
  const browser = await chromium.launch({ headless: false, args: ['--use-gl=angle'] });
  const page = await browser.newPage({ viewport: { width: 1024, height: 720 } });
  await page.goto('http://127.0.0.1:8765/test_particle_final.html', { waitUntil: 'networkidle' });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: `${dir}/01_overview.png` });
  console.log('Saved 01_overview.png');

  await page.waitForTimeout(3000);
  console.log('ready');

  await page.evaluate(() => { map.jumpTo({ center: [-81, 27], zoom: 6 }); });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${dir}/02_florida.png` });
  console.log('Saved 02_florida.png');

  await page.evaluate(() => { map.jumpTo({ center: [-87, 44], zoom: 6 }); });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${dir}/03_great_lakes.png` });
  console.log('Saved 03_great_lakes.png');

  await page.evaluate(() => { map.jumpTo({ center: [-122.4, 37.8], zoom: 8 }); });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${dir}/04_sf_bay.png` });
  console.log('Saved 04_sf_bay.png');

  await browser.close();
  console.log('Done');
}

run();
