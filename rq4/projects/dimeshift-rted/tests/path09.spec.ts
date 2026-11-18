import { test } from '@playwright/test';
import { Oracle } from './oracle';

test('path09', async ({ page }) => {
  const oracle = new Oracle(page, 'path09');
  await page.goto("http://localhost:3006/");
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.locator("xpath=/HTML[1]/BODY/DIV[1]/DIV[1]/DIV[1]/DIV[2]/UL[1]/LI[7]/A[1]").first().click();
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.locator("[name=\"username\"]").first().fill("");
  await page.locator("[name=\"username\"]").first().pressSequentially("example");
  await page.locator("[id=\"input_password\"]").first().fill("");
  await page.locator("[id=\"input_password\"]").first().pressSequentially("example123");
  await page.goto("http://localhost:3006/user/registration");
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.goto("http://localhost:3006/user/signin");
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.goto("http://localhost:3006/profile");
  await page.waitForTimeout(1000);
  await oracle.check();
  await oracle.finish();
});
