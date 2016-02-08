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


function Load-Assembly($assembly)
{
    $assemblyClass = [Reflection.Assembly]
    $winmdClass = [Runtime.InteropServices.WindowsRuntime.WindowsRuntimeMetadata]
    $domain = [AppDomain]::CurrentDomain
    
    # Since desktop .NET can't work with winmd files,
    # we have to use the reflection-only APIs and preload
    # all the dependencies manually.
    $appDomainHandler =
    {
        Param($sender, $e)
        $assemblyClass::ReflectionOnlyLoad($e.Name)
    }
    
    $winmdHandler =
    {
        Param($sender, $e)
        [string[]] $empty = @()
        $path = $winmdClass::ResolveNamespace($e.NamespaceName, $empty) | select -Index 0
        $e.ResolvedAssemblies.Add($assemblyClass::ReflectionOnlyLoadFrom($path))
    }
    
    # Hook up the handlers
    $domain.add_ReflectionOnlyAssemblyResolve($appDomainHandler)
    $winmdClass::add_ReflectionOnlyNamespaceResolve($winmdHandler)
    
    try
    {
        # Load it! (plain old dlls)
        $assemblyObject = $assemblyClass::LoadFrom($assembly)
    }
    catch
    {
        # Load it again! (winmd components)
        $assemblyObject = $assemblyClass::ReflectionOnlyLoadFrom($assembly)
    }
    
    # Deregister the handlers
    $domain.remove_ReflectionOnlyAssemblyResolve($appDomainHandler)
    $winmdClass::remove_ReflectionOnlyNamespaceResolve($winmdHandler)
    
    return $assemblyObject
}

function Get-Namespaces($assembly)
{
    $assemblyObject = Load-Assembly $assembly
    $types = $assemblyObject.GetTypes()
    return $types | ? IsPublic | select -ExpandProperty Namespace -Unique
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