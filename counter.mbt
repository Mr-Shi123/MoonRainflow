///|
/// A counted excursion. half_units = 1 for a half cycle, 2 for a full
/// cycle. Both indices refer to the original samples, before peak filtering.
#derive(Eq)
pub struct Cycle {
  start_index : Int64
  end_index : Int64
  range : Double
  mean : Double
  half_units : Int32
}

///|
pub extend Cycle with Eq::{equal, not_equal}

///|
/// InvalidSample carries the zero-based index in the complete history.
pub(all) suberror RainError {
  InvalidSample(Int64)
  ClosedCounter
  IndexLimit
  InvalidEdges(String)
  CountLimit
}

///|
/// Human-readable messages for command line clients and data import logs.
pub impl Show for RainError with fn output(self, logger) {
  match self {
    InvalidSample(i) =>
      logger.write_string(
        "invalid load at sample \{i}; expected a finite value in [-1e300, 1e300]",
      )
    ClosedCounter => logger.write_string("cannot append after finish")
    IndexLimit => logger.write_string("sample index exceeds the Int64 limit")
    InvalidEdges(detail) => logger.write_string(detail)
    CountLimit =>
      logger.write_string("half-cycle count exceeds the Int64 limit")
  }
}

///|
pub extend RainError with Show::{to_string, output}

///|
priv struct Point {
  index : Int64
  value : Double
}

///|
/// A counter for one continuous record. Call finish only at end of input.
pub struct Counter {
  priv stack : Array[Point]
  priv mut candidate : Point?
  priv mut trend : Int32
  priv mut next_index : Int64
  priv mut closed : Bool
}

///|
pub fn Counter::new() -> Counter {
  { stack: [], candidate: None, trend: 0, next_index: 0L, closed: false, }
}

///|
fn counted(a : Point, b : Point, units : Int32) -> Cycle {
  {
    start_index: a.index,
    end_index: b.index,
    range: (a.value - b.value).abs(),
    mean: (a.value + b.value) / 2.0,
    half_units: units,
  }
}

///|
// Closing the most recent two ranges only touches the tail. The special
// left-boundary case always has exactly three points, so there is no shift
// of a long prefix. Each reversal is pushed once and removed at most once.
fn Counter::reversal(self : Counter, point : Point, out : Array[Cycle]) -> Unit {
  let s = self.stack
  s.push(point)
  while s.length() >= 3 {
    let n = s.length()
    let a = s[n - 3]
    let b = s[n - 2]
    let c = s[n - 1]
    // Consecutive reversals alternate, so A and C are on the same side of B.
    // Compare their positions directly: subtracting B can round two unequal
    // ranges to the same Double and prematurely close a high-dynamic-range pair.
    if (b.value > a.value && c.value > a.value) ||
      (b.value < a.value && c.value < a.value) {
      break
    }
    if n == 3 {
      out.push(counted(a, b, 1))
      s[0] = b
      s[1] = c
      s.truncate(2)
    } else {
      out.push(counted(a, b, 2))
      s[n - 3] = c
      s.truncate(n - 2)
    }
  }
}

///|
fn Counter::accept(self : Counter, x : Double, out : Array[Cycle]) -> Unit {
  let p : Point = { index: self.next_index, value: x, }
  self.next_index += 1L
  match self.candidate {
    None => self.candidate = Some(p)
    Some(previous) => {
      if x == previous.value {
        return
      }
      let direction = if x > previous.value { 1 } else { -1 }
      if self.trend != direction {
        self.reversal(previous, out)
      }
      self.trend = direction
      self.candidate = Some(p)
    }
  }
}

///|
fn check_value(x : Double, index : Int64) -> Unit raise RainError {
  guard x >= -1.0e300 && x <= 1.0e300 else { raise InvalidSample(index) }
}

///|
/// Accept one sample, returning only newly settled cycles.
pub fn Counter::push(
  self : Counter,
  x : Double,
) -> Array[Cycle] raise RainError {
  guard !self.closed else { raise ClosedCounter }
  guard self.next_index < 9223372036854775807L else { raise IndexLimit }
  check_value(x, self.next_index)
  let out = []
  self.accept(x, out)
  out
}

///|
/// Atomic append: on error no samples from this chunk have been consumed.
pub fn Counter::push_chunk(
  self : Counter,
  xs : ArrayView[Double],
) -> Array[Cycle] raise RainError {
  guard !self.closed else { raise ClosedCounter }
  guard xs.length().to_int64() <= 9223372036854775807L - self.next_index else {
    raise IndexLimit
  }
  for i, x in xs {
    check_value(x, self.next_index + i.to_int64())
  }
  let out = []
  for x in xs {
    self.accept(x, out)
  }
  out
}

///|
/// Settle the last extremum, then emit remaining half cycles from oldest
/// to newest. Further calls return an empty array.
pub fn Counter::finish(self : Counter) -> Array[Cycle] {
  let out = []
  if !self.closed {
    self.closed = true
    if self.candidate is Some(last) && self.trend != 0 {
      self.reversal(last, out)
    }
    for i in 1..<self.stack.length() {
      out.push(counted(self.stack[i - 1], self.stack[i], 1))
    }
    self.stack.clear()
    self.candidate = None
  }
  out
}

///|
/// Count an entire open-ended loading history, without periodic wrapping.
pub fn extract(xs : ArrayView[Double]) -> Array[Cycle] raise RainError {
  let stream = Counter::new()
  let cycles = stream.push_chunk(xs)
  cycles.append(stream.finish())
  cycles
}
