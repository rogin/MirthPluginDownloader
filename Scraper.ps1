#Requires -Version 6
#Requires -Modules powerhtml

Import-Module powerhtml

<#
    # List of plugins to download
    # Last updated: 6 Jan 2023
    
    Advanced Alerting                               Gold or above
    Advanced Clustering                             Gold or above
    ASTM E1381 Transmission Mode                    Gold or above
    ASTM E1394 Data Type                            Gold or above
    Channel History                                 Core Extension Bundle or above
    Cures Certification Support                     Gold or above
    Email Reader Connector                          Gold or above
    FHIR Connector (R4)	                            Gold or above
    Health Data Hub Connector                       Platinum Only
    Interoperability Connector Suite                Platinum Only
    License Manager                                 Silver or above
    LDAP Authentication                             Gold or above
    Message Generator                               Core Extension Bundle or above
    Mirth Results Connector                         Platinum Only
    Multi-Factor Authentication                     Platinum Only
    Role-Based Access Control (User Authorization)  Gold or above
    Serial Connector                                Gold or above
    SSL Manager                                     Core Extension Bundle or above
#>
# we can request all plugins by providing an empty list
$PluginNames = @()
#$PluginNames = @('LDAP Authentication','Role-Based Access Control (User Authorization)', 'SSL Manager', 'Multi-Factor Authentication', 'FHIR Connector (R4)')

# plugin version to download
$PluginVersion = "4.2"

#do you also want to download the plugin's user guide?
$IncludeAttachments = $false

#hard-coded UUID within 1Password account
$1PASS_UUID = 'j5m7piroikq3dznzojyjmodyja'

$BaseUrl = "https://www.community.nextgen.com"
$LoginUrl = $BaseUrl + "/apex/SuccessCommunityLogin"
$PluginListUrl = $BaseUrl + "/optimization/articles/Hot_Topic/Mirth-Plug-In-Central"

# this will hold our cookies and be used in (most) web requests
$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

#currently obtains creds via 1password-cli integration
function ObtainCredentials {
    [CmdletBinding()]
    param ()

    Invoke-Expression $(op signin)
    
    $json = op get item $1PASS_UUID --fields username,password | ConvertFrom-Json
    
    op signout

    $json
}

# verified my work with his - https://xceptionale.wordpress.com/2016/04/15/reverse-engineering-the-salesforce-site-login-process/
function Invoke-Login {
    [CmdletBinding()]
    param ()

    Write-Verbose "Logging into site"

    Write-Debug "Connecting to $LoginUrl"
    $login = Invoke-WebRequest -Uri $LoginUrl -WebSession $session

    ## THIS IS FOR PS 5 ##
    #$login.Forms[0].Fields['loginPage:loginForm:username'] = 'rogin@asrcfederal.com.nextgen'
    #$login.Forms[0].Fields['loginPage:loginForm:password'] = 'passwordhere'
    # copy over the hidden ViewState fields so they'll be sent in the response
    #$login.Forms[0].Fields['com.salesforce.visualforce.ViewState'] = $login.InputFields.FindById('com.salesforce.visualforce.ViewState').value
    #$login.Forms[0].Fields['com.salesforce.visualforce.ViewStateVersion'] = $login.InputFields.FindById('com.salesforce.visualforce.ViewStateVersion').value
    #$login.Forms[0].Fields['com.salesforce.visualforce.ViewStateMAC'] = $login.InputFields.FindById('com.salesforce.visualforce.ViewStateMAC').value

    #$content = @{
    #    'loginPage:loginForm:username' = 'rogin@asrcfederal.com.nextgen'
    #    'loginPage:loginForm:password' = 'passwordHere'
    #    'com.salesforce.visualforce.ViewState' = $login.InputFields.FindById('com.salesforce.visualforce.ViewState').value
    #    'com.salesforce.visualforce.ViewStateVersion' = $login.InputFields.FindById('com.salesforce.visualforce.ViewStateVersion').value
    #    'com.salesforce.visualforce.ViewStateMAC' = $login.InputFields.FindById('com.salesforce.visualforce.ViewStateMAC').value
    #}

    #$loginResponse = Invoke-WebRequest -Uri $login.Forms[0].Action -Method Post -Body $login.Forms[0].Fields -WebSession $session

    $creds = ObtainCredentials

    # all the fields we'll be sending
    $content = @{}
    $content.Add('loginPage:loginForm:username', $creds.username)
    $content.Add('loginPage:loginForm:password', $creds.password)
    # must exist
    $content.Add('loginPage:loginForm', 'loginPage:loginForm')
    $content.Add('loginPage:loginForm:loginButton', 'Login')
    $content.Add('loginPage:loginForm:rememberMeCheckbox', 'on')
    # copy over the hidden ViewState fields
    $content.Add('com.salesforce.visualforce.ViewState', $login.InputFields.FindById('com.salesforce.visualforce.ViewState').value)
    $content.Add('com.salesforce.visualforce.ViewStateVersion', $login.InputFields.FindById('com.salesforce.visualforce.ViewStateVersion').value)
    $content.Add('com.salesforce.visualforce.ViewStateMAC', $login.InputFields.FindById('com.salesforce.visualforce.ViewStateMAC').value)

    # extract the form's Action? worked fine so far without
    #$action = 'https://www.community.nextgen.com/SuccessCommunityLogin?refURL=http%3A%2F%2Fwww.community.nextgen.com%2Fapex%2FSuccessCommunityLogin'
    $action = $LoginUrl
    Write-Debug "POSTing login credentials to $action"
    # post the login request
    $loginResponse = Invoke-WebRequest -Uri $action -Method Post -Body $content -WebSession $session

    Write-Debug "Parsing javascript"
    #parse window.location.href from javascript in $loginResponse.Content
    #ex. https://www.community.nextgen.com/secur/frontdoor.jsp?allp=1&apv=1&cshc=y000005LbAH00000007MP6&refURL=https%3A%2F%2Fwww.community.nextgen.com%2Fsecur%2Ffrontdoor.jsp&retURL=%2Fapex%2FMainCommunityLanding&sid=00D400000007MP6%21ARYAQFEjuQtfFH4xlA5bhl7aZ0QQsqgvqHx8JQse8kagSX4XhOXRTRxMUdJ2qwdAfvmDKeRRnBsKuYpp8MlGaxmIQTDt11UB&untethered=
    $extractedHref = parseJavascript $loginResponse.Content ";"

    Write-Debug "Invoking $extractedHref"
    # call the href that was in the javascript
    $webResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session

    Write-Debug "Parsing javascript"
    #again, parse window.location.href from javascript in $webResponse.Content
    #ex. '/apex/MainCommunityLanding'
    $extractedHref = $BaseUrl + (parseJavascript $webResponse.Content "}")

    Write-Debug "Invoking $extractedHref"
    # call the href that was in the javascript
    Invoke-WebRequest -Uri $extractedHref -WebSession $session | Out-Null
}

