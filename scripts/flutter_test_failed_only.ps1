param(
  [switch]$Full,
  [switch]$Reset,
  [switch]$NoFinalFull,
  [string]$StatePath = '.test-cache/flutter_failed_tests.json',
  [string]$FailureReportPath = 'test-results/flutter_test_failures.txt'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Ensure-ParentDirectory([string]$Path) {
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

function Get-ObjectPropertyValue($Object, [string]$Name) {
  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Normalize-TestPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  $normalized = $Path
  if ($Path.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
    try {
      $normalized = ([System.Uri]$Path).LocalPath
    } catch {
      $normalized = $Path
    }
  }

  try {
    $full = [System.IO.Path]::GetFullPath($normalized)
    $root = [System.IO.Path]::GetFullPath($repoRoot)
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
      $relative = $full.Substring($root.Length).TrimStart([char[]]'\/')
      return $relative.Replace('\', '/')
    }
  } catch {
    # Keep the original path if it cannot be normalized.
  }

  return $normalized.Replace('\', '/')
}

function Test-IsRunnableProjectTestPath([string]$Path) {
  $normalized = Normalize-TestPath $Path
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return $false
  }

  if ($normalized.StartsWith('package:', [System.StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }

  $candidate = $normalized.Replace('\', '/')
  if ($candidate -notmatch '^(test|integration_test)/.+_test\.dart$') {
    return $false
  }

  return Test-Path -LiteralPath $candidate -PathType Leaf
}

function Resolve-ProjectTestPath([string]$Primary, [string]$Secondary, [string]$Fallback) {
  foreach ($candidate in @($Primary, $Secondary, $Fallback)) {
    if (Test-IsRunnableProjectTestPath $candidate) {
      return Normalize-TestPath $candidate
    }
  }

  return $null
}

function Invoke-FlutterTestMachine([string[]]$Arguments) {
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lineCount = 0

  Write-Host ''
  Write-Host ('> flutter test {0} --machine' -f ($Arguments -join ' ')) -ForegroundColor Cyan
  Write-Host 'Running' -NoNewline -ForegroundColor DarkGray

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # Flutter and other native tools may legitimately write informational text
    # to stderr. Keep stderr in the captured machine stream without allowing it
    # to become a terminating PowerShell error.
    $ErrorActionPreference = 'Continue'
    & flutter test @Arguments --machine 2>&1 | ForEach-Object {
      $lines.Add($_.ToString())
      $lineCount++
      if (($lineCount % 200) -eq 0) {
        Write-Host '.' -NoNewline -ForegroundColor DarkGray
      }
    }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    Write-Host ''
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    # PowerShell 7.6 can throw "Argument types do not match" when @(...)
    # wraps a generic List<T>. Use the .NET array conversion explicitly.
    Lines = $lines.ToArray()
  }
}

function ConvertFrom-FlutterMachineLog(
  [string[]]$Lines,
  [int]$ExitCode,
  [string]$FallbackFile
) {
  $suitesById = @{}
  $testsById = @{}
  $errorsById = @{}
  $failed = New-Object 'System.Collections.Generic.List[object]'
  $diagnosticLines = New-Object 'System.Collections.Generic.List[string]'

  foreach ($line in $Lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    try {
      $event = $line | ConvertFrom-Json -ErrorAction Stop
    } catch {
      $diagnosticLines.Add($line)
      continue
    }

    $eventType = Get-ObjectPropertyValue $event 'type'
    if ([string]::IsNullOrWhiteSpace([string]$eventType)) {
      # Some output can be valid JSON without being a Flutter machine event.
      $diagnosticLines.Add($line)
      continue
    }

    switch ([string]$eventType) {
      'suite' {
        $suite = Get-ObjectPropertyValue $event 'suite'
        if ($null -eq $suite) {
          $diagnosticLines.Add($line)
          continue
        }

        $suiteId = Get-ObjectPropertyValue $suite 'id'
        if ($null -eq $suiteId) {
          $diagnosticLines.Add($line)
          continue
        }

        $suitePath = [string](Get-ObjectPropertyValue $suite 'path')
        if ([string]::IsNullOrWhiteSpace($suitePath)) {
          $suitePath = [string](Get-ObjectPropertyValue $suite 'url')
        }
        $normalizedSuitePath = Normalize-TestPath $suitePath
        if (Test-IsRunnableProjectTestPath $normalizedSuitePath) {
          $suitesById["$suiteId"] = $normalizedSuitePath
        }
      }

      'testStart' {
        $test = Get-ObjectPropertyValue $event 'test'
        if ($null -eq $test) {
          $diagnosticLines.Add($line)
          continue
        }

        $testId = Get-ObjectPropertyValue $test 'id'
        $testName = Get-ObjectPropertyValue $test 'name'
        if ($null -eq $testId -or [string]::IsNullOrWhiteSpace([string]$testName)) {
          $diagnosticLines.Add($line)
          continue
        }

        # testWidgets() is implemented by flutter_test and its machine event can
        # report package:flutter_test/src/widget_tester.dart as test.url. That is
        # a framework implementation file and cannot be passed to `flutter test`.
        # The suite event retains the actual project *_test.dart path, so prefer it.
        $suiteFile = $null
        $suiteId = Get-ObjectPropertyValue $test 'suiteID'
        if ($null -ne $suiteId -and $suitesById.ContainsKey("$suiteId")) {
          $suiteFile = [string]$suitesById["$suiteId"]
        }
        $testUrl = Normalize-TestPath ([string](Get-ObjectPropertyValue $test 'url'))
        $resolvedFile = Resolve-ProjectTestPath $suiteFile $testUrl $FallbackFile

        $testsById["$testId"] = [pscustomobject]@{
          Name = [string]$testName
          File = $resolvedFile
        }
      }

      'error' {
        $testId = Get-ObjectPropertyValue $event 'testID'
        if ($null -eq $testId) {
          $diagnosticLines.Add($line)
          continue
        }

        $id = "$testId"
        if (-not $errorsById.ContainsKey($id)) {
          $errorsById[$id] = New-Object 'System.Collections.Generic.List[string]'
        }

        $message = [string](Get-ObjectPropertyValue $event 'error')
        if ([string]::IsNullOrWhiteSpace($message)) {
          $message = 'Flutter reported an error without an error message.'
        }

        $stackTrace = [string](Get-ObjectPropertyValue $event 'stackTrace')
        if (-not [string]::IsNullOrWhiteSpace($stackTrace)) {
          $message += "`n" + $stackTrace
        }

        $errorsById[$id].Add($message)
      }

      'testDone' {
        $testId = Get-ObjectPropertyValue $event 'testID'
        $result = [string](Get-ObjectPropertyValue $event 'result')
        if ($null -eq $testId -or [string]::IsNullOrWhiteSpace($result)) {
          $diagnosticLines.Add($line)
          continue
        }

        if ($result -eq 'success' -or $result -eq 'skipped') {
          continue
        }

        $id = "$testId"
        $test = $null
        if ($testsById.ContainsKey($id)) {
          $test = $testsById[$id]
        }

        $name = if ($null -ne $test) { [string]$test.Name } else { "testID:$id" }
        $file = if ($null -ne $test) { [string]$test.File } else { Resolve-ProjectTestPath $null $null $FallbackFile }
        $mode = if ([string]::IsNullOrWhiteSpace($file) -or $name.StartsWith('loading ')) {
          'file'
        } else {
          'test'
        }

        $errorText = if ($errorsById.ContainsKey($id)) {
          $errorsById[$id].ToArray() -join "`n`n"
        } else {
          "Result: $result"
        }

        $failed.Add([pscustomobject]@{
          file = $file
          name = $name
          mode = $mode
          error = $errorText
        })
      }
    }
  }

  if ($ExitCode -ne 0 -and $failed.Count -eq 0) {
    $candidateFile = Resolve-ProjectTestPath $null $null $FallbackFile
    if ([string]::IsNullOrWhiteSpace($candidateFile)) {
      foreach ($line in $Lines) {
        if ($line -match '(test[\\/][^:\r\n]+?_test\.dart)') {
          $matchedFile = Normalize-TestPath $Matches[1]
          if (Test-IsRunnableProjectTestPath $matchedFile) {
            $candidateFile = $matchedFile
            break
          }
        }
      }
    }

    $errorText = ($diagnosticLines.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($errorText)) {
      $errorText = "flutter test exited with code $ExitCode before an individual failing test result was emitted."
    }

    $failed.Add([pscustomobject]@{
      file = $candidateFile
      name = '[suite load / compile failure]'
      mode = 'file'
      error = $errorText
    })
  }

  # Do not use @($failed) here. PowerShell 7.6 can fail to bind a generic
  # List<object> through the array-subexpression operator.
  return $failed.ToArray()
}

function Get-UniqueFailures([object[]]$Failures) {
  if ($null -eq $Failures -or $Failures.Count -eq 0) {
    return [object[]]@()
  }

  $unique = @{}
  foreach ($failure in $Failures) {
    $key = '{0}|{1}|{2}' -f $failure.mode, $failure.file, $failure.name
    $unique[$key] = $failure
  }

  [object[]]$sorted = $unique.Values | Sort-Object file, name
  return $sorted
}

function Save-FailureState([object[]]$Failures) {
  Ensure-ParentDirectory $StatePath
  [ordered]@{
    version = 2
    updatedAt = (Get-Date).ToString('o')
    failures = $Failures
  } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $StatePath
}

function Remove-FailureState {
  if (Test-Path $StatePath) {
    Remove-Item -Force $StatePath
  }
}

function Write-FailureReport([object[]]$Failures, [string]$RunMode) {
  Ensure-ParentDirectory $FailureReportPath
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('Flutter failed-test report')
  $lines.Add(('Generated: {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')))
  $lines.Add(('Run mode: {0}' -f $RunMode))
  $lines.Add(('Remaining failures: {0}' -f $Failures.Count))
  $lines.Add('')

  if ($Failures.Count -eq 0) {
    $lines.Add('No failing tests remain in the current failure queue.')
  }

  for ($i = 0; $i -lt $Failures.Count; $i++) {
    $failure = $Failures[$i]
    $fileLabel = if ([string]::IsNullOrWhiteSpace([string]$failure.file)) {
      '<unknown>'
    } else {
      [string]$failure.file
    }

    $lines.Add(('===== FAILURE {0}/{1} =====' -f ($i + 1), $Failures.Count))
    $lines.Add(('File: {0}' -f $fileLabel))
    $lines.Add(('Test: {0}' -f $failure.name))
    $lines.Add(('Mode: {0}' -f $failure.mode))

    if ($failure.mode -eq 'test' -and -not [string]::IsNullOrWhiteSpace([string]$failure.file)) {
      $escapedName = ([string]$failure.name).Replace('"', '\"')
      $lines.Add(('Retry: flutter test "{0}" --plain-name "{1}"' -f $failure.file, $escapedName))
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$failure.file)) {
      $lines.Add(('Retry: flutter test "{0}"' -f $failure.file))
    }

    $lines.Add('Error:')
    $lines.Add([string]$failure.error)
    $lines.Add('')
  }

  $lines.ToArray() | Set-Content -Encoding UTF8 $FailureReportPath
}

function Run-FullSuite {
  Write-Host 'Running the full Flutter test suite...' -ForegroundColor Yellow
  $result = Invoke-FlutterTestMachine -Arguments @()
  [object[]]$parsed = ConvertFrom-FlutterMachineLog $result.Lines $result.ExitCode $null
  [object[]]$failures = Get-UniqueFailures -Failures $parsed

  if ($failures.Count -gt 0) {
    Save-FailureState $failures
    Write-FailureReport $failures 'full-suite'
    Write-Host ("Full suite finished with {0} failing test(s)." -f $failures.Count) -ForegroundColor Red
    Write-Host ("Failure report: {0}" -f $FailureReportPath) -ForegroundColor Yellow
    return 1
  }

  Remove-FailureState
  Write-FailureReport ([object[]]@()) 'full-suite'
  Write-Host 'Full Flutter test suite passed.' -ForegroundColor Green
  return 0
}

if ($Reset) {
  Remove-FailureState
  if (Test-Path $FailureReportPath) {
    Remove-Item -Force $FailureReportPath
  }
  $Full = $true
}

if ($Full -or -not (Test-Path $StatePath)) {
  exit (Run-FullSuite)
}

try {
  $state = Get-Content -Raw $StatePath | ConvertFrom-Json
  $stateVersion = Get-ObjectPropertyValue $state 'version'
  if ($stateVersion -ne 2) {
    throw "Unsupported failed-test cache version: $stateVersion"
  }

  $stateFailures = Get-ObjectPropertyValue $state 'failures'
  if ($null -eq $stateFailures) {
    [object[]]$pending = @()
  } else {
    [object[]]$pending = $stateFailures
  }
} catch {
  Write-Warning 'The failed-test cache is stale or unreadable. Rebuilding it from a full test run.'
  Remove-FailureState
  exit (Run-FullSuite)
}

if ($pending.Count -eq 0) {
  Remove-FailureState
  exit (Run-FullSuite)
}

$invalidCachedFailures = @(
  $pending | Where-Object {
    -not (Test-IsRunnableProjectTestPath ([string]$_.file))
  }
)
if ($invalidCachedFailures.Count -gt 0) {
  Write-Warning (
    'The failed-test cache contains {0} non-project path(s) (for example flutter_test framework files). Rebuilding the cache from a full suite.' -f $invalidCachedFailures.Count
  )
  Remove-FailureState
  exit (Run-FullSuite)
}

Write-Host ("Re-running only {0} previously failing test(s)..." -f $pending.Count) -ForegroundColor Yellow
$remaining = New-Object 'System.Collections.Generic.List[object]'

foreach ($failure in $pending) {
  if (-not (Test-IsRunnableProjectTestPath ([string]$failure.file))) {
    $remaining.Add($failure)
    continue
  }

  $arguments = if ($failure.mode -eq 'test') {
    @([string]$failure.file, '--plain-name', [string]$failure.name)
  } else {
    @([string]$failure.file)
  }

  $result = Invoke-FlutterTestMachine -Arguments $arguments
  [object[]]$parsed = ConvertFrom-FlutterMachineLog $result.Lines $result.ExitCode ([string]$failure.file)
  [object[]]$newFailures = Get-UniqueFailures -Failures $parsed

  if ($result.ExitCode -eq 0 -and $newFailures.Count -eq 0) {
    Write-Host ("PASS: {0}" -f $failure.name) -ForegroundColor Green
    continue
  }

  if ($newFailures.Count -gt 0) {
    foreach ($newFailure in $newFailures) {
      $remaining.Add($newFailure)
    }
  } else {
    $remaining.Add($failure)
  }

  Write-Host ("FAIL: {0}" -f $failure.name) -ForegroundColor Red
}

[object[]]$remainingArray = $remaining.ToArray()
[object[]]$remainingUnique = Get-UniqueFailures -Failures $remainingArray
if ($remainingUnique.Count -gt 0) {
  Save-FailureState $remainingUnique
  Write-FailureReport $remainingUnique 'failed-only'
  Write-Host ("{0} failing test(s) remain. Passed tests were removed from the queue." -f $remainingUnique.Count) -ForegroundColor Red
  Write-Host ("Failure report: {0}" -f $FailureReportPath) -ForegroundColor Yellow
  exit 1
}

Remove-FailureState
Write-FailureReport ([object[]]@()) 'failed-only'
Write-Host 'All cached failures now pass.' -ForegroundColor Green

if ($NoFinalFull) {
  Write-Host 'Skipping the final full regression run because -NoFinalFull was supplied.' -ForegroundColor Yellow
  exit 0
}

Write-Host 'Failure queue is empty; running one final full regression suite.' -ForegroundColor Yellow
exit (Run-FullSuite)
