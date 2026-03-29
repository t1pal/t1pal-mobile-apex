# oref0-monitor Fixtures

Test fixtures from OpenAPS monitor directory containing pump and CGM state data.

## Source

- Repository: `externals/openaps-example`
- Directory: `monitor/`
- Date extracted: 2026-02-05

## Files

| File | Description |
|------|-------------|
| pump-history.json | Pump event history (temp basals, boluses) |
| glucose.json | CGM readings |
| status.json | Current pump status |
| temp-basal-status.json | Active temp basal state |
| reservoir.json | Reservoir level (units) |
| battery.json | Pump battery status |
| clock.json | Pump clock time |

## Pump History Event Types

The `pump-history.json` contains events with `_type` field:

- `TempBasal` - Temp basal rate setting
- `TempBasalDuration` - Temp basal duration
- `Bolus` - Bolus delivery
- `BolusWizard` - Bolus wizard calculation
- `BasalProfileStart` - Scheduled basal change
- `Prime` - Prime/fill event
- `Rewind` - Reservoir rewind

## Data Format

```json
{
  "_type": "TempBasal",
  "temp": "absolute",
  "timestamp": "2016-07-10T12:51:15-07:00",
  "rate": 1.1,
  "_body": "00",
  "_head": "332c",
  "_date": "4ff30c4a10"
}
```

## Usage

Load fixtures in tests using `FixtureLoader`:

```swift
let history: [PumpHistoryEvent] = try FixtureLoader.load(
    "pump-history",
    subdirectory: "oref0-monitor"
)
```

## Traceability

- Task: FIX-OA-006
- Trace: ALG-009