#for a given wall of text, parse the value of 'window.location.href'
function parseJavascript($text, $lineDelimiter) {
    # find where we will anchor our start
    $hrefIndex = $text.IndexOf('window.location.href')
    # find end of line using provided delimiter
    $semiIndex = $text.IndexOf($lineDelimiter, $hrefIndex)
    # pull the sub text to work with a small section
    $subtext = $text.Substring($hrefIndex, $semiIndex - $hrefIndex)
    # normalize by replacing double quotes with single quotes
    $subtext = $subtext -replace '"', "'"
    # from the tick, find the start of URL value
    $urlIndex = $subtext.IndexOf("'") + 1
    #from the URL value, find the final tick that ends the declaration
    $endTickIndex = $subtext.IndexOf("'", $urlIndex)
    #from the URL value, parse a count that will exclude the tick
    $subtext.Substring($urlIndex, $endTickIndex - $urlIndex)
}

function Select-PluginLinks {
    [CmdletBinding()]
    param ()

    Write-Verbose "Selecting plugin links"

    Write-Debug "Invoking $PluginListUrl"
    $WebContent = Invoke-WebRequest -Uri $PluginListUrl -WebSession $session | ConvertFrom-Html

    # find the links where the href contains 'articles' as the others link to the Support Levels
    $links = $WebContent.SelectNodes("//div[@class='pbBody']//tbody//td//span//a[contains(@href, 'articles')]")

    Write-Debug "Found $($links.Count) links"

    #limit plugins to those we want
    #user can provide an empty list indicating all plugins
    if($PluginNames.Count -eq 0) {
        Write-Debug "Returning all plugins"
        $links
    } else {
        @($links | Where-Object -FilterScript {$PluginNames -contains $_.InnerText.Trim()})
    }
}

