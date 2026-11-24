///|
fn demo() -> Unit raise @rain.RainError {
  let counter = @rain.Counter::new()
  let spectrum = @rain.Spectrum::new([0.0, 4.0, 8.0], [-1.0, 0.0, 1.0])
  let summary = @rain.CycleSummary::new()
  let mut records = 0
  fn consume(rows : Array[@rain.Cycle]) -> Unit raise @rain.RainError {
    summary.add_chunk(rows)
    spectrum.add_chunk(rows)
    for c in rows {
      records += 1
      println(
        "  samples \{c.start_index}..\{c.end_index}: range=\{c.range} mean=\{c.mean} cycles=\{c.half_units.to_double() / 2.0}",
      )
    }
  }
  println("Nine load samples, arriving in three blocks:")
  for block in [[-2.0, 1.0, -3.0], [5.0, -1.0], [3.0, -4.0, 4.0, -2.0]] {
    consume(counter.push_chunk(block))
  }
  consume(counter.finish())
  println(
    "\{records} records; \{spectrum.total_units().to_double() / 2.0} equivalent cycles",
  )
  println("Matrix in half-cycle units (rows: range; columns: mean):")
  for row in spectrum.matrix() {
    println("  [\{row[0]}, \{row[1]}]")
  }
  println("Outside grid: \{spectrum.outside_units()} half-cycle unit(s)")
  let ranges = spectrum.range_units()
  let means = spectrum.mean_units()
  println("Range totals in half-cycle units: [\{ranges[0]}, \{ranges[1]}]")
  println("Mean totals in half-cycle units: [\{means[0]}, \{means[1]}]")
  println("Cycle summary CSV:")
  println(summary.snapshot().to_csv())
  let coarse = spectrum.coarsen([0.0, 8.0], [-1.0, 1.0])
  println(
    "Coarsened spectrum CSV (outside: \{coarse.outside_units()} half unit):",
  )
  println(coarse.to_csv())
  let live = @rain.Counter::new()
  let confirmed = live.push_chunk([0.0, 5.0, 1.0])
  let preview = live.preview_finish()
  println("Live preview [0, 5, 1]: \{preview.length()} provisional half cycles")
  confirmed.append(live.push(6.0))
  confirmed.append(live.finish())
  println(
    "After appending 6: range=\{confirmed[0].range} cycles=\{confirmed[0].half_units.to_double() / 2.0}; range=\{confirmed[1].range} cycles=\{confirmed[1].half_units.to_double() / 2.0}",
  )
}

///|
fn main {
  demo() catch {
    e => abort("invalid built-in example: \{e}")
  }
}
