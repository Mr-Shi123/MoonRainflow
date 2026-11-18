import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const cli = fileURLToPath(new URL('../cmd/rainflow.mjs', import.meta.url))
const sample = fileURLToPath(new URL('../examples/mathworks-nine.txt', import.meta.url))
// Reference: MathWorks, "Cycle Counts with Known Sample Rate". The nine reversals
// occur one second apart. Their timestamps are our zero-based sample indices.
// https://www.mathworks.com/help/signal/ref/rainflow.html
const expected = readFileSync(new URL('../examples/mathworks-nine.cycles.csv', import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n')

function run(args, input = '') {
  const result = spawnSync(process.execPath, [cli, ...args], { input, encoding: 'utf8' })
  assert.ifError(result.error)
  return result
}

test('file input reproduces all seven reference cycles', () => {
  const result = run([sample])
  assert.equal(result.status, 0, result.stderr)
  assert.equal(result.stdout, expected)
})

test('stdin accepts blank lines, CRLF and an unterminated final line', () => {
  const input = readFileSync(sample, 'utf8').trim().split(/\r?\n/).join('\r\n \t\r\n')
  for (const args of [[], ['-']]) {
    const result = run(args, input)
    assert.equal(result.status, 0, result.stderr)
    assert.equal(result.stdout, expected)
  }
})

test('decimals and scientific notation produce an exact half cycle', () => {
  const result = run([], ' +.5e1 \n -1.50\n')
  assert.equal(result.status, 0, result.stderr)
  assert.equal(result.stdout.split('\n')[1], '0,1,6.5,1.75,1')
})

test('minimum range filters counted cycles inclusively without changing indices or weights', () => {
  const filtered = expected.replace('0,1,3,-0.5,1\n', '')
  const input = readFileSync(sample, 'utf8')
  for (const args of [
    ['--min-range', '4', sample],
    [sample, '--min-range=4'],
    ['--min-range', '+4e0'],
    ['-', '--min-range=4'],
  ]) {
    const result = run(args, input)
    assert.equal(result.status, 0, result.stderr)
    assert.equal(result.stdout, filtered)
  }
})

test('zero minimum preserves all cycles and an above-maximum minimum keeps the CSV header', () => {
  const all = run(['--min-range=0', sample])
  assert.equal(all.status, 0, all.stderr)
  assert.equal(all.stdout, expected)
  const none = run(['--min-range', '10', sample])
  assert.equal(none.status, 0, none.stderr)
  assert.equal(none.stdout, 'start_index,end_index,range,mean,half_units\n')
})

test('invalid or repeated minimum range options fail before writing CSV', () => {
  const invalidArgs = [
    ['--min-range'],
    ['--min-range='],
    ['--min-range', '--help'],
    ['--min-range', '0', '--min-range=1'],
    ...['-1', 'NaN', 'Infinity', '1e309', '0x10', '1,2'].map(value => ['--min-range', value]),
  ]
  for (const args of invalidArgs) {
    const result = run(args)
    assert.equal(result.status, 1)
    assert.equal(result.stdout, '')
    assert.match(result.stderr, /--min-range/)
    assert.doesNotMatch(result.stderr, /\n\s+at /)
  }
  const multiple = run(['--min-range', '0', sample, sample])
  assert.equal(multiple.status, 1)
  assert.equal(multiple.stdout, '')
  assert.match(multiple.stderr, /one input file/)
})

test('range filtering still validates every input sample', () => {
  const result = run(['--min-range', '10'], '0\n1\nbad\n')
  assert.equal(result.status, 1)
  assert.match(result.stderr, /line 3\b/i)
})

test('malformed or out-of-range samples identify the physical line', () => {
  for (const sample of ['1,2', 'Infinity', 'NaN', '1e301', '-1.1e300', '0x12']) {
    const result = run(['-'], `1\n\n${sample}\n`)
    assert.equal(result.status, 1)
    assert.match(result.stderr, /line 3\b/i)
    assert.doesNotMatch(result.stderr, /\n\s+at /)
  }
})

test('bad paths and options report an error; help prints usage', () => {
  const missing = run([sample + '.absent'])
  assert.equal(missing.status, 1)
  assert.match(missing.stderr, /mathworks-nine\.txt\.absent/)
  assert.doesNotMatch(missing.stderr, /\n\s+at /)
  const option = run(['--unknown'])
  assert.equal(option.status, 1)
  assert.match(option.stderr, /--unknown/)
  const help = run(['--help'])
  assert.equal(help.status, 0, help.stderr)
  assert.match(help.stdout, /stdin|standard input/i)
  assert.match(help.stdout, /--min-range/)
})

test('a confirmed cycle reaches stdout while stdin is still open', { timeout: 10000 }, async (t) => {
  const child = spawn(process.execPath, [cli], { stdio: ['pipe', 'pipe', 'pipe'] })
  t.after(() => child.kill())
  child.stdout.setEncoding('utf8')
  child.stdin.write('-2\n1\n-3\n5\n')
  let csv = ''
  for await (const chunk of child.stdout) {
    csv += chunk
    if (csv.includes('0,1,3,-0.5,1\n')) return
  }
  assert.fail('first half cycle was missing before EOF')
})

test('minimum range preserves streaming output before stdin closes', { timeout: 10000 }, async (t) => {
  const child = spawn(process.execPath, [cli, '--min-range', '4'], { stdio: ['pipe', 'pipe', 'pipe'] })
  t.after(() => child.kill())
  child.stdout.setEncoding('utf8')
  child.stdin.write('-2\n1\n-3\n5\n-1\n')
  let csv = ''
  for await (const chunk of child.stdout) {
    csv += chunk
    assert.ok(!csv.includes('0,1,3,-0.5,1\n'), 'below-threshold cycle was emitted')
    if (csv.includes('1,2,4,-1,1\n')) return
  }
  assert.fail('matching half cycle was missing before EOF')
})
