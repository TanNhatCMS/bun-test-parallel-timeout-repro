import { test } from 'bun:test'

test('async setTimeout(0) alloc loop should be terminated by --timeout', async () => {
  const retained: unknown[] = []
  await new Promise<never>(() => {
    const tick = () => {
      for (let i = 0; i < 200; i++) {
        retained.push(new Array(1024).fill(1))
      }
      setTimeout(tick, 0)
    }
    tick()
  })
})
