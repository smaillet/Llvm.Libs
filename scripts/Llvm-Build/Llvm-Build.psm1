#Requires -Version 5.0

Set-StrictMode -Version Latest

function New-LlvmCmakeConfig([string]$platform,
                             [string]$config,
                             [string]$baseBuild = (Join-Path (Get-Location) BuildOutput),
                             [string]$srcRoot = (Join-Path (Get-Location) 'llvm\lib')
                            )
{
    [CMakeConfig]$cmakeConfig = New-Object CMakeConfig -ArgumentList $platform, $config, $baseBuild, $srcRoot
    $cmakeConfig.CMakeBuildVariables = @{
        LLVM_ENABLE_RTTI = "ON"
        LLVM_ENABLE_CXX1Y = "ON"
        LLVM_BUILD_TOOLS = "OFF"
        LLVM_BUILD_UTILS = "OFF"
        LLVM_BUILD_DOCS = "OFF"
        LLVM_BUILD_RUNTIME = "OFF"
        LLVM_BUILD_RUNTIMES = "OFF"
        LLVM_OPTIMIZED_TABLEGEN = "ON"
        LLVM_REVERSE_ITERATION = "ON"
        LLVM_TARGETS_TO_BUILD  = "all"
        LLVM_INCLUDE_DOCS = "OFF"
        LLVM_INCLUDE_EXAMPLES = "OFF"
        LLVM_INCLUDE_GO_TESTS = "OFF"
        LLVM_INCLUDE_RUNTIMES = "OFF"
        LLVM_INCLUDE_TESTS = "OFF"
        LLVM_INCLUDE_TOOLS = "OFF"
        LLVM_INCLUDE_UTILS = "OFF"
        LLVM_ADD_NATIVE_VISUALIZERS_TO_SOLUTION = "ON"
        CMAKE_CXX_FLAGS_DEBUG = '/Zi /Fd$(OutDir)$(ProjectName).pdb'
        CMAKE_CXX_FLAGS_RELEASE = '/Zi /Fd$(OutDir)$(ProjectName).pdb'
    }
    return $cmakeConfig
}

function Get-LlvmVersion( [string] $cmakeListPath )
{
    $props = @{}
    $matches = Select-String -Path $cmakeListPath -Pattern "set\(LLVM_VERSION_(MAJOR|MINOR|PATCH) ([0-9])+\)" |
        %{ $_.Matches } |
        %{ $props.Add( $_.Groups[1].Value, [Convert]::ToInt32($_.Groups[2].Value) ) }
    return $props
}
Export-ModuleMember -Function Get-LlvmVersion

function LlvmBuildConfig([CMakeConfig]$configuration)
{
    Invoke-CMakeGenerate $configuration
    Invoke-CmakeBuild $configuration
}

function New-CMakeSettingsJson
{
    $RepoInfo.CMakeConfigurations.GetEnumerator() | New-CmakeSettings | Format-Json
}
Export-ModuleMember -Function New-CMakeSettingsJson

function Compress-BuildOutput
{
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $oldPath = $env:Path
    $archivePath = Join-Path $RepoInfo.BuildOutputPath "llvm-libs-$($RepoInfo.LlvmVersion)-msvc-$($RepoInfo.VsInstance.InstallationVersion.Major).$($RepoInfo.VsInstance.InstallationVersion.Minor).7z"
    try
    {
        if($env:APPVEYOR)
        {
            Write-Error "Cannot pack LLVM libraries in APPVEYOR build as it requires the built libraries and the total time required will exceed the limits of an APPVEYOR Job"
        }

        pushd $RepoInfo.BuildOutputPath
        try
        {
            # TODO: include targets and props files in the package so that consumers
            # can simply reference a properysheet (The way NuGet should have done it)

            7z.exe a $archivePath -t7z -mx=9 x64-Debug\Debug\lib\ x64-Release\Release\lib\
            7z.exe a $archivePath -t7z -mx=9 -r x64-Debug\include\*.h x64-Debug\include\*.gen x64-Debug\include\*.def
            7z.exe a $archivePath -t7z -mx=9 -r x64-Release\include\*.h x64-Release\include\*.gen x64-Release\include\*.def

            cd $RepoInfo.LlvmRoot
            7z.exe a '-xr!*.txt' '-xr!.*' -t7z -mx=9 $archivePath include\
            7z.exe a '-xr!*.txt' '-xr!.*' -t7z -mx=9 $archivePath include\
            
            cd $RepoInfo.RepoRoot
            7z.exe a -t7z -mx=9 $archivePath Llvm-Libs.*
        }
        finally
        {
            popd
        }
    }
    finally
    {
        $timer.Stop()
        $env:Path = $oldPath
        Write-Information "Pack Finished - Elapsed Time: $($timer.Elapsed.ToString())"
    }
}
Export-ModuleMember -Function Compress-BuildOutput

function Clear-BuildOutput()
{
    rd -Recurse -Force $RepoInfo.ToolsPath
    rd -Recurse -Force $RepoInfo.BuildOutputPath
    rd -Recurse -Force $RepoInfo.PackOutputPath
    $script:RepoInfo = Get-RepoInfo
}
Export-ModuleMember -Function Clear-BuildOutput

