# Alfred Workflow

This folder contains a simple Alfred workflow source that shells out to the `mac-mirror` CLI.

## Expected CLI location

The workflow assumes the CLI has been installed to:

`~/Library/Application Support/MacMirror/bin/mac-mirror`

That happens automatically when you run the Mac Mirror app and enable launch-at-login, or you can copy the binary there yourself after a build.

## Build the workflow file

```bash
./Extras/Alfred/build-workflow.sh
```

The script creates `Extras/Alfred/build/Mac Mirror.alfredworkflow`.
