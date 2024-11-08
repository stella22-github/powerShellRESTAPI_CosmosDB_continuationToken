process {
    # Variables
    $endpointUrl = "https://xxxx.documents.azure.com/"
    $databaseName = "NutritionDatabase"
    $containerName = "FoodCollection"
    $apiVersion = "2018-12-31"
    $query = "SELECT * FROM c" 
    $verb = "POST"
    $resourceType = "docs"
    $resourceLink = "dbs/$databaseName/colls/$containerName" 
    $primaryKey = 'xxxxx'
    $continuationToken = $null
    $allDocuments = @()

    function Get-CosmosDbAuthorizationToken {
        param (
            [string]$verb,
            [string]$resourceType,
            [string]$resourceLink,
            [string]$date,
            [string]$primaryKey
        )

        $keyType = "master"
        $tokenVersion = "1.0"
        $payload = "$($verb.ToLowerInvariant())`n$($resourceType.ToLowerInvariant())`n$resourceLink`n$($date.ToLowerInvariant())`n`n"
        Write-Host "Authorization Payload: $payload"  # Debugging line to verify payload
        $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256
        $hmacSha256.Key = [Convert]::FromBase64String($primaryKey)
        $hashPayload = $hmacSha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
        $signature = [Convert]::ToBase64String($hashPayload)
        $authHeader = [System.Net.WebUtility]::UrlEncode("type=$keyType&ver=$tokenVersion&sig=$signature")
        return $authHeader
    }

    do {
        $date = (Get-Date).ToUniversalTime().ToString("R")
        $authToken = Get-CosmosDbAuthorizationToken -verb $verb -resourceType $resourceType -resourceLink $resourceLink -date $date -primaryKey $primaryKey

        # Headers
        $headers = @{
            "Authorization"                              = $authToken
            "x-ms-date"                                  = $date
            "x-ms-version"                               = $apiVersion
            "Content-Type"                               = "application/query+json"
            "x-ms-documentdb-query-enablecrosspartition" = "true"
        }
        
        if ($continuationToken) {
            Write-Host "Using continuation token: $continuationToken"
            $headers["x-ms-continuation"] = $continuationToken
        }

        $bodyJson = @{ query = $query } | ConvertTo-Json -Compress
        
        try {
            $response = Invoke-WebRequest -Method $verb -Uri "$endpointUrl$resourceLink/docs" -Headers $headers -Body $bodyJson
            $responseJson = $response | ConvertFrom-Json

            if ($responseJson.Documents.Count -gt 0) {
                $allDocuments += $responseJson.Documents
                Write-Host "Documents retrieved in this batch: $($responseJson.Documents.Count)"
            }

            $continuationToken = $response.Headers["x-ms-continuation"]
    
        }
        catch {
            Write-Host "Error: $($_.Exception.Message)"
            }
        
    } while ($continuationToken)

    Write-Host "Total documents retrieved: $($allDocuments.Count)"
    $allDocuments | ConvertTo-Json -Depth 10 | Out-File "D:\CosmosDBDocuments4.json"
    Write-Host "All documents saved to CosmosDBDocuments4.json"
}

