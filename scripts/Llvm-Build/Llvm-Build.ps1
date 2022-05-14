. (Join-Path $PSScriptRoot RepoBuild-Common.ps1)
. (Join-Path $PSScriptRoot CMake-Helpers.ps1)

function New-LlvmCmakeConfig(
    [string]$platform,
    [string]$config,
    [string]$baseBuild = (Join-Path (Get-Location) BuildOutput),
    [string]$srcRoot = (Join-Path (Get-Location) 'llvm\lib')
    )
{
    [CMakeConfig]$cmakeConfig = New-Object CMakeConfig -ArgumentList $platform, $config, $baseBuild, $srcRoot
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_ENABLE_RTTI', 'ON')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_TOOLS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_UTILS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_DOCS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_RUNTIME', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_RUNTIMES', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_TESTS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_EXAMPLES', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_BENCHMARKS','OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_LLVM_C_DYLIB','OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_BUILD_LLVM_DYLIB','OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_OPTIMIZED_TABLEGEN', 'ON')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_REVERSE_ITERATION', 'ON')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_TARGETS_TO_BUILD', 'all')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_DOCS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_EXAMPLES', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_GO_TESTS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_RUNTIMES', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_TESTS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_TOOLS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_INCLUDE_UTILS', 'OFF')
    $cmakeConfig.CMakeBuildVariables.Add('LLVM_ADD_NATIVE_VISUALIZERS_TO_SOLUTION', 'ON')
    return $cmakeConfig
}

function global:Get-LlvmVersion( [string] $cmakeListPath )
{
    $props = @{}
    $matches = Select-String -Path $cmakeListPath -Pattern "set\(LLVM_VERSION_(MAJOR|MINOR|PATCH) ([0-9]+)\)" |
        %{ $_.Matches } |
        %{ $props.Add( $_.Groups[1].Value, [Convert]::ToInt32($_.Groups[2].Value) ) }
    return $props
}