function Invoke-Build
{
<#
.SYNOPSIS
    Wraps CMake generation and build for LLVM as used by the LLVM.NET project

.DESCRIPTION
    This script is used to build LLVM libraries
#>

    [CmdletBinding(DefaultParameterSetName="build")]
    param( )

    if($env:APPVEYOR)
    {
        Write-Error "Cannot build LLVM libraries in APPVEYOR build as the total time required will exceed the limits of an APPVEYOR Job"
    }

    <#
    NUMBER_OF_PROCESSORS < 6;
    This is generally an inefficient number of cores available (Ideally 6-8 are needed for a timely build)
    On an automated build service this may cause the build to exceed the time limit allocated for a build
    job. (As an example AppVeyor has a 1hr per job limit with VMs containing only 2 cores, which is
    unfortunately just not capable of completing the build for a single platform+config in time, let alone multiple combinations.)
    #>

    if( ([int]$env:NUMBER_OF_PROCESSORS) -lt 6 )
    {
        Write-Warning "NUMBER_OF_PROCESSORS{ $env:NUMBER_OF_PROCESSORS } < 6;"
    }

    try
    {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        foreach( $cmakeConfig in $RepoInfo.CMakeConfigurations )
        {
            LlvmBuildConfig $cmakeConfig
        }
    }
    finally
    {
        $timer.Stop()
        Write-Information "Build Finished - Elapsed Time: $($timer.Elapsed.ToString())"
    }

    if( $Error.Count -gt 0 )
    {
        $Error.GetEnumerator() | %{ $_ }
    }
}
Export-ModuleMember -Function Invoke-Build

function EnsureBuildPath([string]$path)
{
    $resultPath = $([System.IO.Path]::Combine($PSScriptRoot, '..', '..', $path))
    if( !(Test-Path -PathType Container $resultPath) )
    {
        md $resultPath
    }
    else
    {
        Get-Item $resultPath
    }
}

function Get-RepoInfo([switch]$Force)
{
    $repoRoot = (Get-Item $([System.IO.Path]::Combine($PSScriptRoot, '..', '..')))
    $llvmroot = (Get-Item $([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'llvm')))
    $llvmversionInfo = (Get-LlvmVersion (Join-Path $llvmroot 'CMakeLists.txt'))
    $llvmversion = "$($llvmversionInfo.Major).$($llvmversionInfo.Minor).$($llvmversionInfo.Patch)"
    $toolsPath = EnsureBuildPath 'tools'
    $buildOuputPath = EnsureBuildPath 'BuildOutput'
    $packOutputPath = EnsureBuildPath 'packages'
    $vsInstance = Find-VSInstance -Force:$Force

    return @{
        RepoRoot = $repoRoot
        ToolsPath = $toolsPath
        BuildOutputPath = $buildOuputPath
        PackOutputPath = $packOutputPath
        LlvmRoot = $llvmroot
        LlvmVersion = $llvmversion
        Version = $llvmversion # this is may be differ from the LLVM Version if the packaging infrastructure is "patched"
        VsInstanceName = $vsInstance.DisplayName
        VsInstance = $vsInstance
        CMakeConfigurations = @( (New-LlvmCmakeConfig x64 'Release' $buildOuputPath $llvmroot),
                                 (New-LlvmCmakeConfig x64 'Debug' $buildOuputPath $llvmroot)
                               )
    }
}

function Initialize-BuildEnvironment
{
    $env:__LLVM_BUILD_INITIALIZED=1
    $env:Path = "$($RepoInfo.ToolsPath);$env:Path"

    $cmakePath = Find-OnPath 'cmake.exe'
    if(!$cmakePath)
    {
        $cmakePath = $(Join-Path $RepoInfo.VsInstance.InstallationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' )
        Write-Information "Using cmake from VS Instance"
        $env:Path = "$env:Path;$([System.IO.Path]::GetDirectoryName($cmakePath))"
    }

    if( !(Test-Path -PathType Leaf $cmakePath))
    {
        Write-Error "cmake.exe was not found!"
    }
    else
    {
        Write-Information "cmake: $cmakePath"
    }

    $path7Z = Find-OnPath '7z.exe'
    if(!$path7Z)
    {
        if( Test-Path -PathType Container HKLM:\SOFTWARE\7-Zip )
        {
            $path7Z = Join-Path (Get-ItemProperty HKLM:\SOFTWARE\7-Zip\ 'Path').Path '7z.exe'
        }

        if( !$path7Z -and ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") )
        {
            $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
            $subKey = $hklm.OpenSubKey("SOFTWARE\7-Zip")
            $root = $subKey.GetValue("Path")
            if($root)
            {
                $path7Z = Join-Path $root '7z.exe'
            }
        }
    }

    if(!$path7Z -or !(Test-Path -PathType Leaf $path7Z ) )
    {
        throw "Can't find 7-zip command line executable"
    }

    Write-Information "Using 7-zip from: $path7Z"
    $env:Path="$env:Path;$([System.IO.Path]::GetDirectoryName($path7Z))"
}
Export-ModuleMember -Function Initialize-BuildEnvironment

# --- Module init script
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$isCI = !!$env:CI
$RepoInfo = Get-RepoInfo  -Force:$isCI
Export-ModuleMember -Variable RepoInfo

New-Alias -Name build -Value Invoke-Build
Export-ModuleMember -Alias build

New-Alias -Name pack -Value Compress-BuildOutput
Export-ModuleMember -Alias pack

New-Alias -Name clean -Value Clear-BuildOutput
Export-ModuleMember -Alias clean

Write-Information "Build Info:`n $($RepoInfo | Out-String )"
