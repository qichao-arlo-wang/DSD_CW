param(
    [switch]$SkipRun
)

$ErrorActionPreference = 'Stop'

$tbRoot = (Resolve-Path (Join-Path $PSScriptRoot '.')).Path
$codeRoot = (Resolve-Path (Join-Path $tbRoot '..')).Path
$outRoot = Join-Path $tbRoot 'modelsim_projects'

New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$simModelFiles = @(
    'rtl/sim_models/custom_fp_add.sv',
    'rtl/sim_models/custom_fp_mul.sv',
    'rtl/sim_models/custom_fp_sub.sv'
)

$rtlFiles = @(
    'rtl/core/task7_cordic_cos_multi_iter.sv',
    'rtl/core/task7_fp_add_ip_unit.sv',
    'rtl/core/task7_fp_mul_ip_unit.sv',
    'rtl/core/task7_fp_sub_ip_unit.sv',
    'rtl/core/task7_fp32_to_fx.sv',
    'rtl/core/task7_fx_to_fp32.sv',
    'rtl/ci_step2/task7_ci_cos_only.sv',
    'rtl/ci_step2/task7_ci_fp32_add.sv',
    'rtl/ci_step2/task7_ci_fp32_mul.sv',
    'rtl/ci_step2/task7_ci_fp32_sub.sv',
    'rtl/ci_step3/task7_ci_f_single.sv',
    'rtl/task8/task8_ci_f2_accum.sv',
    'rtl/task8_mm/task8_mm_fsum_accel.sv',
    'rtl/task8_pipe/task8_cordic_cos_pipe.sv',
    'rtl/task8_pipe/task8_fp_accum_interleaved.sv',
    'rtl/task8_pipe/task8_fp_add_rr_stage.sv',
    'rtl/task8_pipe/task8_fp_mul_rr_stage.sv',
    'rtl/task8_pipe/task8_pipe_fsum_core.sv',
    'rtl/task8_pipe/task8_ci_fsum_pipe.sv'
)

$embeddedCustomModelTbs = @(
    'tb_task7_fp_add_ip_unit_release',
    'tb_task7_fp_ip_units_hwish',
    'tb_task8_ci_fsum_pipe_clk_en_glitch',
    'tb_task8_ci_fsum_pipe_frame_isolation',
    'tb_task8_ci_fsum_pipe_hwish_long',
    'tb_task8_ci_fsum_pipe_hwish_repeats',
    'tb_task8_ci_fsum_pipe_random_hwish',
    'tb_task8_ci_fsum_pipe_release_regression',
    'tb_task8_ci_fsum_pipe_runtime_sweep',
    'tb_task8_ci_fsum_pipe_sweep_case'
)

function Get-RelativePath {
    param(
        [string]$FromDirectory,
        [string]$ToPath
    )

    $from = [System.IO.Path]::GetFullPath($FromDirectory)
    if (-not $from.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $from += [System.IO.Path]::DirectorySeparatorChar
    }
    $to = [System.IO.Path]::GetFullPath($ToPath)
    $fromUri = [System.Uri]::new($from)
    $toUri = [System.Uri]::new($to)
    return $fromUri.MakeRelativeUri($toUri).ToString()
}

function Get-TopModule {
    param([string]$TbFile)

    $matches = Select-String -Path $TbFile -Pattern '^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)' -AllMatches
    foreach ($m in $matches) {
        $name = $m.Matches[0].Groups[1].Value
        if ($name -notin @('custom_fp_add', 'custom_fp_mul', 'custom_fp_sub')) {
            return $name
        }
    }
    throw "Cannot determine top module for $TbFile"
}

function New-DoFile {
    param(
        [string]$TbName,
        [string]$TopModule,
        [string[]]$RelativeFiles,
        [string]$ProjectDir
    )

    $doPath = Join-Path $ProjectDir ($TbName + '.do')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('transcript on')
    $lines.Add('onerror {quit -f -code 1}')
    $lines.Add('onbreak {quit -f -code 1}')
    $lines.Add('if {[file exists work]} { catch {vdel -lib work -all} }')
    $lines.Add('vlib work')
    $lines.Add('vmap work work')
    foreach ($file in $RelativeFiles) {
        $lines.Add("vlog -work work {$file}")
    }
    $lines.Add("vsim -c work.$TopModule")
    $lines.Add('run -all')
    $lines.Add('quit -f -code 0')
    Set-Content -Path $doPath -Value $lines -Encoding ascii
}

