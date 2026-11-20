import { test } from 'bun:test'

test('sync allocation loop should be terminated by --timeout', () => {
  const retained: unknown[] = []
  let node: Record<string, unknown> = {}
  while (true) {
    node = { next: node, payload: new Array(1024).fill(1) }
    retained.push(node)
  }
})
