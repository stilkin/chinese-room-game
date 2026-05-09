## 1. Spec deltas

- [x] 1.1 `diffusion-engine` delta: REMOVE bit-hash requirement, ADD Int8 quantization requirement.
- [x] 1.2 `move-selection` delta: MODIFY game-specific strategy requirement to reference InfluenceOverlay; REMOVE the duplicate cold-start fallback requirement.
- [x] 1.3 `clone-brain` delta: REMOVE the legacy "Move selection delegates" requirement.

## 2. Validation

- [x] 2.1 `npx openspec validate spec-drift-cleanup --strict` passes.

## 3. Archive

- [ ] 3.1 `npx openspec archive spec-drift-cleanup -y` applies all deltas to canonical specs.
- [ ] 3.2 Re-run `npx openspec validate --all --strict`; all 14 canonical specs + 0 active changes pass.
