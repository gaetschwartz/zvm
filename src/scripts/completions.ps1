function Split-String {
  # Parameter help description
  param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The string to split")]
    [string]$inputString
  )

  $splitString = @()
  $inQuote = $false
  $buffer = ""
  
  for ($i = 0; $i -lt $inputString.Length; $i++) {
    $char = $inputString[$i]
    if ($char -eq "'") {
      $inQuote = !$inQuote
    }
    elseif ($char -eq " " -and !$inQuote) {
      if ($buffer) {
        $splitString += $buffer
        $buffer = ""
      }
    }
    else {
      $buffer += $char
    }
  }
  
  if ($buffer) {
    $splitString += $buffer
  }
  
  return $splitString
}

$scriptblock = {
  param($wordToComplete, $commandAst, $cursorPosition)

  $argv = @("complete")
  $argv += $commandAst.ToString().Split(" ")
  $res = zvm $argv

  # so we need to use a regex to split on spaces outside of quotes
  $split = Split-String $res
  $split | ForEach-Object {
    $completion = $_
    if ($completion.StartsWith("'") -and $completion.EndsWith("'")) {
      $completion = $completion.Substring(1, $completion.Length - 2)
    }

    $parts = $completion.Split(":")
    $description = $completion
    if ($parts.Length -gt 1) {
      $completion = $parts[0]
      $description = $parts[1]
    }

    [System.Management.Automation.CompletionResult]::new($completion, $description, 'ParameterValue', $description)
  }
}
Register-ArgumentCompleter -Native -CommandName zvm -ScriptBlock $scriptblock