function Read-PluginPage {
    [CmdletBinding()]
    param (
        # Node containing plugin download link
        [Parameter(Mandatory,Position=0,ValueFromPipeline=$true)]
        [HtmlAgilityPack.HtmlNode]
        $Node,
        # switch to include attachments along with the plugin
        [switch]
        $IncludeAttachments
    )

    Process {
        Write-Verbose "Processing '$($Node.InnerText)', `$IncludeAttachments=$IncludeAttachments"

        $href = $Node.GetAttributeValue('href', 'missing-href-value-1')

        if($href -eq 'missing-href-value-1') {
            Write-Warning "Could not find href value for $($Node.InnerText) - you likely don't have the correct support level, skipping"
        } else {
            #noticed this wall with 'Mirth Results Connector' and 'Health Data Hub Connector'
            #check for nextgenhealthcare.lightning.force.com which redirects to salesforce.com
            if($href -match 'lightning.force.com') {
                Write-Warning "Unable to download plugin $($Node.InnerText) as it requires a salesforce.com account, skipping"
            } else {
                $href = $BaseUrl + $href

                Write-Debug "Invoking plugin `$href=$href"
                $WebContent = Invoke-WebRequest -Uri $href -WebSession $session | ConvertFrom-Html

                $pluginDownloadLinks = $WebContent.SelectNodes("(//div[@class='pbSubsection'])[6]//table[@class='htmlDetailElementTable']//td//a")

                #example text: "Advanced Alerting  Plug-in 4.2"
                $pluginDownloadLinks = @($pluginDownloadLinks | Where-Object {$_.InnerText.Trim().EndsWith($PluginVersion)})

                Write-Verbose "Found $($pluginDownloadLinks.Count) links matching version '$PluginVersion'"
                
                if($pluginDownloadLinks.Count -eq 0) {
                    Write-Warning "Failed to find version '$PluginVersion' of $($Node.InnerText)"
                } elseif($pluginDownloadLinks.Count -gt 1) {
                    Write-Error "Found $($pluginDownloadLinks.Count) download links for version '$PluginVersion' of $($Node.InnerText), expected 1"
                } else {
                    $NameAndVersion = $pluginDownloadLinks[0].InnerText.Trim()

                    #ex. https://www.community.nextgen.com/apex/ResourceRepository?fileId=a9o4y000000YIdT
                    $downloadUrl = $pluginDownloadLinks[0].GetAttributeValue('href', 'missing-href-value-2')

                    Write-Debug "Beginning download of plugin '$NameAndVersion' from $downloadUrl"

                    $downloadResponse = Invoke-WebRequest -Uri $downloadUrl -WebSession $session
                    #parse window.location.href from javascript in $downloadResponse.Content
                    #ex. /DownloadSuccess?fileId=a9o4y000000YId9
                    Write-Debug "Parsing javascript"
                    $extractedHref = $BaseUrl + (parseJavascript $downloadResponse.Content ";")

                    Write-Debug "Invoking $extractedHref"

                    # call the href that was in the javascript
                    $secondResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session | ConvertFrom-Html
                    
                    #if the plugin is at Support Level "Platinum Only", of which I don't have,
                    #then the link will send us to a forbidden page that will fail parsing for the hidden "a" tag below.
                    $hiddenLink = $secondResponse.SelectSingleNode("//a[@class='hidden']")

                    if($null -eq $hiddenLink) {
                        Write-Warning "Failed to find download link - you likely don't have the correct support level, skipping"
                    } else {
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

        if($IncludeAttachments) {
            # download all attachments
            $attachments = $WebContent.SelectNodes("(//div[@class='pbSubsection'])[7]//table[@class='detailList']//a")

            foreach ($attachment in $attachments) {
                $filename = $attachment.InnerText.Trim()

                if($filename -eq '') {
                    Write-Warning "Attachment filename is empty, skipping"
                } else {
                    if(-not $filename.EndsWith(".pdf")) {
                        Write-Verbose "Appending .pdf to filename"
                        $filename += ".pdf"
                    }

                    Write-Verbose "Downloading attachment '$filename'"
                    $href = $BaseUrl + $attachment.GetAttributeValue('href', 'missing-attachment-href-value')

                    Write-Debug "`$filename=$filename, `$href=$href"

                    Invoke-WebRequest -Uri $href -WebSession $session -OutFile $filename
                }
            }
        }
    }
}

function Start-Scrape {
    [CmdletBinding()]
    param ()

    begin {
        $StoredPSDefaultParameterValues = $PSDefaultParameterValues.Clone()
        $StoredProgressPreference = $ProgressPreference
        
        # quiet this chatty portion
        $PSDefaultParameterValues.Add('Invoke-WebRequest:Debug', $False)
        $PSDefaultParameterValues.Add('Invoke-WebRequest:Verbose', $False)

        $ProgressPreference = 'SilentlyContinue'
    }

    process {
        Invoke-Login

        $pluginLinks = Select-PluginLinks
        
        $pluginLinks | Read-PluginPage -IncludeAttachments:$IncludeAttachments
    }

    end {
        $PSDefaultParameterValues = $StoredPSDefaultParameterValues
        $ProgressPreference = $StoredProgressPreference
    }
}

Start-Scrape -Debug -Verbose