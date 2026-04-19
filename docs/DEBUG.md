# NeverLost Workbench Debug

## Common Failure Classes

### RUNNER_MISSING
Expected PowerShell runner is missing from C:\dev\neverlost\scripts.

### PROCESS_START_FAILED
PowerShell could not be launched.

### Missing green token
The child process exited but did not emit the required token.

### Nonzero exit
The canonical runner failed. Inspect stdout/stderr shown in UI and evidence files on disk.

## Debug Rule
Always debug the PowerShell instrument first.
Do not patch around failures in the React UI.
