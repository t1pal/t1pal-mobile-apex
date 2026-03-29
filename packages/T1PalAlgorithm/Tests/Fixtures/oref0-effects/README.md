# oref0-effects Test Fixtures

Test vectors extracted from `externals/openaps-example/effects/` for algorithm conformance testing.

## Source
- Repository: openaps-example (OpenAPS reference implementation)
- Date range: 2016-07-10 (sample day with complete data)

## Files

| File | Description | Records |
|------|-------------|---------|
| `walsh_insulin_effect.json` | Insulin activity effect using Walsh curves | ~65 |
| `scheiner-carb-effect.json` | Carb absorption effect using Scheiner model | ~50 |
| `glucose-momentum-effect.json` | Glucose momentum extrapolation | ~70 |
| `cumulative-results.json` | Combined effect calculations | ~100 |
| `cleaned-history.json` | Pump history for effect calculations | ~30 |

## Data Format

All effect files follow the same structure:
```json
[
  {
    "date": "2016-07-10T04:50:00-07:00",
    "amount": -0.25510115448841897,
    "unit": "mg/dL"
  }
]
```

## Usage

These fixtures test:
1. **Walsh insulin curves** - insulin activity modeling
2. **Scheiner carb absorption** - carbohydrate effect predictions
3. **Glucose momentum** - trend-based extrapolation
4. **Effect summation** - combining multiple effects

## Trace
FIX-OA-003
