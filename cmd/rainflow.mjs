#!/usr/bin/env node
import { createReadStream } from 'node:fs'
import { pipeline } from 'node:stream/promises'

const usage = `Usage: node cmd/rainflow.mjs [--min-range R] [FILE|-]

Read one decimal sample per line from FILE or standard input. Blank lines are
ignored. Samples must be finite and in [-1e300, 1e300]; exponents are accepted.
Write cycles to stdout as CSV, with zero-based sample indices. A half_units
value of 1 is a half cycle and 2 is a full cycle. An error can follow partial CSV.

--min-range R  Emit only cycles with range >= R (default: 0). R must be a finite,
               nonnegative decimal in the input's units; exponents are accepted.
               Also accepts --min-range=R, before or after FILE. This filters
               output after counting; all samples still enter the counter.
`
const decimal = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/

function parseArgs(args) {
  let path
  let minRange = 0
  let hasMinRange = false
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--min-range' || arg.startsWith('--min-range=')) {
      if (hasMinRange) throw new Error('--min-range may only be specified once; see --help')
      const text = arg === '--min-range' ? args[++i] : arg.slice('--min-range='.length)
      const value = Number(text)
      if (!decimal.test(text ?? '') || !Number.isFinite(value) || value < 0) {
        throw new Error('--min-range requires a finite nonnegative decimal; see --help')
      }
      minRange = value
      hasMinRange = true
    } else {
      if (arg !== '-' && arg.startsWith('-')) throw new Error(`unknown option ${arg}; see --help`)
      if (path !== undefined) throw new Error('expected one input file; see --help')
      path = arg
    }
  }
  return { path: path ?? '-', minRange }
}

async function* lines(source) {
  let pending = ''
  for await (const chunk of source) {
    const parts = chunk.split('\n')
    if (parts.length === 1) {
      pending += chunk
      continue
    }
    yield pending + parts[0]
    for (let i = 1; i < parts.length - 1; i++) yield parts[i]
    pending = parts.at(-1)
  }
  if (pending.length) yield pending
}

async function main(args) {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
    process.stdout.write(usage)
    return
  }
  const { path, minRange } = parseArgs(args)

  const bridge = await import('../_build/js/release/build/cmd/bridge/bridge.js').catch((error) => {
    if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error
    throw new Error('build the CLI first with: moon build --target js --release cmd/bridge')
  })
  const input = path === '-' ? process.stdin : createReadStream(path)
  input.setEncoding('utf8')
  await pipeline(input, async function* (source) {
    const counter = bridge.newCounter()
    let csv = ''
    const emit = (start, end, range, mean, halfUnits) => {
      if (range < minRange) return
      csv += `${start},${end},${range},${mean},${halfUnits}\n`
    }
    yield 'start_index,end_index,range,mean,half_units\n'
    let lineNumber = 0
    for await (const line of lines(source)) {
      lineNumber++
      const text = line.trim()
      if (!text) continue
      const value = Number(text)
      if (!decimal.test(text) || !Number.isFinite(value) || Math.abs(value) > 1e300) {
        throw new Error(`line ${lineNumber}: expected one finite decimal in [-1e300, 1e300]`)
      }
      if (!bridge.pushSample(counter, value, emit)) {
        throw new Error(`line ${lineNumber}: counter rejected the sample`)
      }
      if (csv) {
        yield csv
        csv = ''
      }
    }
    bridge.finishCounter(counter, emit)
    if (csv) yield csv
  }, process.stdout)
}

main(process.argv.slice(2)).catch((error) => {
  console.error(`rainflow: ${error.message}`)
  process.exitCode = 1
})
