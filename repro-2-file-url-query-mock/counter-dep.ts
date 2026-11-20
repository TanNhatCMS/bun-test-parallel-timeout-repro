const g = globalThis as any
g.__depLoadCount = (g.__depLoadCount ?? 0) + 1
export const loadCount = g.__depLoadCount
export const obj = { id: loadCount }
