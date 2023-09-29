#Set Collection name
$CollectionName = "All Dell Systems w/o Warranty"

#Set Dell API key and secret
$dell_api_id = '<Insert Dell API Key>'
$dell_api_secret = '<Insert Dell API Secret>'

# Site configuration
$SiteCode = "<Insert Site code>" # Site code 
$ProviderMachineName = "<Insert MECM Site server FQDN>" # SMS Provider machine name

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

#Join-Object Function - https://github.com/RamblingCookieMonster/PowerShell/blob/master/Join-Object.ps1
function Join-Object
{
    <#
    .SYNOPSIS
        Join data from two sets of objects based on a common value
    .DESCRIPTION
        Join data from two sets of objects based on a common value
        For more details, see the accompanying blog post:
            http://ramblingcookiemonster.github.io/Join-Object/
        For even more details,  see the original code and discussions that this borrows from:
            Dave Wyatt's Join-Object - http://powershell.org/wp/forums/topic/merging-very-large-collections
            Lucio Silveira's Join-Object - http://blogs.msdn.com/b/powershell/archive/2012/07/13/join-object.aspx
    .PARAMETER Left
        'Left' collection of objects to join.  You can use the pipeline for Left.
        The objects in this collection should be consistent.
        We look at the properties on the first object for a baseline.
    
    .PARAMETER Right
        'Right' collection of objects to join.
        The objects in this collection should be consistent.
        We look at the properties on the first object for a baseline.
    .PARAMETER LeftJoinProperty
        Property on Left collection objects that we match up with RightJoinProperty on the Right collection
    .PARAMETER RightJoinProperty
        Property on Right collection objects that we match up with LeftJoinProperty on the Left collection
    .PARAMETER LeftProperties
        One or more properties to keep from Left.  Default is to keep all Left properties (*).
        Each property can:
            - Be a plain property name like "Name"
            - Contain wildcards like "*"
            - Be a hashtable like @{Name="Product Name";Expression={$_.Name}}.
                 Name is the output property name
                 Expression is the property value ($_ as the current object)
                
                 Alternatively, use the Suffix or Prefix parameter to avoid collisions
                 Each property using this hashtable syntax will be excluded from suffixes and prefixes
    .PARAMETER RightProperties
        One or more properties to keep from Right.  Default is to keep all Right properties (*).
        Each property can:
            - Be a plain property name like "Name"
            - Contain wildcards like "*"
            - Be a hashtable like @{Name="Product Name";Expression={$_.Name}}.
                 Name is the output property name
                 Expression is the property value ($_ as the current object)
                
                 Alternatively, use the Suffix or Prefix parameter to avoid collisions
                 Each property using this hashtable syntax will be excluded from suffixes and prefixes
    .PARAMETER Prefix
        If specified, prepend Right object property names with this prefix to avoid collisions
        Example:
            Property Name                   = 'Name'
            Suffix                          = 'j_'
            Resulting Joined Property Name  = 'j_Name'
    .PARAMETER Suffix
        If specified, append Right object property names with this suffix to avoid collisions
        Example:
            Property Name                   = 'Name'
            Suffix                          = '_j'
            Resulting Joined Property Name  = 'Name_j'
    .PARAMETER Type
        Type of join.  Default is AllInLeft.
        AllInLeft will have all elements from Left at least once in the output, and might appear more than once
          if the where clause is true for more than one element in right, Left elements with matches in Right are
          preceded by elements with no matches.
          SQL equivalent: outer left join (or simply left join)
        AllInRight is similar to AllInLeft.
        
        OnlyIfInBoth will cause all elements from Left to be placed in the output, only if there is at least one
          match in Right.
          SQL equivalent: inner join (or simply join)
         
        AllInBoth will have all entries in right and left in the output. Specifically, it will have all entries
          in right with at least one match in left, followed by all entries in Right with no matches in left, 
          followed by all entries in Left with no matches in Right.
          SQL equivalent: full join
    .EXAMPLE
        #
        #Define some input data.
        $l = 1..5 | Foreach-Object {
            [pscustomobject]@{
                Name = "jsmith$_"
                Birthday = (Get-Date).adddays(-1)
            }
        }
        $r = 4..7 | Foreach-Object{
            [pscustomobject]@{
                Department = "Department $_"
                Name = "Department $_"
                Manager = "jsmith$_"
            }
        }
        #We have a name and Birthday for each manager, how do we find their department, using an inner join?
        Join-Object -Left $l -Right $r -LeftJoinProperty Name -RightJoinProperty Manager -Type OnlyIfInBoth -RightProperties Department
            # Name    Birthday             Department  
            # ----    --------             ----------  
            # jsmith4 4/14/2015 3:27:22 PM Department 4
            # jsmith5 4/14/2015 3:27:22 PM Department 5
    .EXAMPLE  
        #
        #Define some input data.
        $l = 1..5 | Foreach-Object {
            [pscustomobject]@{
                Name = "jsmith$_"
                Birthday = (Get-Date).adddays(-1)
            }
        }
        $r = 4..7 | Foreach-Object{
            [pscustomobject]@{
                Department = "Department $_"
                Name = "Department $_"
                Manager = "jsmith$_"
            }
        }
        #We have a name and Birthday for each manager, how do we find all related department data, even if there are conflicting properties?
        $l | Join-Object -Right $r -LeftJoinProperty Name -RightJoinProperty Manager -Type AllInLeft -Prefix j_
            # Name    Birthday             j_Department j_Name       j_Manager
            # ----    --------             ------------ ------       ---------
            # jsmith1 4/14/2015 3:27:22 PM                                    
            # jsmith2 4/14/2015 3:27:22 PM                                    
            # jsmith3 4/14/2015 3:27:22 PM                                    
            # jsmith4 4/14/2015 3:27:22 PM Department 4 Department 4 jsmith4  
            # jsmith5 4/14/2015 3:27:22 PM Department 5 Department 5 jsmith5  
    .EXAMPLE
        #
        #Hey!  You know how to script right?  Can you merge these two CSVs, where Path1's IP is equal to Path2's IP_ADDRESS?
        
        #Get CSV data
        $s1 = Import-CSV $Path1
        $s2 = Import-CSV $Path2
        #Merge the data, using a full outer join to avoid omitting anything, and export it
        Join-Object -Left $s1 -Right $s2 -LeftJoinProperty IP_ADDRESS -RightJoinProperty IP -Prefix 'j_' -Type AllInBoth |
            Export-CSV $MergePath -NoTypeInformation
    .EXAMPLE
        #
        # "Hey Warren, we need to match up SSNs to Active Directory users, and check if they are enabled or not.
        #  I'll e-mail you an unencrypted CSV with all the SSNs from gmail, what could go wrong?"
        
        # Import some SSNs. 
        $SSNs = Import-CSV -Path D:\SSNs.csv
        #Get AD users, and match up by a common value, samaccountname in this case:
        Get-ADUser -Filter "samaccountname -like 'wframe*'" |
            Join-Object -LeftJoinProperty samaccountname -Right $SSNs `
                        -RightJoinProperty samaccountname -RightProperties ssn `
                        -LeftProperties samaccountname, enabled, objectclass
    .NOTES
        This borrows from:
            Dave Wyatt's Join-Object - http://powershell.org/wp/forums/topic/merging-very-large-collections/
            Lucio Silveira's Join-Object - http://blogs.msdn.com/b/powershell/archive/2012/07/13/join-object.aspx
        Changes:
            Always display full set of properties
            Display properties in order (left first, right second)
            If specified, add suffix or prefix to right object property names to avoid collisions
            Use a hashtable rather than ordereddictionary (avoid case sensitivity)
    .LINK
        http://ramblingcookiemonster.github.io/Join-Object/
    .FUNCTIONALITY
        PowerShell Language
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipeLine = $true)]
        [object[]] $Left,

        # List to join with $Left
        [Parameter(Mandatory=$true)]
        [object[]] $Right,

        [Parameter(Mandatory = $true)]
        [string] $LeftJoinProperty,

        [Parameter(Mandatory = $true)]
        [string] $RightJoinProperty,

        [object[]]$LeftProperties = '*',

        # Properties from $Right we want in the output.
        # Like LeftProperties, each can be a plain name, wildcard or hashtable. See the LeftProperties comments.
        [object[]]$RightProperties = '*',

        [validateset( 'AllInLeft', 'OnlyIfInBoth', 'AllInBoth', 'AllInRight')]
        [Parameter(Mandatory=$false)]
        [string]$Type = 'AllInLeft',

        [string]$Prefix,
        [string]$Suffix
    )
    Begin
    {
        function AddItemProperties($item, $properties, $hash)
        {
            if ($null -eq $item)
            {
                return
            }

            foreach($property in $properties)
            {
                $propertyHash = $property -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $expressionValue = $expression.Invoke($item)[0]
            
                    $hash[$hashName] = $expressionValue
                }
                else
                {
                    foreach($itemProperty in $item.psobject.Properties)
                    {
                        if ($itemProperty.Name -like $property)
                        {
                            $hash[$itemProperty.Name] = $itemProperty.Value
                        }
                    }
                }
            }
        }

        function TranslateProperties
        {
            [cmdletbinding()]
            param(
                [object[]]$Properties,
                [psobject]$RealObject,
                [string]$Side)

            foreach($Prop in $Properties)
            {
                $propertyHash = $Prop -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $ScriptString = $expression.tostring()
                    if($ScriptString -notmatch 'param\(')
                    {
                        Write-Verbose "Property '$HashName'`: Adding param(`$_) to scriptblock '$ScriptString'"
                        $Expression = [ScriptBlock]::Create("param(`$_)`n $ScriptString")
                    }
                
                    $Output = @{Name =$HashName; Expression = $Expression }
                    Write-Verbose "Found $Side property hash with name $($Output.Name), expression:`n$($Output.Expression | out-string)"
                    $Output
                }
                else
                {
                    foreach($ThisProp in $RealObject.psobject.Properties)
                    {
                        if ($ThisProp.Name -like $Prop)
                        {
                            Write-Verbose "Found $Side property '$($ThisProp.Name)'"
                            $ThisProp.Name
                        }
                    }
                }
            }
        }

        function WriteJoinObjectOutput($leftItem, $rightItem, $leftProperties, $rightProperties)
        {
            $properties = @{}

            AddItemProperties $leftItem $leftProperties $properties
            AddItemProperties $rightItem $rightProperties $properties

            New-Object psobject -Property $properties
        }

        #Translate variations on calculated properties.  Doing this once shouldn't affect perf too much.
        foreach($Prop in @($LeftProperties + $RightProperties))
        {
            if($Prop -as [hashtable])
            {
                foreach($variation in ('n','label','l'))
                {
                    if(-not $Prop.ContainsKey('Name') )
                    {
                        if($Prop.ContainsKey($variation) )
                        {
                            $Prop.Add('Name',$Prop[$Variation])
                        }
                    }
                }
                if(-not $Prop.ContainsKey('Name') -or $Prop['Name'] -like $null )
                {
                    Throw "Property is missing a name`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }


                if(-not $Prop.ContainsKey('Expression') )
                {
                    if($Prop.ContainsKey('E') )
                    {
                        $Prop.Add('Expression',$Prop['E'])
                    }
                }
            
                if(-not $Prop.ContainsKey('Expression') -or $Prop['Expression'] -like $null )
                {
                    Throw "Property is missing an expression`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }
            }        
        }

        $leftHash = @{}
        $rightHash = @{}

        # Hashtable keys can't be null; we'll use any old object reference as a placeholder if needed.
        $nullKey = New-Object psobject
        
        $bound = $PSBoundParameters.keys -contains "InputObject"
        if(-not $bound)
        {
            [System.Collections.ArrayList]$LeftData = @()
        }
    }
    Process
    {
        #We pull all the data for comparison later, no streaming
        if($bound)
        {
            $LeftData = $Left
        }
        Else
        {
            foreach($Object in $Left)
            {
                [void]$LeftData.add($Object)
            }
        }
    }
    End
    {
        foreach ($item in $Right)
        {
            $key = $item.$RightJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $rightHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $rightHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        foreach ($item in $LeftData)
        {
            $key = $item.$LeftJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $leftHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $leftHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        $LeftProperties = TranslateProperties -Properties $LeftProperties -Side 'Left' -RealObject $LeftData[0]
        $RightProperties = TranslateProperties -Properties $RightProperties -Side 'Right' -RealObject $Right[0]

        #I prefer ordered output. Left properties first.
        [string[]]$AllProps = $LeftProperties

        #Handle prefixes, suffixes, and building AllProps with Name only
        $RightProperties = foreach($RightProp in $RightProperties)
        {
            if(-not ($RightProp -as [Hashtable]))
            {
                Write-Verbose "Transforming property $RightProp to $Prefix$RightProp$Suffix"
                @{
                    Name="$Prefix$RightProp$Suffix"
                    Expression=[scriptblock]::create("param(`$_) `$_.'$RightProp'")
                }
                $AllProps += "$Prefix$RightProp$Suffix"
            }
            else
            {
                Write-Verbose "Skipping transformation of calculated property with name $($RightProp.Name), expression:`n$($RightProp.Expression | out-string)"
                $AllProps += [string]$RightProp["Name"]
                $RightProp
            }
        }

        $AllProps = $AllProps | Select -Unique

        Write-Verbose "Combined set of properties: $($AllProps -join ', ')"

        foreach ( $entry in $leftHash.GetEnumerator() )
        {
            $key = $entry.Key
            $leftBucket = $entry.Value

            $rightBucket = $rightHash[$key]

            if ($null -eq $rightBucket)
            {
                if ($Type -eq 'AllInLeft' -or $Type -eq 'AllInBoth')
                {
                    foreach ($leftItem in $leftBucket)
                    {
                        WriteJoinObjectOutput $leftItem $null $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
            else
            {
                foreach ($leftItem in $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $leftItem $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }

        if ($Type -eq 'AllInRight' -or $Type -eq 'AllInBoth')
        {
            foreach ($entry in $rightHash.GetEnumerator())
            {
                $key = $entry.Key
                $rightBucket = $entry.Value

                $leftBucket = $leftHash[$key]

                if ($null -eq $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $null $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }
    }
}

#Get Dell token - this is valid for 1 hour
$access_token_endpoint_url = 'https://apigtwb2c.us.dell.com/auth/oauth/v2/token'
$requestBody = @{
    grant_type = "client_credentials"
    client_id = $dell_api_id
    client_secret = $dell_api_secret
}
$authResponse = Invoke-RestMethod -Method Post -Uri $access_token_endpoint_url -Body $requestBody -ContentType "application/x-www-form-urlencoded"
$token = $authResponse.access_token

#Get date
$startDate = Get-Date

#Get Last Update time
$LastRefreshTime = (Get-CMDeviceCollection -Name $CollectionName).LastRefreshTime

#Update Membership of Collection
Invoke-CMCollectionUpdate -Name $CollectionName

#Wait until refresh is done
do {
    Start-Sleep 30
} while ($LastRefreshTime -eq (Get-CMDeviceCollection -Name $CollectionName).LastRefreshTime -and $startDate.AddMinutes(10) -gt (Get-Date))

#Check it 10 minute timeout reached
if ($LastRefreshTime -eq (Get-CMDeviceCollection -Name $CollectionName).LastRefreshTime) {
    throw "Timeout reached - collection didn't update within 10 minutes"
}

#Get all collection members and serial numbers
$Resources = Get-CMCollectionMember -CollectionName $CollectionName | Select-Object ResourceID, SerialNumber

#Split $Resources into batches of 70 to improve performance of the Dell API
for($i = 0; $i -lt $Resources.Count; $i += 70) {#Change 1000 to the number you want to process in a single batch 
    $num = $i + 69 #Change this number to 1 less that the batch number
    if ($num -ge $Resources.Count) {
            $num = $Resources.Count 
       }
    $ResourceBatch = $Resources[$i..$num]
    Write-Host "No of Objects in the batch:" $ResourceBatch.Count
    Write-Host "Done $num of" $Resources.Count -ForegroundColor Cyan

    #Retrieve Warranty Expirations from Dell API
    $api_url = "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements"
    $headers = @{"Authorization" = "Bearer $token" }
    $body = @{
        servicetags = $ResourceBatch | Join-String -Property SerialNumber -Separator ', '
    }
    $json = (Invoke-RestMethod -URI $api_url -Method GET -contenttype 'Application/json' -Headers $headers -body $body) | Select-Object 'serviceTag', @{N='warrantyExpiration';E={$_.entitlements.endDate | Sort-Object -Descending | Select-Object -First 1}}

    #Join current $ResourceBatch and the json returned from Dell API on service tag
    $JoinedData = Join-Object -Left $ResourceBatch -LeftJoinProperty SerialNumber -Type AllInBoth -Right $json -RightJoinProperty servicetag

    #Add WarrantyExpiration Custom Property in MECM
    foreach ($Resource in $JoinedData){
        
        #Get ResourceID
        $ResourceID = $Resource.ResourceID

        #Get Warranty info from Dell
        $WarrantyExpiration = $Resource.warrantyExpiration

        #Set a List of properties (create or update)
        $uri = "https://$ProviderMachineName/AdminService/v1.0/Device($ResourceID)/AdminService.SetExtensionData"
        $body = "{ExtensionData:{""WarrantyExpiration"":""$WarrantyExpiration""}}"
        Invoke-WebRequest -Method "Post" -Uri $uri -UseDefaultCredentials -Body $body -ContentType "application/json"
    }
}
