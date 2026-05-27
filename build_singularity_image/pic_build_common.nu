def select-engine [] {
  if ((which apptainer | length) > 0) {
    "apptainer"
  } else if ((which singularity | length) > 0) {
    "singularity"
  } else {
    error make {msg: "apptainer or singularity not found"}
  }
}

def check-path [path: string name: string] {
  if not ($path | path exists) {
    error make {msg: $"Missing ($name): ($path)"}
  }
}

def render-template [template_path: string out_path: string values: record] {
  mut text = (open $template_path)

  for key in ($values | columns) {
    let placeholder = ("{{" + $key + "}}")
    let value = ($values | get $key | into string)
    $text = ($text | str replace --all $placeholder $value)
  }

  $text | save -f $out_path
}

def ensure-rendered [def_path: string] {
  if (open $def_path | str contains "{{") {
    error make {msg: $"Unrendered placeholder found: ($def_path)"}
  }
}

def clean-temp-dir [temp_dir: string] {
  print $"Cleaning temporary dir: ($temp_dir)"
  rm -rf $temp_dir
}
