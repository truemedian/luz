local luz = require('luz')

describe('time.sleep', function()
  it('sleeps for the specified time', function()
    local start = os.time()
    luz.time.sleep(2000)
    local stop = os.time()
    assert.is_true(stop - start >= 1)
  end)
end)

describe('time.timestamp', function()
  it('returns a sane number', function()
    local sec, ns = luz.time.timestamp()
    assert.is_true(sec >= 1577858400) -- > 2020
    assert.is_true(sec <= 33134767200) -- < 3020
    assert.is_number(ns)
  end)
end)

describe('time.Instant', function()
  it('calculates a time difference', function()
    local now = luz.time.Instant.now()

    luz.time.sleep(1 * luz.time.ms_per_s)

    local later = luz.time.Instant.now()

    assert.is_true(later:since(now) >= luz.time.ns_per_s)
    assert.is_true(now:since(later) <= -luz.time.ns_per_s)

    assert.is_true(later - now >= luz.time.ns_per_s)
    assert.is_true(now - later <= -luz.time.ns_per_s)

    assert.is_true(now < later)
    assert.is_false(now >= later)
    assert.is_false(now == later)
  end)
end)

describe('time.Timer', function()
  it('calculates a time difference', function()
    local timer = luz.time.Timer.start()

    luz.time.sleep(1000)

    local read1 = timer:read()
    assert.is_true(read1 >= 1 * luz.time.ns_per_s)
    assert.is_true(read1 <= 2 * luz.time.ns_per_s)

    luz.time.sleep(1000)

    local read2 = timer:lap()
    assert.is_true(read2 >= 2 * luz.time.ns_per_s)
    assert.is_true(read2 <= 3 * luz.time.ns_per_s)

    luz.time.sleep(1000)

    local read3 = timer:read()
    assert.is_true(read3 >= 1 * luz.time.ns_per_s)
    assert.is_true(read3 <= 2 * luz.time.ns_per_s)

    timer:reset()
    local read4 = timer:read()
    assert.is_true(read4 >= 0)
    assert.is_true(read4 <= 1 * luz.time.ns_per_s)
  end)
end)