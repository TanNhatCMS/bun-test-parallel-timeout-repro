import { test } from 'bun:test'

test('sync cpu loop should be terminated by --timeout', () => {
  while (true) {}
})
