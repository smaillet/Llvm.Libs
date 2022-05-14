class CMakeConfig
{
    [string]$Name;

    [ValidateSet('x86','x64')]
    [string]$Platform;

    [ValidateSet('Debug', 'Release', 'MinSizeRel', 'RelWithDebInfo')]
    [string]$BuildType;

    [string]$BuildRoot;
    [string]$SrcRoot;
    [string]$Generator;
    [System.Collections.ArrayList]$CMakeCommandArgs;
    [System.Collections.ArrayList]$BuildCommandArgs;
    [System.Collections.ArrayList]$InheritEnvironments;
    [hashtable]$CMakeBuildVariables;

    CMakeConfig([string]$plat, [string]$config, [string]$baseBuild, [string]$srcRoot)
    {
        $this.Name="$plat-$config"
        $this.Platform = $plat.ToLowerInvariant()

        $this.BuildRoot = Join-Path $baseBuild $this.Name
        $this.SrcRoot = $srcRoot
        $this.Generator = "Ninja"
        $this.CMakeCommandArgs = [System.Collections.ArrayList]@()
        $this.BuildCommandArgs = [System.Collections.ArrayList]@()
        $this.InheritEnvironments = [System.Collections.ArrayList]@()
        $this.CMakeBuildVariables = @{}

        if($config -ieq "Release" )
        {
            $this.BuildType = "RelWithDebInfo"
        }
        else
        {
            $this.BuildType = $config
        }

        # Ninja is a single configuration build system, so inform CMAKE which configuration to generate
        $this.CMakeBuildVariables.Add("CMAKE_BUILD_TYPE", $this.BuildType)
    }
}

function global:Assert-CmakeInfo([Version]$minVersion)
{
    $cmakePath = Find-OnPath 'cmake.exe'
    if( !$cmakePath )
    {
        throw 'CMAKE.EXE not found'
    }

    $cmakeInfo = cmake.exe -E capabilities | ConvertFrom-Json
    if(!$cmakeInfo)
    {
        throw "CMake version not supported. 'cmake -E capabilities' returned nothing"
    }

    $cmakeVer = [Version]::new($cmakeInfo.version.major,$cmakeInfo.version.minor,$cmakeInfo.version.patch)
    if( $cmakeVer -lt $minVersion )
    {
        throw "CMake version not supported. Found: $cmakeVer; Require >= $($minVersion)"
    }
    Write-Information "CMAKE version: $cmakeVer"
}

function global:Invoke-CMakeGenerate( [CMakeConfig]$config )
{
    $activity = "Generating solution for $($config.Name)"
    Write-Information $activity
    if(!(Test-Path -PathType Container $config.BuildRoot ))
    {
        New-Item -ItemType Container $config.BuildRoot | Out-Null
    }

    # Construct full set of args from fixed options and configuration variables
    $cmakeArgs = New-Object System.Collections.ArrayList
    $cmakeArgs.Add("-G`"$($config.Generator)`"" ) | Out-Null
    foreach( $param in $config.CMakeCommandArgs )
    {
        $cmakeArgs.Add( $param ) | Out-Null
    }

    foreach( $var in $config.CMakeBuildVariables.GetEnumerator() )
    {
        $cmakeArgs.Add( "-D$($var.Key)=$($var.Value)" ) | Out-Null
    }

    $cmakeArgs.Add( $config.SrcRoot ) | Out-Null

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $cmakePath = Find-OnPath 'cmake.exe'
    pushd $config.BuildRoot
    try
    {
        $generatorLogFile = "cmake-generate-$($config.Name).log"
        Write-Information "Generating for $($config.Name)"
        cmake $cmakeArgs > $generatorLogFile

        if($LASTEXITCODE -ne 0 )
        {
            Write-Error "Cmake generation exited with code: $LASTEXITCODE"
            type $generatorLogFile
        }
    }
    finally
    {
        $timer.Stop()
        popd
    }
    Write-Information "Generation Time: $($timer.Elapsed.ToString())"
}

function global:Invoke-CmakeBuild([CMakeConfig]$config)
{
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Information "CMake Building $($config.Name)"

    $cmakeArgs = @('--build', "$($config.BuildRoot)", '--', "$($config.BuildCommandArgs)")

    Write-Information "cmake $([string]::Join(' ', $cmakeArgs))"
    cmake $cmakeArgs

    if($LASTEXITCODE -ne 0 )
    {
        Write-Error "Cmake build exited with code: $LASTEXITCODE"
    }

    $timer.Stop()
    Write-Information "Build Time: $($timer.Elapsed.ToString())"
}

function global:Assert-CMakeList([Parameter(Mandatory=$true)][string] $root)
{
    $cmakeListPath = Join-Path $root CMakeLists.txt
    if( !( Test-Path -PathType Leaf $cmakeListPath ) )
    {
        throw "'CMakeLists.txt' is missing, '$root' does not appear to be a valid source directory"
    }
}
