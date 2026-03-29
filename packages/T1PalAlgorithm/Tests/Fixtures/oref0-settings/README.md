# oref0-settings Fixtures

Test fixtures from OpenAPS settings directory with mapping to T1Pal profile format.

## Source

- Repository: `externals/openaps-example`
- Directory: `settings/`
- Date extracted: 2026-02-05
- Task: FIX-OA-007

## Files

| OpenAPS File | T1Pal Mapping | Description |
|--------------|---------------|-------------|
| settings.json | `AlgorithmProfile.maxBasal`, `maxBolus`, `dia` | Pump settings |
| selected-basal-profile.json | `AlgorithmProfile.basalSchedule` | Basal rate schedule |
| insulin-sensitivities.json | `AlgorithmProfile.isfSchedule` | ISF schedule |
| bg-targets.json | `AlgorithmProfile.targetSchedule` | Target glucose schedule |

## Settings Mapping

### settings.json → AlgorithmProfile

| OpenAPS Field | T1Pal Field | Notes |
|---------------|-------------|-------|
| `maxBasal` | `maxBasal` | Max temp basal rate (U/hr) |
| `maxBolus` | `maxBolus` | Max bolus amount (U) |
| `insulin_action_curve` | `dia` | DIA in hours (4, 5, or 6) |
| `temp_basal.type` | - | Always "Units/hour" for AID |
| `insulinConcentration` | - | U-100 assumed |

### selected-basal-profile.json → basalSchedule

```json
// OpenAPS format
{ "i": 0, "start": "00:00:00", "rate": 0.7, "minutes": 0 }

// T1Pal BasalScheduleEntry
{ "startTime": 0, "rate": 0.7 }  // startTime in seconds from midnight
```

Conversion: `startTime = minutes * 60` or parse "HH:MM:SS" to seconds.

### insulin-sensitivities.json → isfSchedule

```json
// OpenAPS format
{ "i": 0, "start": "00:00:00", "sensitivity": 45, "offset": 0 }

// T1Pal ISFScheduleEntry  
{ "startTime": 0, "value": 45 }
```

The `sensitivity` field maps directly to ISF value (mg/dL/U).

### bg-targets.json → targetSchedule

```json
// OpenAPS format
{ "i": 0, "start": "00:00:00", "low": 106, "high": 125, "offset": 0 }

// T1Pal TargetScheduleEntry
{ "startTime": 0, "low": 106, "high": 125 }
```

Target uses both low and high values; algorithm typically uses midpoint.

## Missing in OpenAPS Settings

These T1Pal fields have no direct OpenAPS equivalent:

| T1Pal Field | Default | Notes |
|-------------|---------|-------|
| `maxIOB` | 8.0 | Set separately in oref0 preferences |
| `maxCOB` | 120 | Calculated from carb ratio |
| `autosensMax` | 1.2 | oref0 preference file |
| `autosensMin` | 0.8 | oref0 preference file |
| `icrSchedule` | - | From `carb-ratios.json` if present |

## Carb Ratio Note

OpenAPS carb ratios are typically stored in `settings/carb-ratios.json` 
(not present in this example). The format is similar to ISF:

```json
{ "i": 0, "start": "00:00:00", "ratio": 10, "offset": 0 }
```

## Units

Both OpenAPS and T1Pal use:
- Glucose: mg/dL (configurable, but fixtures use mg/dL)
- Insulin: Units (U)
- Time: Seconds from midnight for schedules

## Usage Example

```swift
// Load OpenAPS settings
let settings: [String: Any] = try FixtureLoader.loadJSON(
    "settings",
    subdirectory: "oref0-settings"
)

// Convert to AlgorithmProfile
let profile = AlgorithmProfile(
    name: "Imported",
    dia: settings["insulin_action_curve"] as? Double ?? 6.0,
    maxBasal: settings["maxBasal"] as? Double ?? 5.0,
    maxBolus: settings["maxBolus"] as? Double ?? 10.0,
    // ... map schedules
)
```

## Traceability

- Task: FIX-OA-007
- Trace: ALG-009
- Related: PRD-ALGO-001 (Profile compatibility)
