function Get-WpfAssemblies
{
    $names = 'PresentationCore', 'PresentationFramework', 'System.Xaml', 'WindowsBase'
    $programFiles = ${env:ProgramFiles(x86)}
    $base = $programFiles, 'Reference Assemblies', 'Microsoft', 'Framework', '.NETFramework' -Join '\'
    $latest = gci $base | % FullName | sort -Descending | select -Index 0
    return $names | % `
    {
        Join-Path $latest "$_.dll"
    }
}

function Get-UwpAssembly
{
    $name = 'Windows.Foundation.UniversalApiContract'
    $programFiles = ${env:ProgramFiles(x86)}
    $directory = $programFiles, 'Windows Kits', '10', 'References', $name -Join '\'
    $latest = gci $directory | % FullName | sort -Descending | select -Index 0
    return Join-Path $latest "$name.winmd"
}

function Get-Namespaces($assembly)
{
    Add-CecilReference
    $moduleDefinition = [Mono.Cecil.ModuleDefinition]
    $module = $moduleDefinition::ReadModule($assembly)
    return $module.Types | ? IsPublic | % Namespace | select -Unique
}

function Filter-Namespaces($namespaces)
{
    return $namespaces | ? `
    {
        $current = $_
        
        # Where(...).Count() == 0 isn't as efficient as !Any(...),
        # but who cares? This is just a PowerShell script.
        $filtered = $namespaces | ? `
        {
            $_.StartsWith("$current.")
        }
        
        $filtered.Length -eq 0
    }
}

function Extract-Nupkg($nupkg, $out)
{
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem' # PowerShell lacks native support for zip
    
    $zipFile = [IO.Compression.ZipFile]
    $zipFile::ExtractToDirectory($nupkg, $out)
}

function Add-CecilReference
{
    $url = 'https://www.nuget.org/api/v2/package/Mono.Cecil'
    $directory = $PSScriptRoot, 'bin', 'Mono.Cecil' -Join '\'
    $nupkg = Join-Path $directory 'Mono.Cecil.nupkg'
    $assemblyPath = $directory, 'lib', 'net45', 'Mono.Cecil.dll' -Join '\'
    
    if (Test-Path $assemblyPath)
    {
        # Already added the ref, nothing to do here
        return
    }
    
    ri -Recurse -Force $directory 2>&1 | Out-Null
    mkdir -f $directory
    iwr $url -OutFile $nupkg
    Extract-Nupkg $nupkg -Out $directory
    Add-Type -Path $assemblyPath
}

cd $PSScriptRoot

$assemblies = @()
$assemblies += Get-WpfAssemblies
$assemblies += Get-UwpAssembly

$template = gc 'Template.cs'
$namespaces = $assemblies | % `
{
    % { Get-Namespaces $_ }
}

# Filter out the namespaces we don't need
$namespaces = Filter-Namespaces $namespaces

$directory = 'bin/shims'
mkdir -f $directory | Out-Null

foreach ($namespace in $namespaces)
{
    $contents = $template -Replace '\$NAMESPACE', $namespace # -Replace uses regex, so escape the $
    $file = "$directory/$namespace.cs"
    echo $contents > $file
}

echo "Finished generating files. You can find them in $directory."