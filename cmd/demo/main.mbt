///|
fn demo() -> Unit raise @rain.RainError {
  let counter = @rain.Counter::new()
  let spectrum = @rain.Spectrum::new([0.0, 4.0, 8.0], [-1.0, 0.0, 1.0])
  let mut records = 0
  fn consume(rows : Array[@rain.Cycle]) -> Unit raise @rain.RainError {
    for c in rows {
      records += 1
      spectrum.add(c)
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
}

///|
fn main {
  demo() catch {
    e => abort("invalid built-in example: \{e}")
  }
}
