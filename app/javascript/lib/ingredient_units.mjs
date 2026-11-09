// Unit conversion for ingredient quantity badges. Base units: grams (mass), millilitres (volume).
const UNITS = {
  g: ["mass", 1], kg: ["mass", 1000], oz: ["mass", 28.3495], lb: ["mass", 453.592],
  ml: ["volume", 1], l: ["volume", 1000], tsp: ["volume", 4.92892], tbsp: ["volume", 14.7868], cup: ["volume", 236.588], "fl oz": ["volume", 29.5735]
}
// Click order: metric first, then imperial/US.
const CYCLES = { mass: ["g", "kg", "oz", "lb"], volume: ["ml", "l", "tsp", "tbsp", "cup", "fl oz"] }

export function convert(value, from, to) {
  return (value * UNITS[from][1]) / UNITS[to][1]
}

export function nextUnit(unit) {
  const cycle = CYCLES[UNITS[unit][0]]
  return cycle[(cycle.indexOf(unit) + 1) % cycle.length]
}

export function format(value) {
  if (value >= 100) return String(Math.round(value))
  return String(Number(value.toPrecision(3)))
}