function global:New-PathInfo([Parameter(Mandatory=$true)]$BasePath, [Parameter(Mandatory=$true, ValueFromPipeLine)]$Path)
{
    $relativePath = ($Path.FullName.Substring($BasePath.Trim('\').Length + 1))
    @{
        FullPath=$Path.FullName;
        RelativePath=$relativePath;
        RelativeDir=[System.IO.Path]::GetDirectoryName($relativePath);
        FileName=[System.IO.Path]::GetFileName($Path.FullName);
    }
}

function global:LinkFile($archiveVersionName, $info)
{
    $linkPath = join-Path $archiveVersionName $info.RelativeDir
    if(!(Test-Path -PathType Container $linkPath))
    {
        md $linkPath | Out-Null
    }

    Write-Verbose "Link: $linkPath => $($info.FullPath)"
    New-Item -ItemType HardLink -Path $linkPath -Name $info.FileName -Value $info.FullPath
}

function global:LinkPdb([Parameter(Mandatory=$true, ValueFromPipeLine)]$item, [Parameter(Mandatory=$true)]$NewLinkDirectory)
{
    BEGIN
    {
    }
    PROCESS
    {
        $newLinkPath = Join-Path $newLinkDirectory $item.Name
        if(Test-Path -PathType Leaf $newLinkPath)
        {
            del -Force $newLinkPath
        }

        Write-Verbose "Link: $linkPath => $($item.FullName)"
        New-Item -ItemType HardLink -Path $newLinkDirectory -Name $item.Name -Value $item.FullName -ErrorAction Stop | Out-Null
    }
    END
    {
    }
}

function global:Create-ArchiveLayout($archiveVersionName)
{
    $ErrorActionPreference = 'Stop'
    $InformationPreference = "Continue"

    # To simplify building the 7z archive with the desired structure
    # create the layout desired using hard-links, and zip the result in a single operation
    # this also allows local testing of the package without needing to publish, download and unpack the archive
    # while avoiding unnecessary file copies
    Write-Information "Creating ZIP structure hardlinks in $(Join-Path $global:RepoInfo.BuildOutputPath $archiveVersionName)"
    pushd $global:RepoInfo.BuildOutputPath
    try
    {
        if(Test-Path -PathType Container $archiveVersionName)
        {
            rd -Force -Recurse $archiveVersionName
        }

        md $archiveVersionName | Out-Null

        ConvertTo-Json (Get-LlvmVersion (Join-Path $global:RepoInfo.LlvmRoot 'CMakeLists.txt')) | Out-File (Join-Path $archiveVersionName 'llvm-version.json')

        $commonIncPath = join-Path $global:RepoInfo.LlvmRoot include
        # Build chained pipeline of output files to hard-link into archive layout
        & {
            dir x64-Debug\lib -Filter LLVM*.lib | %{ New-PathInfo $global:RepoInfo.BuildOutputPath.FullName $_}
            dir x64-Release\lib -Filter LLVM*.lib | %{ New-PathInfo $global:RepoInfo.BuildOutputPath.FullName $_}
            dir -r x64*\include -Include ('*.h', '*.gen', '*.def', '*.inc')| %{ New-PathInfo $global:RepoInfo.BuildOutputPath.FullName $_}
            dir -r $commonIncPath -Exclude ('*.txt')| ?{$_ -is [System.IO.FileInfo]} | %{ New-PathInfo $global:RepoInfo.LlvmRoot.FullName $_ }
            dir $global:RepoInfo.RepoRoot -Filter Llvm-Libs.* | ?{$_ -is [System.IO.FileInfo]} | %{ New-PathInfo $global:RepoInfo.RepoRoot.FullName $_ }
            dir (join-path $global:RepoInfo.LlvmRoot 'lib\ExecutionEngine\Orc\OrcCBindingsStack.h') | %{ New-PathInfo $global:RepoInfo.LlvmRoot.FullName $_ }
        } | %{ LinkFile $archiveVersionName $_ } | Out-Null

        # Link PDBs into the archive layout so that symbols are available.
        # These don't use New-PathInfo as the target destination isn't the
        # same relative path as the source location of the files.
        dir -r x64-Release -Include LLVM*.pdb | LinkPdb -NewLinkDirectory (Join-Path $archiveVersionName 'x64-Release\lib')
        dir -r x64-Debug -Include LLVM*.pdb | LinkPdb -NewLinkDirectory (Join-Path $archiveVersionName 'x64-Debug\lib')
    }
    finally
    {
        popd
    }
}

function global:Compress-BuildOutput
{
    $ErrorActionPreference = 'Stop'
    $InformationPreference = "Continue"

    if($env:APPVEYOR)
    {
        Write-Error "Cannot pack LLVM libraries in APPVEYOR build as it requires the built libraries and the total time required will exceed the limits of an APPVEYOR Job"
        return
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $oldPath = $env:Path
    $archiveVersionName = "llvm-libs-$($global:RepoInfo.LlvmVersion)-msvc-$($global:RepoInfo.VsInstance.InstallationVersion.Major).$($global:RepoInfo.VsInstance.InstallationVersion.Minor)"
    $archivePath = Join-Path $global:RepoInfo.BuildOutputPath "$archiveVersionName.7z"
    pushd $global:RepoInfo.BuildOutputPath
    try
    {
        Write-Information "Creating archive layout"
        Create-ArchiveLayout $archiveVersionName

        if(Test-Path -PathType Leaf $archivePath)
        {
            del -Force $archivePath
        }

        Write-Information "Creating 7-ZIP archive $archivePath"
        cd $archiveVersionName
        7z.exe a $archivePath '*' -r -t7z -mx=9
    }
    finally
    {
        popd
        $timer.Stop()
        $env:Path = $oldPath
        Write-Information "Pack Finished - Elapsed Time: $($timer.Elapsed.ToString())"
    }
}

function global:Clear-BuildOutput()
{
    rd -Recurse -Force $global:RepoInfo.ToolsPath
    rd -Recurse -Force $global:RepoInfo.BuildOutputPath
    rd -Recurse -Force $global:RepoInfo.PackOutputPath
}

function global:Invoke-Build([switch]$GenerateOnly)
{
<#
.SYNOPSIS
    Wraps CMake generation and build for LLVM as used by the LLVM.NET project

.DESCRIPTION
    This script is used to build LLVM libraries
#>
    $ErrorActionPreference = 'Stop'
    $InformationPreference = "Continue"

    if($env:APPVEYOR)
    {
        Write-Error "Cannot build LLVM libraries in APPVEYOR build as the total time required will exceed the limits of an APPVEYOR Job"
    }

    <#
    NUMBER_OF_PROCESSORS < 6;
    This is generally an inefficient number of cores available (Ideally 6-8 are needed for a timely build)
    On an automated build service this may cause the build to exceed the time limit allocated for a build
    job. (As an example AppVeyor has a 1hr per job limit with VMs containing only 2 cores, which is
    unfortunately just not capable of completing the build for a single platform+configuration in time, let alone multiple combinations.)
    #>

    if( ([int]$env:NUMBER_OF_PROCESSORS) -lt 6 )
    {
        Write-Warning "NUMBER_OF_PROCESSORS{ $env:NUMBER_OF_PROCESSORS } < 6; Performance will suffer"
    }

    # Verify Cmake version info
    Assert-CmakeInfo ([Version]::new(3, 12, 1))

    try
    {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        foreach( $cmakeConfig in $global:RepoInfo.CMakeConfigurations )
        {
            Write-Information "Generating CMAKE configuration $($cmakeConfig.Name)"
            Invoke-CMakeGenerate $cmakeConfig

            if(!$GenerateOnly)
            {
                Write-Information "Building CMAKE configuration $($cmakeConfig.Name)"
                Invoke-CmakeBuild $cmakeConfig
            }
        }
    }
    finally
    {
        $timer.Stop()
        Write-Information "Build Finished - Elapsed Time: $($timer.Elapsed.ToString())"
    }
}

function global:Initialize-BuildPath([string]$path)
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

function global:Get-RepoInfo([switch]$Force)
{
    $repoRoot = (Get-Item $([System.IO.Path]::Combine($PSScriptRoot, '..', '..')))
    $llvmroot = (Get-Item $([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'llvm', 'llvm')))
    $llvmversionInfo = (Get-LlvmVersion (Join-Path $llvmroot 'CMakeLists.txt'))
    $llvmversion = "$($llvmversionInfo.Major).$($llvmversionInfo.Minor).$($llvmversionInfo.Patch)"
    $toolsPath = Initialize-BuildPath 'tools'
    $buildOuputPath = Initialize-BuildPath 'BuildOutput'
    $packOutputPath = Initialize-BuildPath 'packages'
    $vsInstance = Find-VSInstance -Force:$Force -Version '[15.0, 17.0)'

    if(!$vsInstance)
    {
        throw "No VisualStudio instance found! This build requires VS build tools to function"
    }

    $vcToolsVersion = get-content (join-path $vsInstance.InstallationPath 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.v142.default.txt')
    if([Environment]::Is64BitOperatingSystem)
    {
        $hostArch = 'x64'
    }
    else
    {
        $hostArch = 'x86'
    }
    $targetArch = 'x64'
    $vcToolsPath = Join-Path $vsInstance.InstallationPath "VC\Tools\MSVC\$vcToolsVersion\bin\Host$hostArch\$targetArch"

    return @{
        RepoRoot = $repoRoot
        ToolsPath = $toolsPath
        BuildOutputPath = $buildOuputPath
        PackOutputPath = $packOutputPath
        LlvmRoot = $llvmroot
        LlvmVersion = $llvmversion
        Version = $llvmversion # this may differ from the LLVM Version if the packaging infrastructure is "patched"
        VsInstanceName = $vsInstance.DisplayName
        VsVersion = $vsInstance.InstallationVersion
        VsInstance = $vsInstance
        VCToolsVersion = $vcToolsVersion
        VCToolsPath = $vcToolsPath
        CMakeConfigurations = @( (New-LlvmCmakeConfig x64 'Release' $buildOuputPath $llvmroot),
                                 (New-LlvmCmakeConfig x64 'Debug' $buildOuputPath $llvmroot)
                               )
    }
}

function Initialize-BuildEnvironment
{
    # Prevent re-running of this function from infinitely increasing the size of the path string
    if($env:__PATH_BEFORE_INIT_ENVIRONMENT)
    {
        $env:Path = $env:__PATH_BEFORE_INIT_ENVIRONMENT
    }
    else
    {
        $env:__PATH_BEFORE_INIT_ENVIRONMENT = $env:Path
    }

    $env:Path = "$($global:RepoInfo.ToolsPath);$env:Path"
    $isCI = !!$env:CI

    Write-Information "Build Info:`n $($global:RepoInfo | Out-String)"
    Write-Information "PS Version:`n $($PSVersionTable | Out-String)"

    $msBuildInfo = Find-MsBuild
    if( !$msBuildInfo.FoundOnPath )
    {
        Write-Information "Using MSBuild from: $($msBuildInfo.BinPath)"
        $env:Path = "$($env:Path);$($msBuildInfo.BinPath)"
    }

    $cmakePath = $(Join-Path $global:RepoInfo.VsInstance.InstallationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin')
    if(!(Test-Path -PathType Leaf (Join-Path $cmakePath 'cmake.exe')))
    {
        throw "CMAKE.EXE not found at: '$cmakePath'"
    }

    Write-Information "Using cmake from VS Instance"
    $env:Path = "$cmakePath;$env:Path"

    $ninjaPath = $(Join-Path $global:RepoInfo.VsInstance.InstallationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja')
    if(!(Test-Path -PathType Leaf (join-path $ninjaPath 'ninja.exe')))
    {
        throw "CMAKE.EXE not found at: '$ninjaPath'"
    }
    $env:Path = "$ninjaPath;$env:Path"
    Initialize-VCVars

    $vsGitCmdPath = [System.IO.Path]::Combine( $global:RepoInfo.VsInstance.InstallationPath, 'Common7', 'IDE', 'CommonExtensions', 'Microsoft', 'TeamFoundation', 'Team Explorer', 'Git', 'cmd')
    if(Test-Path -PathType Leaf ([System.IO.Path]::Combine($vsGitCmdPath, 'git.exe')))
    {
        Write-Information "Using git from VS Instance"
        $env:Path = "$vsGitCmdPath;$env:Path"
    }

    Write-Information "cmake: $cmakePath"
}

# --- Module init script
$ErrorActionPreference = 'Stop'
$InformationPreference = "Continue"

$isCI = !!$env:CI -or !!$env:GITHUB_ACTIONS

$global:RepoInfo = Get-RepoInfo -Force:$isCI

New-Alias -Name build -Value Invoke-Build -Scope Global -Force
New-Alias -Name pack -Value Compress-BuildOutput -Scope Global -Force
New-Alias -Name clean -Value Clear-BuildOutput -Scope Global -Force
