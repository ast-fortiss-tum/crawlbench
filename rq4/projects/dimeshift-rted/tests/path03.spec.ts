import { test } from '@playwright/test';
import { Oracle } from './oracle';

test('path03', async ({ page }) => {
  const oracle = new Oracle(page, 'path03');
  await page.goto("http://localhost:3006/");
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.locator("xpath=/HTML[1]/BODY/DIV[1]/DIV[1]/DIV[1]/DIV[2]/UL[1]/LI[6]/A[1]").first().click();
  await page.waitForTimeout(1000);
  await oracle.check();
  await page.locator("[id=\"input_login\"]").first().fill("");
  await page.locator("[id=\"input_login\"]").first().pressSequentially("example");
  await page.locator("[id=\"input_email\"]").first().fill("");
  await page.locator("[id=\"input_email\"]").first().pressSequentially("example@example.com");
  await page.locator("[id=\"input_password\"]").first().fill("");
  await page.locator("[id=\"input_password\"]").first().pressSequentially("example123");
  await page.goto("http://localhost:3006/plans");
  await page.waitForTimeout(1000);
  await oracle.check();
  await oracle.finish();
});
