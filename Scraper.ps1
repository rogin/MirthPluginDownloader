# list of plugins to download
$PluginNames = @('LDAP Authentication','Role-Based Access Control Plug-In', 'SSL Manager Plug-In', 'Multi-Factor Authentication')
# version to download
$PluginVersion = "3.12"

$BaseUrl = "https://www.community.nextgen.com"
$LoginUrl = $BaseUrl + "/apex/SuccessCommunityLogin"
$PluginListUrl = $BaseUrl + "/optimization/articles/Hot_Topic/Mirth-Plug-In-Central"

Import-Module powerhtml

# this will hold our cookies and be used in (most) web requests
$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

#currently obtains creds via rogin's 1password-cli integration
function ObtainCredentials {
    Invoke-Expression $(op signin)
    
    #hard-coded UUID from rogin's account
    $json = op get item 'j5m7piroikq3dznzojyjmodyja' --fields username,password | ConvertFrom-Json
    
    op signout

    $json
}

# verified my work with his - https://xceptionale.wordpress.com/2016/04/15/reverse-engineering-the-salesforce-site-login-process/
function SiteLogin {
    $creds = ObtainCredentials

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
    # post the login request
    $loginResponse = Invoke-WebRequest -Uri $action -Method Post -Body $content -WebSession $session

    #parse window.location.href from javascript in $loginResponse.Content
    #ex. https://www.community.nextgen.com/secur/frontdoor.jsp?allp=1&apv=1&cshc=y000005LbAH00000007MP6&refURL=https%3A%2F%2Fwww.community.nextgen.com%2Fsecur%2Ffrontdoor.jsp&retURL=%2Fapex%2FMainCommunityLanding&sid=00D400000007MP6%21ARYAQFEjuQtfFH4xlA5bhl7aZ0QQsqgvqHx8JQse8kagSX4XhOXRTRxMUdJ2qwdAfvmDKeRRnBsKuYpp8MlGaxmIQTDt11UB&untethered=
    $extractedHref = parseJavascript $loginResponse.Content ";"

    # call the href that was in the javascript
    $webResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session

    #again, parse window.location.href from javascript in $webResponse.Content
    #ex. '/apex/MainCommunityLanding'
    $extractedHref = $BaseUrl + (parseJavascript $webResponse.Content "}")

    # call the href that was in the javascript
    $finalResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session
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

function GetPluginLinks {
    $WebContent = Invoke-WebRequest -Uri $PluginListUrl -WebSession $session | ConvertFrom-Html

    # find the links where the href contains 'articles' as the others link to the Support Levels
    $links = $WebContent.SelectNodes("//div[@class='pbBody']//tbody//td/span/a[contains(@href, 'articles')]")

    #limit plugins to those we want
    return $links | where -FilterScript {$PluginNames -contains $_.InnerText.Trim()}
}

function GetPluginPage {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory,Position=0,ValueFromPipeline=$true)]
        [HtmlAgilityPack.HtmlNode]
        $Node
    )

    Process {
        Write-Host ("Processing '{0}'" -f $Node.InnerText)

        $href = $BaseUrl + $Node.GetAttributeValue('href', 'missing-href-value-1')
        $WebContent = Invoke-WebRequest -Uri $href -WebSession $session | ConvertFrom-Html

        # download attachments, only take the top one
        $attachment = $WebContent.SelectNodes("//div[@class='custom-attachments']//table//a") | select -First 1

        if ($null -ne $attachment) {
            $filename = $attachment.InnerText.Trim()

            if($filename -ne '') {
                Write-Host ("Downloading attachment '{0}'" -f $filename)
                $href = $BaseUrl + $attachment.GetAttributeValue('href', 'missing-attachment-href-value')
                
                Invoke-WebRequest -Uri $href -WebSession $session -OutFile $filename
            }
        }
        
        # pull the table, expect garbage from the table above it as well
        $spans = $WebContent.SelectNodes("//div[@class='sfdc_richtext']//tbody/tr/td/span")

        #TODO what if we're early and the version we want is missing?

        # trim the fluff, the first row for processing which should contain the latest plugin version
        while ($spans[0].InnerText.Trim() -ne $PluginVersion) {
            $spans = $spans | select -Skip 1
        }

        #span order: version, release date, download link
        
        $version = $spans[0].InnerText
        $releaseDate = $spans[1].InnerText
        Write-Host ("Downloading version '{0}' released {1}" -f ($version, $releaseDate))

        #ex. https://www.community.nextgen.com/apex/ResourceRepository?fileId=a9o4y000000YIdT
        $downloadUrl = $spans[2].SelectSingleNode("./a").GetAttributeValue('href', 'missing-href-value-2')

        $downloadResponse = Invoke-WebRequest -Uri $downloadUrl -WebSession $session
        #parse window.location.href from javascript in $downloadResponse.Content
        #ex. /DownloadSuccess?fileId=a9o4y000000YId9
        $extractedHref = $BaseUrl + (parseJavascript $downloadResponse.Content ";")

        # call the href that was in the javascript
        $secondResponse = Invoke-WebRequest -Uri $extractedHref -WebSession $session | ConvertFrom-Html
		
		#TODO if the plugin is at Support Level "Platinum Only" which we don't have, then the link will send us to a forbidden page that will fail parsing for the hidden "a" tag below

        # extract final HREF
        # ex. https://nextgen-aws-salesforce-prod-sdrive-us-east-2.s3.us-east-2.amazonaws.com/a9o4y000000YId9AAG/ldap-3.12.0.b1752.zip?X-Amz-Algorithm=AWS4-HMAC-SHA256&amp;X-Amz-Credential=AKIA2ZO6ZFSFWXJS7NWF%2F20220318%2Fus-east-2%2Fs3%2Faws4_request&amp;X-Amz-Date=20220318T051704Z&amp;X-Amz-Expires=216000&amp;X-Amz-SignedHeaders=host&amp;X-Amz-Signature=962a48d81f6091b86855eb2041df9bd0ba3123479ac87cc860bc061aa82edaff
        $extractedHref = $secondResponse.SelectSingleNode("//a[@class='hidden']").GetAttributeValue('href', 'missing-href-value-3')
        # decode this or else the AWS call will fail
        [uri]$decodedHref = [System.Web.HttpUtility]::HtmlDecode($extractedHref)
        # extract filename
        $filename = $decodedHref.Segments[-1]

        # call the href that was in the javascript
        Invoke-WebRequest -Uri $decodedHref.AbsoluteUri -OutFile $filename
    }
}

function Scrape {
    SiteLogin

    $pluginLinks = GetPluginLinks
    
    $pluginLinks | GetPluginPage
}

Scrape