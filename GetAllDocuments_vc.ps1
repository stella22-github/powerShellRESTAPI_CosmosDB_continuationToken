# Variables
$databaseName = "yourDatabaseName"
$containerName = "yourContainerName"
$primaryKey = "accountKey"
$endpointUrl = "https://xxxx.documents.azure.com/"
$query = "SELECT * FROM c"
$resourceLink = "dbs/$databaseName/colls/$containerName"
$apiVersion = "2018-12-31"
$verb = "POST"
$resourceType = "docs"

# Function to create authorization token
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

# Pagination variables
$continuationToken = $null
$allDocuments = @()

do {
    $date = (Get-Date).ToUniversalTime().ToString("R")
    $authToken = Get-CosmosDbAuthorizationToken -verb $verb -resourceType $resourceType -resourceLink $resourceLink -date $date -primaryKey $primaryKey
    
    # Headers
    $headers = @{
        "Authorization" = $authToken
        "x-ms-date" = $date
        "x-ms-version" = $apiVersion
        "Content-Type" = "application/query+json"
        "x-ms-documentdb-query-enablecrosspartition" = "true"  # Enable cross-partition queries
       # "x-ms-documentdb-partitionkey" = "null"  # Add partition key header if needed, or "null" for cross-partition
    }

    # Add continuation token if available
    if ($continuationToken) {
        Write-Host "Using continuation token: $continuationToken"  # Debugging line to verify continuation token
        $headers["x-ms-continuation"] = $continuationToken
    }

    # Body
    $body = @{
        "query" = $query
    }
    $bodyJson = $body | ConvertTo-Json -Compress

    # Make the REST API call
    try {
        $response = Invoke-WebRequest -Method $verb -Uri "$endpointUrl$resourceLink/docs" -Headers $headers -Body $bodyJson -ContentType "application/query+json"
        
        # Parse the response content
        $responseJson = $response.Content | ConvertFrom-Json

        # Check if the response contains documents
        if ($responseJson.Documents -is [System.Collections.IEnumerable] -and $responseJson.Documents.Count -gt 0) {
            $allDocuments += $responseJson.Documents
            Write-Host "Documents in current page: $($responseJson.Documents.Count)"
        } else {
            Write-Host "No documents found in the current response."
        }

        # Retrieve the continuation token for the next page, if available
        $continuationToken = $response.Headers["x-ms-continuation"]
        Write-Host "Continuation Token: $($continuationToken)"

    } catch {
        Write-Host "Error: $($_.Exception.Message)"
        if ($_.Exception.Response -ne $null) {
            # Log the raw error response
            $stream = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $errorResponse = $stream.ReadToEnd()
            Write-Host "Error Content: $errorResponse"
        } else {
            Write-Host "No response body available."
        }
        break
    }

} while ($continuationToken)  # Continue until no continuation token is returned

# Output results
Write-Host "Total documents retrieved: $($allDocuments.Count)"
#$allDocuments | ForEach-Object { Write-Output $_ }

# Optional: Save all documents to a JSON file
$allDocuments | ConvertTo-Json -Depth 10 | Out-File "D:\CosmosDBDocuments2.json"
Write-Host "All documents saved to CosmosDBDocuments2.json"