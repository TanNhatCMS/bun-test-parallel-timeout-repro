import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { expect, mock, test } from 'bun:test'

const depPath = path.join(import.meta.dir, 'dep.ts')
const depActualUrl = `${pathToFileURL(depPath).href}?bun-actual`

mock.module('./dep.ts', async () => {
  const actual = await import(depActualUrl)
  return {
    ...actual,
    Comp: () => `wrapped:${actual.Comp?.()}`,
  }
})

test('mock.module factory importing file:// URL with ?bun-actual should load real exports', async () => {
  const mod = await import('./dep')
  expect(typeof mod.Comp).toBe('function')
  expect(mod.Comp()).toBe('wrapped:real')
})
