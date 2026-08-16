# Preview without sleeping this Mac

`swift test` never calls `pmset`. To *see* the UI:

```sh
swift run Decaffeinate --preview
swift run Decaffeinate --screenshots ~/Desktop/decaff-preview
swift run Decaffeinate --scan
```

`--preview` and `--screenshots` use fixture data. Sleep Now / display-off /
keep-awake do not call `pmset`.

Do **not** click Sleep Now on the installed `/Applications` app if you do
not want this Mac to sleep.
