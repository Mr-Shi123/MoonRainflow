import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const paths = execFileSync('git', [
  'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', '*.mbt',
], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean)
const rows = [...new Set(paths)].sort().map(path => {
  const lines = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8').split(/\r?\n/)
  if (lines.at(-1) === '') lines.pop()
  return {
    path,
    kind: /_(?:test|wbtest|bbtest)\.mbt$/.test(path) ? 'test' : path.includes('/') ? 'command' : 'core',
    physical: lines.length,
    code: lines.filter(line => line.trim() && !line.trimStart().startsWith('//')).length,
  }
})

console.log('MoonBit source size: nonblank physical lines excluding // comments.')
console.log('Tests and commands/examples are excluded from the core-library minimum.')
console.log('Generated .mbti interfaces, build output and dependencies are excluded.')
console.log('kind\tphysical\tcode\tfile')
for (const row of rows) console.log(`${row.kind}\t${row.physical}\t${row.code}\t${row.path}`)
const core = rows.filter(row => row.kind === 'core').reduce((sum, row) => sum + row.code, 0)
const production = rows.filter(row => row.kind !== 'test').reduce((sum, row) => sum + row.code, 0)
console.log(`Core library code lines: ${core}`)
console.log(`All production MoonBit code lines: ${production}`)
if (core < 500) {
  console.error(`Core library requires at least 500 code lines; found ${core}.`)
  process.exitCode = 1
}
