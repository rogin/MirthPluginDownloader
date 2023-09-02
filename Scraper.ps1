#Requires -Version 6
#Requires -Modules PowerHTML

Import-Module PowerHTML
Import-Module PSSalesForceLogin
#Import-Module ../PSSalesForceLogin/PSSalesForceLogin.psd1 -Force

<#
    # List of plugins to download
    # Last updated: 31 July 2023
    
    Advanced Alerting                               Platinum Only
    Advanced Clustering                             Platinum Only
    ASTM E1381 Transmission Mode                    Gold or above
    ASTM E1394 Data Type                            Gold or above
    Channel History                                 Silver or above
    Cures Certification Support                     Gold or above
    Email Reader Connector                          Gold or above
    Enhancement Bundle                              Gold and Platinum
    FHIR Connector (R4)	                            Gold or above
    Health Data Hub Connector                       Platinum Only
    Interoperability Connector Suite                Gold or above
    License Manager                                 Silver or above
    LDAP Authentication                             Gold or above
    Message Generator                               Silver or above
    Mirth Results Connector                         Platinum Only
    Multi-Factor Authentication                     Gold or above
    Role-Based Access Control (User Authorization)  Gold or above
    Serial Connector                                Gold or above
    SSL Manager                                     Silver or above
#>
# we can request all plugins by providing an empty list
$PluginNames = @()
#$PluginNames = @('LDAP Authentication','Role-Based Access Control (User Authorization)', 'SSL Manager', 'Multi-Factor Authentication', 'FHIR Connector (R4)')

# plugin version to download
$PluginVersion = "4.4"

#your support level so you can skip the access errors
$UserSupportLevel = [SupportLevel]::GOLD

#do you also want to download the plugin's user guide?
$IncludeAttachments = $false

$ErrorActionPreference = 'Stop'

#hard-coded UUID within 1Password account
$1PASS_UUID = 'j5m7piroikq3dznzojyjmodyja'

$BaseUrl = "https://www.community.nextgen.com"
$LoginUrl = $BaseUrl + "/apex/SuccessCommunityLogin"
$PluginListUrl = $BaseUrl + "/optimization/articles/Hot_Topic/Mirth-Plug-In-Central"

enum SupportLevel {
    SILVER = 1
    GOLD = 2
    PLATINUM = 3
}

<#
.SYNOPSIS
    Obtain credential via 1password-cli integration
.PARAMETER UUID
    UUID of the 1Password item
#>
function Get-1PassCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $UUID
    )

    Invoke-Expression $(op signin)
    
    $json = op item get $UUID --fields "username,password" --format json | ConvertFrom-Json
    
    op signout

    $SecurePassword = ConvertTo-SecureString $json[1].value -AsPlainText
    
    New-Object System.Management.Automation.PSCredential ($json[0].value, $SecurePassword)
}

function Select-PluginLinks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Microsoft.PowerShell.Commands.WebRequestSession]
        $session
    )

    Write-Verbose "Selecting plugin links"

    Write-Debug "Invoking $PluginListUrl"
    $WebContent = Invoke-WebRequest -Uri $PluginListUrl -WebSession $session | ConvertFrom-Html

    # find the links where the href contains 'articles' as the others link to the Support Levels
    #$links = $WebContent.SelectNodes("//div[@class='pbBody']//tbody//td//span//a[contains(@href, 'articles')]")
    #https://stackoverflow.com/questions/3920957/xpath-query-with-descendant-and-descendant-text-predicates
    $PluginRows = $WebContent.SelectNodes("//div[@class='sfdc_richtext']//tbody//td//span//a[contains(@href, 'articles')]/ancestor::*[self::tr][1]")

    Write-Debug "Found $($PluginRows.Count) plugins"

    $FilteredPluginRows = $PluginRows.Where({
        $PR = $_
        $SupportLevelText = $PR.SelectSingleNode("td[2]").InnerText
        #the first word defines the minimum support level
        $SupportLevel = $SupportLevelText.Split(" ")[0].ToUpper() -as [SupportLevel]
        if($null -eq $SupportLevel) {
            Write-Error "Unable to determine Support Level for '$SupportLevelText'"
        }

        #Write-Debug "Comparing $UserSupportLevel -ge $SupportLevel"
        $UserSupportLevel -ge $SupportLevel
    })

        Write-Debug "Filtered to $($FilteredPluginRows.Count) plugins"

    $links = $FilteredPluginRows.SelectNodes("td[1]//span//a[contains(@href, 'articles')]")

	Write-Debug "Extracted $($links.Count) plugin links"

    #limit plugins to those we want
    #user can provide an empty list indicating all plugins
    if ($PluginNames.Count -eq 0) {
        Write-Debug "Returning all plugins"
        $links
    }
    else {
        @($links | Where-Object -FilterScript { $PluginNames -contains $_.InnerText.Trim() })
    }
}

