#!/usr/bin/env nu

source ../build_common.nu

# Run smoke tests for PIC program images.
def main [
  program: string = "all" # all, epoch1d, epoch2d, epoch3d, smilei or smilei_spin
  --dry-run              # print commands only
] {
  # Test target configuration.
  let test_configs = {
    epoch1d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch1d/epoch_epoch1d.sif"
      input_dir: "pic_test_inputs/epoch1d"
      command: "printf '.\n' | epoch1d"
    }
    epoch2d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch2d/epoch_epoch2d.sif"
      input_dir: "pic_test_inputs/epoch2d"
      command: "printf '.\n' | epoch2d"
    }
    epoch3d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch3d/epoch_epoch3d.sif"
      input_dir: "pic_test_inputs/epoch3d"
      command: "printf '.\n' | epoch3d"
    }
    smilei: {
      image: "/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
      input_dir: "pic_test_inputs/smilei"
      command: "smilei smoke.py"
    }
    smilei_spin: {
      image: "/home/yuhanjin/Code_Program/Smilei_Spin/Smilei_Spin_v2_2_3D_interpolator/Smilei_Spin_v2_2_3D_interpolator.sif"
      input_dir: "pic_test_inputs/smilei_spin"
      command: "smilei smoke.py"
    }
  }

  # Select one target or all configured targets.
  let configured_targets = ($test_configs | columns)
  if $program != "all" and $program not-in $configured_targets {
    error make {msg: $"Unknown program: ($program)."}
  }
  let targets = (
    $configured_targets
    | where {|target| $program == "all" or $target == $program }
  )

  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let engine = (select-engine)

  for target in $targets {
    let cfg = ($test_configs | get $target)
    let image = ($cfg.image | path expand)
    let input_dir = ($script_dir | path join $cfg.input_dir)

    check-path $image $"($target) image"
    check-path $input_dir $"($target) input directory"

    let run_dir = if $dry_run {
      $"/tmp/pic_test_($target)"
    } else {
      mktemp -d
    }

    title "PIC image smoke test"
    field "Target" $target
    field "Mode" (if $dry_run { "dry-run" } else { "run" })
    field "Rule" "bind test input to /work and run startup command"
    field "Image" $image
    field "Input" $input_dir
    field "Run dir" $run_dir

    let shell_cmd = $"cd /work && ($cfg.command)"
    field "Command" $"($engine) exec --bind ($run_dir):/work ($image) sh -lc '($shell_cmd)'"

    if $dry_run {
      status "DRY-RUN" "No smoke test will be run."
    } else {
      try {
        # Copy smoke-test inputs into the isolated run directory.
        cp -r (($input_dir | path join "*") | into glob) $run_dir
        ^$engine exec --bind $"($run_dir):/work" $image sh -lc $shell_cmd
        if $env.LAST_EXIT_CODE != 0 {
          error make {msg: $"Smoke test failed with code ($env.LAST_EXIT_CODE)."}
        }
      } catch {|err|
        status "ERROR" $"Failed smoke-test files kept for review: ($run_dir)."
        error make {msg: (sentence $"Smoke test failed: ($err.msg)")}
      }

      clean-temp-dir $run_dir
      status "OK" $"Smoke test completed: ($target)."
    }
  }

  if $dry_run {
    status "OK" "Smoke-test dry run completed."
  } else {
    status "OK" "Smoke testing completed."
  }
}
