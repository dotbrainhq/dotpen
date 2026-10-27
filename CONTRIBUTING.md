# Contributing

Every change follows the same path, even a one-word fix.

1. Open an issue with a type label (`bug`, `enhancement` or `documentation`), an area label and a milestone.
2. Branch from an up-to-date `main`: `fix/<issue>-<slug>`, `feat/<issue>-<slug>`, `docs/<issue>-<slug>` or `chore/<slug>`.
3. Keep commits small, with an imperative subject: `Add`, `Fix`, `Update`, `Remove`, `Refactor`, `Test` or `Docs`.
4. Open a pull request that says `Closes #<issue>`.
5. Squash-merge once the `CI passed` check is green.

## Checks

Run these before opening a pull request:

```
(cd Packages/DotPenCore && swift test)
(cd Packages/DotPenRender && swift test)
xcodegen generate
xcodebuild -project dotPen.xcodeproj -scheme dotPen -configuration Debug -derivedDataPath build build
```

If you changed the renderer, also run `npm test` and `npm run build` in `renderer/`, and commit the built files in `Packages/DotPenRender/Sources/DotPenRender/Resources/renderer/`.

For anything you can see, check it in light and dark mode, with Reduce Motion on, and open `fixtures/sample.md` to make sure nothing else changed.
