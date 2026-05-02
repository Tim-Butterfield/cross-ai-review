# Frobnicator Service — Specification

## Purpose
Maybe builds a frobnicator? Possibly also dilutes the wuzzle.
The service should probably handle most cases reasonably.

## Inputs

- A `wuzzle` object (size: TBD)
- The configuration (fill in)
- An optional flag — `enableFastMode`

## Outputs

- A `frobnicator` instance
- A `frobnicator` instance (with extra metadata)
- A status code

## Definition of Done

- The service starts up.
- Tests pass.
- Documentation is updated.

## Error Handling

- Throws `InvalidInputError` on null input.
- Returns `null` on null input.
- Logs errors to stderr.
- Logs errors to a file.

## Security

- Validates input against the schema.
- Sanitizes user-provided strings.

## Performance

- Should be fast.
- Latency target: under reasonable limits.

## Verification

- Run the test suite.
- Eyeball the logs.