function Read-PluginPage {
    [CmdletBinding()]
    param (
        # Node containing plugin download link
        [Parameter(Mandatory, ValueFromPipeline)]
        [HtmlAgilityPack.HtmlNode]
        $Node,
        [Parameter(Mandatory)]
        [Microsoft.PowerShell.Commands.WebRequestSession]
        $session,
        # switch to include attachments along with the plugin
        [switch]
        $IncludeAttachments
    )

    Begin {
        Write-Verbose "$($MyInvocation.MyCommand.Name) BEGIN"
    }

    Process {
        Write-Verbose "Processing '$($Node.InnerText)', `$IncludeAttachments=$IncludeAttachments"

        $href = $Node.GetAttributeValue('href', 'missing-href-value-1')

        if ($href -eq 'missing-href-value-1') {
            Write-Warning "Could not find href value for $($Node.InnerText) - you likely don't have the correct support level, skipping"
        }
        else {
            #noticed this wall with 'Mirth Results Connector' and 'Health Data Hub Connector'
            #check for nextgenhealthcare.lightning.force.com which redirects to salesforce.com
            if ($href -match 'lightning.force.com') {
                Write-Warning "Unable to download plugin $($Node.InnerText) as it requires a salesforce.com account, skipping"
            }
            else {
                $href = $BaseUrl + $href

                Write-Debug "Invoking plugin GET `$href=$href"
                $WebContent = Invoke-WebRequest -Uri $href -WebSession $session | ConvertFrom-Html

                $pluginDownloadLinks = $WebContent.SelectNodes("(//div[@class='pbSubsection'])[6]//table[@class='htmlDetailElementTable']//td//a")

                #example text: "Advanced Alerting  Plug-in 4.2"
                #example text: "Enhancement Bundle Plug-in 4.4.0"
                #$pluginDownloadLinks = @($pluginDownloadLinks | Where-Object { $_.InnerText.Trim().EndsWith($PluginVersion) })
                $pluginDownloadLinks = @($pluginDownloadLinks | Where-Object { $_.InnerText.Trim().Split(" ")[-1].StartsWith($PluginVersion) })

                Write-Verbose "Found $($pluginDownloadLinks.Count) links matching version '$PluginVersion'"
                
                if ($pluginDownloadLinks.Count -eq 0) {
                    Write-Warning "Failed to find version '$PluginVersion' of $($Node.InnerText)"
                }
                elseif ($pluginDownloadLinks.Count -gt 1) {
                    Write-Error "Found $($pluginDownloadLinks.Count) download links for version '$PluginVersion' of $($Node.InnerText), expected 1"
                }
                else {
                    $NameAndVersion = $pluginDownloadLinks[0].InnerText.Trim()

                    #ex. https://www.community.nextgen.com/apex/ResourceRepository?fileId=a9o4y000000YIdT
                    $downloadUrl = $pluginDownloadLinks[0].GetAttributeValue('href', 'missing-href-value-2')

                    Write-Debug "Invoking plugin '$NameAndVersion' GET $downloadUrl"

                    $downloadResponse = Invoke-WebRequest -Uri $downloadUrl -WebSession $session
                    #parse window.location.href from javascript in $downloadResponse.Content
                    #ex. /DownloadSuccess?fileId=a9o4y000000YId9
                    Write-Debug "Parsing javascript"
                    $extractedHref = $BaseUrl + (Get-SFHrefFromJavascript $downloadResponse.Content ";")

                    Write-Debug "Invoking GET $extractedHref"

                    # call the href that was in the javascript
                    $secondResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session | ConvertFrom-Html
                    
                    #if the plugin is at Support Level "Platinum Only", of which I don't have,
                    #then the link will send us to a forbidden page that will fail parsing for the hidden "a" tag below.
                    $hiddenLink = $secondResponse.SelectSingleNode("//a[@class='hidden']")

                    if ($null -eq $hiddenLink) {
                        Write-Warning "Failed to find download link - you likely don't have the correct support level, skipping"
                    }
                    else {
                        # extract final HREF
                        # ex. https://nextgen-aws-salesforce-prod-sdrive-us-east-2.s3.us-east-2.amazonaws.com/a9o4y000000YId9AAG/ldap-3.12.0.b1752.zip?X-Amz-Algorithm=AWS4-HMAC-SHA256&amp;X-Amz-Credential=AKIA2ZO6ZFSFWXJS7NWF%2F20220318%2Fus-east-2%2Fs3%2Faws4_request&amp;X-Amz-Date=20220318T051704Z&amp;X-Amz-Expires=216000&amp;X-Amz-SignedHeaders=host&amp;X-Amz-Signature=962a48d81f6091b86855eb2041df9bd0ba3123479ac87cc860bc061aa82edaff
                        $extractedHref = $hiddenLink.GetAttributeValue('href', 'missing-href-value-3')
                        Write-Debug "Found `$hiddenLink with `$extractedHref=$extractedHref"

                        Write-Debug "Decoding `$extractedHref"
                        # decode this or else the AWS call will fail
                        [uri]$decodedHref = [System.Web.HttpUtility]::HtmlDecode($extractedHref)
                        # extract filename
                        $filename = $decodedHref.Segments[-1]

                        Write-Debug "Downloading plugin '$filename' from $($decodedHref.AbsoluteUri)"

                        Invoke-WebRequest -Uri $decodedHref.AbsoluteUri -OutFile $filename
                    }
                }
            }
        }

        if ($IncludeAttachments) {
            # download all attachments
            $attachments = $WebContent.SelectNodes("(//div[@class='pbSubsection'])[7]//table[@class='detailList']//a")

            foreach ($attachment in $attachments) {
                $filename = $attachment.InnerText.Trim()

                if ($filename -eq '') {
                    Write-Warning "Attachment filename is empty, skipping"
                }
                else {
                    if (-not $filename.EndsWith(".pdf")) {
                        Write-Verbose "Appending .pdf to filename"
                        $filename += ".pdf"
                    }

                    Write-Verbose "Downloading attachment '$filename'"
                    $href = $BaseUrl + $attachment.GetAttributeValue('href', 'missing-attachment-href-value')

                    Write-Debug "Invoking GET `$filename=$filename, `$href=$href"

                    Invoke-WebRequest -Uri $href -WebSession $session -OutFile $filename
                }
            }
        }
    }

    End {
        Write-Verbose "$($MyInvocation.MyCommand.Name) END"
    }
}

function Start-Scrape {
    [CmdletBinding()]
    param ()

    begin {
        $StoredPSDefaultParameterValues = $PSDefaultParameterValues.Clone()
        $StoredProgressPreference = $ProgressPreference
        
        #it will whine about these parameters being re-added
        $PSDefaultParameterValues.Remove('Invoke-WebRequest:Debug')
        $PSDefaultParameterValues.Remove('Invoke-WebRequest:Verbose')

        # quiet this chatty function
        $PSDefaultParameterValues.Add('Invoke-WebRequest:Debug', $False)
        $PSDefaultParameterValues.Add('Invoke-WebRequest:Verbose', $False)

        # don't show progress bars
        $ProgressPreference = 'SilentlyContinue'
    }

    process {
        # this will hold our cookies and be used in (most) web requests
        $session = Get-1PassCredential $1PASS_UUID | Invoke-SFLogin $LoginUrl

        $pluginLinks = Select-PluginLinks $session
        
        $pluginLinks | Read-PluginPage -session $session -IncludeAttachments:$IncludeAttachments
    }

    end {
        $PSDefaultParameterValues = $StoredPSDefaultParameterValues
        $ProgressPreference = $StoredProgressPreference
    }
}

Start-Scrape -Debug -Verbose