function New-MpfFile {
    param(
        [string]$TbName,
        [string[]]$RelativeFiles,
        [string]$ProjectDir
    )

    $orig = Get-Location
    try {
        Set-Location $ProjectDir
        $commands = @("project new . $TbName")
        foreach ($file in $RelativeFiles) {
            $commands += "project addfile $file"
        }
        $commands += 'project calculateorder'
        $commands += 'project close'
        $commands += 'quit -f'
        $cmd = $commands -join '; '
        & vsim -c -do $cmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "ModelSim project generation failed for $TbName"
        }
    } finally {
        Set-Location $orig
    }
}

function Invoke-DoFile {
    param(
        [string]$TbName,
        [string]$ProjectDir
    )

    $orig = Get-Location
    try {
        Set-Location $ProjectDir
        $output = & vsim -c -do ($TbName + '.do') 2>&1
        Set-Content -Path (Join-Path $ProjectDir 'transcript.log') -Value $output -Encoding utf8
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    } finally {
        Set-Location $orig
    }
}

$tbFiles = Get-ChildItem $tbRoot -Filter 'tb_*.sv' | Sort-Object Name
$results = New-Object System.Collections.Generic.List[object]

foreach ($tb in $tbFiles) {
    $tbName = $tb.BaseName
    $projectDir = Join-Path $outRoot $tbName
    if (Test-Path $projectDir) {
        Remove-Item -Recurse -Force $projectDir
    }
    New-Item -ItemType Directory -Force -Path $projectDir | Out-Null

    $files = New-Object System.Collections.Generic.List[string]
    if ($tbName -notin $embeddedCustomModelTbs) {
        foreach ($file in $simModelFiles) { $files.Add($file) }
    }
    foreach ($file in $rtlFiles) { $files.Add($file) }
    $files.Add((Join-Path 'tb' ($tb.Name)).Replace('\', '/'))

    $relativeFiles = foreach ($file in $files) {
        $absolutePath = Join-Path $codeRoot $file
        Get-RelativePath -FromDirectory $projectDir -ToPath $absolutePath
    }

    $topModule = Get-TopModule -TbFile $tb.FullName
    New-DoFile -TbName $tbName -TopModule $topModule -RelativeFiles $relativeFiles -ProjectDir $projectDir
    New-MpfFile -TbName $tbName -RelativeFiles $relativeFiles -ProjectDir $projectDir

    if (-not $SkipRun) {
        $run = Invoke-DoFile -TbName $tbName -ProjectDir $projectDir
        $passed = ($run.ExitCode -eq 0)
        $results.Add([pscustomobject]@{
            Testbench = $tbName
            TopModule = $topModule
            Passed    = $passed
            ExitCode  = $run.ExitCode
            Project   = $projectDir
        })
    }
}

$summaryPath = Join-Path $outRoot 'modelsim_summary.md'
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('# ModelSim Testbench Summary')
$summary.Add('')
$summary.Add("Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summary.Add('')

if ($SkipRun) {
    $summary.Add('Run status: generation only (`-SkipRun` used)')
} else {
    $summary.Add('| Testbench | Top Module | Result | Exit Code |')
    $summary.Add('| --- | --- | --- | ---: |')
    foreach ($r in $results) {
        $resultText = if ($r.Passed) { 'PASS' } else { 'FAIL' }
        $summary.Add("| $($r.Testbench) | $($r.TopModule) | $resultText | $($r.ExitCode) |")
    }
}

Set-Content -Path $summaryPath -Value $summary -Encoding utf8

if (-not $SkipRun -and ($results | Where-Object { -not $_.Passed })) {
    throw 'One or more ModelSim testbenches failed. See modelsim_summary.md and per-test transcript.log files.'
}
