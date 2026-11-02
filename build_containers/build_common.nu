def select-engine [] {
  if ((which apptainer | length) > 0) {
    "apptainer"
  } else if ((which singularity | length) > 0) {
    "singularity"
  } else {
    error make {msg: "Apptainer or Singularity not found."}
  }
}

def status-label [status: string] {
  match $status {
    "OK" => $"(ansi green)OK(ansi reset)"
    "SKIP" => $"(ansi yellow)SKIP(ansi reset)"
    "WARN" => $"(ansi yellow)WARN(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    "DRY-RUN" => $"(ansi cyan)DRY-RUN(ansi reset)"
    _ => $status
  }
}

def status [label: string message: string] {
  let line = $"[(status-label $label)] ($message)"
  if $label == "ERROR" {
    print --stderr $line
  } else {
    print $line
  }
}

def step [message: string] {
  print $message
}

def sentence [message: string] {
  let text = ($message | str trim)
  if ($text | str ends-with ".") {
    $text
  } else {
    $"($text)."
  }
}

def field [name: string value: string] {
  print $"($name): ($value)"
}

def title [name: string] {
  print ""
  print $"(ansi cyan)($name)(ansi reset)"
}

def check-path [path: string name: string] {
  if not ($path | path exists) {
    error make {msg: $"Missing ($name): ($path)."}
  }
}

# Render template placeholders into a temporary definition file.
def render-template [template_path: string out_path: string values: record] {
  mut text = (open $template_path)

  for key in ($values | columns) {
    let placeholder = ("{{" + $key + "}}")
    let value = ($values | get $key | into string)
    $text = ($text | str replace --all $placeholder $value)
  }

  $text | save -f $out_path
}

# Guard against building from an unrendered template.
def ensure-rendered [def_path: string] {
  if (open $def_path | str contains "{{") {
    error make {msg: $"Unrendered placeholder found: ($def_path)."}
  }
}

# Remove only the temporary build directory created by the caller.
def clean-temp-dir [temp_dir: string] {
  field "Cleanup" $temp_dir
  with-env {CODEX_TEMP_CLEANUP: "1"} {
    rm -rf $temp_dir
  }
}
