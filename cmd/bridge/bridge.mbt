///|
#export_name("newCounter")
pub fn new_counter() -> @rain.Counter {
  @rain.Counter::new()
}

///|
fn emit_cycles(
  cycles : Array[@rain.Cycle],
  emit : (Int64, Int64, Double, Double, Int32) -> Unit,
) -> Unit {
  for cycle in cycles {
    emit(
      cycle.start_index,
      cycle.end_index,
      cycle.range,
      cycle.mean,
      cycle.half_units,
    )
  }
}

///|
#export_name("pushSample")
pub fn push_sample(
  counter : @rain.Counter,
  sample : Double,
  emit : (Int64, Int64, Double, Double, Int32) -> Unit,
) -> Bool {
  let cycles = counter.push(sample) catch { _ => return false }
  emit_cycles(cycles, emit)
  true
}

///|
#export_name("finishCounter")
pub fn finish_counter(
  counter : @rain.Counter,
  emit : (Int64, Int64, Double, Double, Int32) -> Unit,
) -> Unit {
  emit_cycles(counter.finish(), emit)
}
