import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { expect, test } from 'bun:test'

test('file:// URL with distinct searchParams should evaluate a fresh module instance', async () => {
  const p = path.join(import.meta.dir, 'counter-dep.ts')
  const fileBase = pathToFileURL(p).href

  const mRel = await import('./counter-dep.ts')
  const mFileQ1 = await import(`${fileBase}?q=1`)
  const mFileQ2 = await import(`${fileBase}?q=2`)
  const mRelQ1 = await import('./counter-dep.ts?q=1')

  // Relative specifier with query evaluates separately as expected:
  expect(mRelQ1).not.toBe(mRel)
  expect(mRelQ1.loadCount).toBe(2)

  // Bug on Bun 1.4.5: file:// URLs ignore searchParams and return the cached mRel:
  expect(mFileQ1).not.toBe(mRel)
  expect(mFileQ2).not.toBe(mFileQ1)
})
